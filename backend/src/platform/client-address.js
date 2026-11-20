/*
 * The caller's own address, for the two places that need one: `trust proxy`
 * (src/index.js) and the sign-in throttle (modules/people/login-throttle.js).
 *
 * ## Why the socket address is not the caller
 *
 * Production serves the API behind a proxy chain — Cloudflare's edge, the
 * `cloudflared` service on the host, the `platform-edge` nginx container, this
 * API — so the socket peer is the last proxy and identical for every caller.
 * Counting sign-in failures per socket therefore counted the whole plant as one
 * client: about twenty unauthenticated requests paused sign-in for everybody,
 * and a password spray was never attributed to the machine doing it (audit
 * finding F3).
 *
 * ## Which address is believed, and who decides
 *
 * The hop the header comes from was the hole in the first attempt at this fix.
 * `platform-edge` publishes `0.0.0.0:80` on the plant LAN and passed through
 * whatever `CF-Connecting-IP` a caller sent, so a caller that reached the edge
 * without Cloudflare wrote its own bucket — nine failures with nine fresh
 * addresses and never a 429. A header is only worth what the hop that OVERWROTE
 * it is worth, and no backend can tell an overwritten header from a caller's.
 *
 * So the edge decides, once per request, in dev/edge.nginx.conf — the copy of
 * that file running on CT102 is the production edge. A socket peer that is the
 * tunnel connector is tunnel traffic and its Cloudflare-supplied
 * `CF-Connecting-IP` is the caller; any other peer is a direct caller, and its
 * own `$remote_addr` is the caller. The edge writes that answer into ONE
 * header, `X-Client-IP`, which it always overwrites, and it REPLACES
 * `X-Forwarded-For` with the same value — a list a caller can prepend to never
 * survives the edge.
 *
 * This module reads that header and no other, and only for a request whose
 * socket peer is in CLIENT_TRUSTED_PROXIES — the proxy hops whose word may be
 * believed; a peer outside that list controls nothing here, it is simply the
 * caller. The header is believed only when it matches the address the hop
 * nearest this API appended to `X-Forwarded-For`, i.e. the last entry of that
 * list, which is the one address in it a caller cannot write. Agreement is what
 * keeps the fix safe in the window before the edge is updated: the edge
 * deployed today sets no `X-Client-IP` and forwards a caller's one untouched,
 * and that caller's value cannot match what the edge itself appended.
 *
 * Until that edge is reloaded, the appended address is the connector's, so the
 * throttle is coarse — one bucket for the tunnel — rather than caller-chosen.
 * That is the origin/main behaviour, which could not be spoofed either; the
 * per-client half of F3 needs the edge change as much as this file.
 *
 * That is also what the old `trust proxy 1` got wrong: a hop COUNT trusts
 * whoever is on the wire, so on a port a caller can reach directly (the
 * development stack publishes 8002) the caller's own X-Forwarded-For became
 * `req.ip`, and on the deployed chain it took the connector. `trust proxy` is
 * still set, from the same list, for anything that reads `req.ip`; the throttle
 * does not, because a walk that trusts every hop continues past our own hops
 * into a list the caller prepended to.
 *
 * The list is CLIENT_TRUSTED_PROXIES — comma-separated addresses or CIDRs, read
 * on every call so a deployment can narrow it without a rebuild. Its default is
 * the measured path and nothing wider: loopback (a proxy on the same host) and
 * Docker's bridge space 172.16.0.0/12, which is where the deployed edge sits —
 * measured on production as the `platform-edge` container at 172.18.0.3 on
 * 172.18.0.0/16. Every address in the list is allowed to name itself, so the
 * list is kept as small as the deployment permits; a plant that knows its edge
 * network can say `CLIENT_TRUSTED_PROXIES=172.18.0.0/16` and be narrower than
 * the default.
 */

const net = require('node:net');
const { log } = require('./log');

const ENV = 'CLIENT_TRUSTED_PROXIES';
const DEFAULT_TRUSTED_PROXIES = '127.0.0.0/8,::1/128,172.16.0.0/12';
// Written by the edge, always overwritten by it: see the header comment.
const HEADER = 'x-client-ip';

let parsedFrom = null;
let parsedList = null;

// Parsed once per distinct setting rather than per request: the throttle reads
// env on every call, and re-parsing a CIDR list on each sign-in attempt would
// buy nothing.
function parse(raw) {
  const list = new net.BlockList();
  for (const entry of raw.split(',')) {
    const text = entry.trim();
    if (text === '') continue;

    const slash = text.indexOf('/');
    const address = slash === -1 ? text : text.slice(0, slash);
    const family = net.isIP(address);
    const bits = family === 4 ? 32 : 128;
    const prefix = slash === -1 ? bits : Number(text.slice(slash + 1));

    if (family === 0 || !Number.isInteger(prefix) || prefix < 0 || prefix > bits) {
      // Ignored, not fatal: the safe direction is to trust less, and one typo
      // must not take the API down. Logged once per distinct setting, because
      // silence here is a deployment quietly falling back to `req.ip`.
      log('error', 'ignoring a malformed CLIENT_TRUSTED_PROXIES entry', { entry: text });
      continue;
    }

    const type = family === 4 ? 'ipv4' : 'ipv6';
    if (prefix === bits) list.addAddress(address, type);
    else list.addSubnet(address, prefix, type);
  }
  return list;
}

function trustedProxies() {
  const raw = (process.env[ENV] ?? '').trim() || DEFAULT_TRUSTED_PROXIES;
  if (raw !== parsedFrom) {
    parsedList = parse(raw);
    parsedFrom = raw;
  }
  return parsedList;
}

/*
 * True when `address` is a proxy hop whose headers may be believed. This is
 * also the `trust proxy` function, which Express calls once per hop — the socket
 * first, then each X-Forwarded-For entry from the nearest outwards — so the
 * resolved `req.ip` stops at the first address that is not in the list.
 *
 * A dual-stack listener reports an IPv4 peer as `::ffff:172.18.0.3`; net's
 * BlockList matches that against an IPv4 subnet, which is why it is used here
 * rather than a hand-written CIDR comparison.
 */
function isTrustedProxy(address) {
  const family = typeof address === 'string' ? net.isIP(address) : 0;
  if (family === 0) return false;
  return trustedProxies().check(address, family === 4 ? 'ipv4' : 'ipv6');
}

// An IPv4 address written as an IPv4-mapped IPv6 one is the same client, and
// must not be given a second bucket of its own.
function normalise(address) {
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(address);
  return mapped ? mapped[1] : address;
}

// A usable address from the edge's header, or null. One address, not a list:
// the edge replaces X-Forwarded-For, and nothing else it sends is read here.
function claimedAddress(req) {
  const value = req.get?.(HEADER);
  const text = typeof value === 'string' ? value.trim() : '';
  return net.isIP(text) === 0 ? null : normalise(text);
}

// The last entry of X-Forwarded-For: the address the hop nearest this API
// appended to the list, and the only entry it did not inherit from the caller.
function appendedAddress(req) {
  const value = req.get?.('x-forwarded-for');
  if (typeof value !== 'string') return null;
  const hops = value.split(',').map((part) => part.trim()).filter(Boolean);
  const last = hops[hops.length - 1];
  return last && net.isIP(last) !== 0 ? normalise(last) : null;
}

/*
 * The address to count: the one the edge says it counted the request as. A
 * request from any peer outside the trusted list is called by that peer,
 * headers ignored.
 */
function clientAddress(req) {
  const peer = req.socket?.remoteAddress ?? null;
  if (!isTrustedProxy(peer)) return normalise(peer || 'unknown');

  // What our nearest hop saw, whatever the caller prepended to the list. On the
  // edge as configured by dev/edge.nginx.conf this is the classified client;
  // on the edge deployed today it is the connector, which is why F3's
  // plant-wide bucket survives until that edge is reloaded — coarse, and not a
  // bucket a caller chose.
  const appended = appendedAddress(req) ?? normalise(peer || 'unknown');
  const named = claimedAddress(req);

  // The edge's word stands only when it is the same address the hop chain
  // carries. The edge that writes X-Client-IP writes both; a caller writing the
  // header alone cannot move what our own hop appended, so its claim disagrees
  // and is dropped. That is what makes this safe in the window before the edge
  // is updated, when today's edge forwards a caller-written header untouched.
  return named && named === appended ? named : appended;
}

module.exports = { clientAddress, isTrustedProxy };
