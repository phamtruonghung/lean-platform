/*
 * platform/client-address.js: which address a request is counted as, and when a
 * forwarding header may be believed. Pure; needs no database and no server.
 *
 * The arrangements here are the ones measured on the deployment: the edge as
 * dev/edge.nginx.conf now configures it, the edge as it runs today (which sets
 * no X-Client-IP and forwards a caller's one untouched), a direct caller on the
 * published port, and a caller that writes every forwarding header itself.
 */

const test = require('node:test');
const assert = require('node:assert');
const { clientAddress, isTrustedProxy } = require('../src/platform/client-address');

const ENV = 'CLIENT_TRUSTED_PROXIES';
const EDGE = '172.18.0.3'; // the platform-edge container, as measured on production
const GATEWAY = '172.18.0.1'; // what Docker's published port shows the edge
const CLIENT = '203.0.113.5'; // the address Cloudflare names

function withProxies(value, run) {
  const saved = process.env[ENV];
  process.env[ENV] = value;
  try {
    return run();
  } finally {
    if (saved === undefined) delete process.env[ENV];
    else process.env[ENV] = saved;
  }
}

// The parts of an Express request this module reads.
function request(peer, headers = {}) {
  const lower = Object.fromEntries(
    Object.entries(headers).map(([name, value]) => [name.toLowerCase(), value])
  );
  return {
    socket: { remoteAddress: peer },
    get: (name) => lower[String(name).toLowerCase()]
  };
}

test('the default proxy list is loopback and Docker bridge space, and no wider', () => {
  for (const address of ['127.0.0.1', '::1', '::ffff:127.0.0.1', '172.18.0.3']) {
    assert.strictEqual(isTrustedProxy(address), true, `${address} is the measured hop`);
  }
  // A public address is never a proxy hop, and neither is a private range the
  // deployment was not measured on: trusting one would be trusting more than
  // this repository can point at.
  for (const address of ['203.0.113.9', '10.1.2.3', '192.168.1.50', 'not-an-address', '', null]) {
    assert.strictEqual(isTrustedProxy(address), false, `${address} must not be trusted`);
  }
});

test('tunnel traffic is counted per client, through the edge as now configured', () => {
  // What dev/edge.nginx.conf sends on: the classified client in X-Client-IP and
  // in the replaced X-Forwarded-For, with Cloudflare's own CF-Connecting-IP
  // still present.
  const first = request(EDGE, {
    'x-client-ip': CLIENT,
    'x-forwarded-for': CLIENT,
    'cf-connecting-ip': CLIENT
  });
  const second = request(EDGE, {
    'x-client-ip': '203.0.113.6',
    'x-forwarded-for': '203.0.113.6',
    'cf-connecting-ip': '203.0.113.6'
  });
  assert.strictEqual(clientAddress(first), CLIENT);
  assert.strictEqual(clientAddress(second), '203.0.113.6', 'a second client, a second bucket');
});

test('through the edge as it runs today the count is coarse, and never caller-chosen', () => {
  // Today's edge appends to X-Forwarded-For and sets no X-Client-IP, so the last
  // entry is what it appended: the connector, seen through Docker's published
  // port as the gateway. That is F3's plant-wide bucket — the half of the fix
  // that needs the edge reloaded — and it is still not a bucket anyone chose.
  const tunnel = request(EDGE, { 'x-forwarded-for': `${CLIENT}, ${GATEWAY}`, 'cf-connecting-ip': CLIENT });
  assert.strictEqual(clientAddress(tunnel), GATEWAY);
});

test('a caller-written X-Client-IP is dropped when the hop chain does not carry it', () => {
  // The round-1 defect as a unit: the header alone, from a caller that reached
  // the edge without Cloudflare.
  const req = request(EDGE, { 'x-client-ip': '198.51.100.99', 'x-forwarded-for': GATEWAY });
  assert.strictEqual(clientAddress(req), GATEWAY, 'the connector, not the claim');
});

test('a caller cannot pick a bucket by rotating every header it writes', () => {
  // Five attempts, a fresh claim on each: one answer, because none of the
  // claims is what the nearest hop appended.
  const seen = new Set();
  for (let i = 1; i <= 5; i += 1) {
    const req = request(EDGE, {
      'x-client-ip': `198.51.100.${i}`,
      'cf-connecting-ip': `198.51.100.${i}`,
      // A caller's entries are to the LEFT of what the edge appends.
      'x-forwarded-for': `198.51.100.${i}, ${GATEWAY}`
    });
    seen.add(clientAddress(req));
  }
  // The list a caller prepends to is not read either: the last entry is the
  // edge's own, so even a prepended address that ends up in the list is not
  // what the request is counted as.
  assert.deepStrictEqual([...seen], [GATEWAY], 'five claims, one bucket');
});

test('a header sent by a peer that is not the proxy is ignored', () => {
  // A caller that reached the backend itself — the development stack publishes
  // 8002 — claiming to be someone else, with every header it owns.
  const req = request('198.51.100.40', {
    'x-client-ip': CLIENT,
    'x-forwarded-for': '203.0.113.6',
    'cf-connecting-ip': '203.0.113.7'
  });
  assert.strictEqual(clientAddress(req), '198.51.100.40');
});

test('a trusted hop with no usable headers falls back to the hop itself', () => {
  assert.strictEqual(clientAddress(request(EDGE)), EDGE);
  for (const bad of ['', 'unknown', '203.0.113.5, 198.51.100.7', '203.0.113.300']) {
    const req = request(EDGE, { 'x-client-ip': bad, 'x-forwarded-for': GATEWAY });
    assert.strictEqual(clientAddress(req), GATEWAY, `header ${JSON.stringify(bad)}`);
  }
});

test('an IPv4-mapped address is the same client as its IPv4 form', () => {
  const viaHeader = request('::ffff:172.18.0.3', {
    'x-client-ip': '::ffff:203.0.113.5',
    'x-forwarded-for': '::ffff:203.0.113.5'
  });
  assert.strictEqual(clientAddress(viaHeader), '203.0.113.5');

  const viaSocket = request('::ffff:198.51.100.40');
  assert.strictEqual(clientAddress(viaSocket), '198.51.100.40');
});

test('the proxy list can be narrowed by environment, and a malformed entry is ignored', () => {
  withProxies('172.18.0.0/16', () => {
    assert.strictEqual(isTrustedProxy(EDGE), true);
    assert.strictEqual(isTrustedProxy('127.0.0.1'), false, 'loopback was dropped on purpose');

    // Which means nothing is believed from a loopback caller: it is counted as
    // itself, and a coarser bucket is the price of a list that narrow.
    const req = request('127.0.0.1', { 'x-client-ip': CLIENT, 'x-forwarded-for': CLIENT });
    assert.strictEqual(clientAddress(req), '127.0.0.1');
  });

  withProxies('nonsense, 198.51.100.0/24', () => {
    assert.strictEqual(isTrustedProxy('198.51.100.9'), true, 'the valid entry survives');
    assert.strictEqual(isTrustedProxy('127.0.0.1'), false);
  });
});
