/*
 * In-flight requests survive a shutdown.
 *
 * This is the promise that makes a deploy invisible: the container is replaced
 * while somebody is mid-request, and their request still gets an answer. The
 * cheaper test — signal it and check the exit code — passes just as happily for
 * a server that drops every open connection on its way out, so it proves the
 * process is tidy without proving anything about the people using it.
 *
 * Making a request genuinely in flight needs it to be slow, and slow on purpose
 * rather than by luck. A tiny TCP proxy sits between the API and Postgres and
 * delays what it forwards, so the request is provably still waiting when the
 * signal arrives. Needs a database. Set DATABASE_URL before running.
 */

const test = require('node:test');
const assert = require('node:assert');
const net = require('node:net');
const { spawn } = require('node:child_process');
const path = require('node:path');

const ENTRY = path.join(__dirname, '..', '..', 'src', 'index.js');

// Every chunk on its way to Postgres waits this long. Connection setup is
// several round trips, so the first query takes comfortably longer than the
// delay below before the signal is sent.
const FORWARD_DELAY_MS = 200;

// Sent well before the request can have finished, so "still in flight" is a
// property of the arithmetic rather than of how fast the machine is today.
const SIGNAL_AFTER_MS = 400;

const EXIT_TIMEOUT_MS = 15000;

// Forwards to the real Postgres, holding each chunk briefly on the way there.
// Delaying only the outbound direction is enough: it is the query that has to
// still be outstanding when the signal lands.
function startSlowProxy(target) {
  const server = net.createServer((client) => {
    const upstream = net.connect(target.port, target.host);
    const pending = [];

    client.on('data', (chunk) => {
      const timer = setTimeout(() => {
        if (!upstream.destroyed) upstream.write(chunk);
      }, FORWARD_DELAY_MS);
      pending.push(timer);
    });

    upstream.on('data', (chunk) => {
      if (!client.destroyed) client.write(chunk);
    });

    const teardown = () => {
      for (const timer of pending) clearTimeout(timer);
      client.destroy();
      upstream.destroy();
    };

    client.on('error', teardown);
    upstream.on('error', teardown);
    client.on('close', teardown);
    upstream.on('close', teardown);
  });

  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve({ server, port: server.address().port }));
  });
}

function startServer(databaseUrl) {
  const child = spawn(process.execPath, [ENTRY], {
    env: { ...process.env, BACKEND_PORT: '0', DATABASE_URL: databaseUrl },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  return new Promise((resolve, reject) => {
    let buffered = '';

    const onData = (chunk) => {
      buffered += chunk.toString();
      for (const line of buffered.split('\n')) {
        if (!line.trim()) continue;
        let entry;
        try {
          entry = JSON.parse(line);
        } catch {
          continue;
        }
        if (entry.msg === 'listening' && entry.port) {
          child.stdout.off('data', onData);
          resolve({ child, port: entry.port });
          return;
        }
      }
    };

    child.stdout.on('data', onData);
    child.once('error', reject);
    child.once('exit', (code) => reject(new Error(`API exited before listening (code ${code})`)));
  });
}

function waitForExit(child) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error('API did not exit within the timeout after SIGTERM')),
      EXIT_TIMEOUT_MS
    );
    child.once('exit', (code, signal) => {
      clearTimeout(timer);
      resolve({ code, signal });
    });
  });
}

test('a request already in flight is answered even though the API is stopping', async () => {
  const upstream = new URL(process.env.DATABASE_URL);
  const proxy = await startSlowProxy({
    host: upstream.hostname,
    port: Number(upstream.port || 5432)
  });

  upstream.hostname = '127.0.0.1';
  upstream.port = String(proxy.port);

  const { child, port } = await startServer(upstream.toString());

  try {
    // Deliberately not awaited: the request has to still be outstanding when
    // the signal arrives, which is the whole point.
    const inFlight = fetch(`http://127.0.0.1:${port}/api/health`);

    await new Promise((resolve) => setTimeout(resolve, SIGNAL_AFTER_MS));
    child.kill('SIGTERM');

    const response = await inFlight;
    assert.strictEqual(response.status, 200, 'the in-flight request should still be answered');

    const body = await response.json();
    assert.strictEqual(body.answer, 1, 'and answered from the database, not from a stub');

    const { code, signal } = await waitForExit(child);
    assert.strictEqual(signal, null, 'expected the API to exit itself, not to be killed');
    assert.strictEqual(code, 0);
  } finally {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
    }
    proxy.server.close();
  }
});

test('a request arriving after the signal is not accepted', async () => {
  const { child, port } = await startServer(process.env.DATABASE_URL);

  try {
    child.kill('SIGTERM');
    await waitForExit(child);

    // Once it has gone, the port is closed rather than left half-open. A
    // connection refused here is the correct outcome: the proxy in front should
    // already have stopped routing, and anything that still arrives must fail
    // fast rather than hang.
    await assert.rejects(() => fetch(`http://127.0.0.1:${port}/api/health`));
  } finally {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
    }
  }
});
