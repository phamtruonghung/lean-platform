/*
 * platform/client-address.js: which address a request is counted as, and when a
 * forwarding header may be believed. Pure; needs no database and no server.
 *
 * These are the states the deployed path puts a request in — behind the tunnel
 * on the proxy's socket, and directly on a port that publishes the backend —
 * plus the two ways a caller could try to name its own bucket.
 */

const test = require('node:test');
const assert = require('node:assert');
const { clientAddress, isTrustedProxy } = require('../src/platform/client-address');

const ENV = 'CLIENT_TRUSTED_PROXIES';

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
function request(peer, { headers = {}, ip } = {}) {
  const lower = Object.fromEntries(
    Object.entries(headers).map(([name, value]) => [name.toLowerCase(), value])
  );
  return {
    socket: { remoteAddress: peer },
    get: (name) => lower[String(name).toLowerCase()],
    ip
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

test('a request from the proxy hop is counted as the address the tunnel names', () => {
  // The socket is the edge container; CF-Connecting-IP is what the edge saw.
  const req = request('172.18.0.3', { headers: { 'cf-connecting-ip': '203.0.113.5' } });
  assert.strictEqual(clientAddress(req), '203.0.113.5');
});

test('a header sent by a peer that is not the proxy is ignored', () => {
  // A caller that reached the backend itself, claiming to be someone else.
  const req = request('198.51.100.40', {
    headers: { 'cf-connecting-ip': '203.0.113.5' },
    ip: '198.51.100.40'
  });
  assert.strictEqual(clientAddress(req), '198.51.100.40');
});

test('a forged X-Forwarded-For cannot replace the address either', () => {
  // What `trust proxy 1` used to allow on the published development port: the
  // resolved `req.ip` is the socket's own address once the peer is untrusted.
  const req = request('198.51.100.40', {
    headers: { 'x-forwarded-for': '203.0.113.5', 'cf-connecting-ip': '203.0.113.6' },
    ip: '198.51.100.40'
  });
  assert.strictEqual(clientAddress(req), '198.51.100.40');
});

test('a trusted hop with no usable header falls back to the resolved address', () => {
  assert.strictEqual(clientAddress(request('172.18.0.3', { ip: '172.18.0.3' })), '172.18.0.3');
  for (const bad of ['', 'unknown', '203.0.113.5, 198.51.100.7', '203.0.113.300']) {
    const req = request('172.18.0.3', {
      headers: { 'cf-connecting-ip': bad },
      ip: '172.18.0.3'
    });
    assert.strictEqual(clientAddress(req), '172.18.0.3', `header ${JSON.stringify(bad)}`);
  }
});

test('an IPv4-mapped address is the same client as its IPv4 form', () => {
  const viaHeader = request('::ffff:172.18.0.3', {
    headers: { 'cf-connecting-ip': '::ffff:203.0.113.5' }
  });
  assert.strictEqual(clientAddress(viaHeader), '203.0.113.5');

  const viaSocket = request('::ffff:198.51.100.40', { ip: '::ffff:198.51.100.40' });
  assert.strictEqual(clientAddress(viaSocket), '198.51.100.40');
});

test('the proxy list can be narrowed by environment, and a malformed entry is ignored', () => {
  withProxies('172.18.0.0/16', () => {
    assert.strictEqual(isTrustedProxy('172.18.0.3'), true);
    assert.strictEqual(isTrustedProxy('127.0.0.1'), false, 'loopback was dropped on purpose');

    // Which means the header is not believed from a loopback caller in tests.
    const req = request('127.0.0.1', {
      headers: { 'cf-connecting-ip': '203.0.113.5' },
      ip: '127.0.0.1'
    });
    assert.strictEqual(clientAddress(req), '127.0.0.1');
  });

  withProxies('nonsense, 198.51.100.0/24', () => {
    assert.strictEqual(isTrustedProxy('198.51.100.9'), true, 'the valid entry survives');
    assert.strictEqual(isTrustedProxy('127.0.0.1'), false);
  });
});
