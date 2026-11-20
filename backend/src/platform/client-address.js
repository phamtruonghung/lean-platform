/*
 * The caller's own address, for the two places that need one: `trust proxy`
 * (src/index.js) and the sign-in throttle (modules/people/login-throttle.js).
 *
 * ## Why the socket address is not the caller
 *
 * Production serves the API behind a proxy chain — Cloudflare's edge, the
 * `cloudflared` tunnel on the host, the nginx container — so the socket peer is
 * the last proxy and identical for every caller. Counting sign-in failures per
 * socket therefore counts the whole plant as one client: about twenty
 * unauthenticated requests pause sign-in for everybody, and a password spray is
 * never attributed to the machine doing it (audit finding F3).
 *
 * ## Which address is believed, and when
 *
 * `CF-Connecting-IP` is the header Cloudflare's edge sets to the caller's
 * address. The edge overwrites whatever the client sent, and both `cloudflared`
 * and nginx pass it through unchanged, so the value describes the first hop and
 * not the sender. It is believed ONLY when the socket peer is one of the
 * configured proxies AND the value parses as an IP address. A request from any
 * other peer is called by `req.ip`, which — with that peer outside the trusted
 * list — is the socket address itself, headers ignored.
 *
 * That is the whole rule, and it is what the old `trust proxy 1` got wrong: a
 * hop COUNT trusts whoever is on the wire, so on a port a caller can reach
 * directly (the development stack publishes 8002) the caller's own
 * X-Forwarded-For becomes `req.ip` and every header is a fresh, chosen bucket.
 * Trusting by ADDRESS cannot be talked into that: a peer that is not in the
 * list controls nothing this file reads.
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
const HEADER = 'cf-connecting-ip';

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

/*
 * The address to count: the tunnel header when the request arrived from a proxy
 * in the list, otherwise the address the connection itself came from.
 */
function clientAddress(req) {
  const peer = req.socket?.remoteAddress ?? null;

  if (isTrustedProxy(peer)) {
    const forwarded = req.get(HEADER);
    const claimed = typeof forwarded === 'string' ? forwarded.trim() : '';
    if (net.isIP(claimed) !== 0) return normalise(claimed);
  }

  return normalise(req.ip || peer || 'unknown');
}

module.exports = { clientAddress, isTrustedProxy };
