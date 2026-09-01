/*
 * Graceful shutdown.
 *
 * A deploy replaces this container, and the promise is that whoever is using
 * the app does not notice. That promise is only real if the process handles
 * SIGTERM and exits on its own terms — a process that has to be killed has cut
 * somebody's request in half.
 *
 * This runs the API as a child process, because the behaviour under test is
 * what the process does when signalled. Calling the shutdown function directly
 * would prove the function runs, not that the signal reaches it.
 */

const test = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');
const path = require('node:path');

const ENTRY = path.join(__dirname, '..', 'src', 'index.js');

// Long enough to be certain a clean exit failed, short enough that a broken
// shutdown fails the run rather than hanging it. The process's own last-resort
// timer is 25 seconds, so anything approaching that is already a failure.
const EXIT_TIMEOUT_MS = 10000;

// Starts the API and resolves once it reports the port it actually bound.
// BACKEND_PORT=0 asks the OS for a free one, so a test run never collides with
// a development server or with a second run on the same machine.
function startServer() {
  const child = spawn(process.execPath, [ENTRY], {
    env: { ...process.env, BACKEND_PORT: '0' },
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
          // Not every line is ours to read; ignore anything that is not the
          // structured log this process emits.
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

test('the API exits cleanly when it is asked to stop', async () => {
  const { child, port } = await startServer();

  try {
    // Prove it was actually serving before the signal, so a process that
    // crashed on boot cannot pass this test by exiting quickly.
    const before = await fetch(`http://127.0.0.1:${port}/healthz`);
    assert.strictEqual(before.status, 200);

    child.kill('SIGTERM');
    const { code, signal } = await waitForExit(child);

    // Exit code 0 by its own hand. A process killed by the signal reports the
    // signal instead, which is precisely the outcome this guards against.
    assert.strictEqual(signal, null, 'expected the API to exit itself, not to be killed');
    assert.strictEqual(code, 0);
  } finally {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
    }
  }
});

test('a second signal while already shutting down does not stop it exiting cleanly', async () => {
  const { child } = await startServer();

  try {
    child.kill('SIGTERM');
    child.kill('SIGTERM');

    const { code, signal } = await waitForExit(child);
    assert.strictEqual(signal, null);
    assert.strictEqual(code, 0);
  } finally {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill('SIGKILL');
    }
  }
});
