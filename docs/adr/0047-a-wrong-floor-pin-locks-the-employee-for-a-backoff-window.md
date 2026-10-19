---
status: accepted
---

# A wrong floor PIN locks the Employee for a backoff window

Date: 2026-10-19

Constrained by ADR-0016, which put a shared device on the floor and an
Employee's number and PIN on it. A device credential ships in the web bundle,
so anyone holding a device can call `POST /floor/identify` as often as they
like, and a 4 to 8 digit PIN falls to that in minutes. Nothing counted
attempts.

## The decision

`POST /floor/identify` counts wrong PINs in `floor_pin_attempts`:

- **Per (device, Employee number).** Five consecutive wrong PINs lock that pair
  for 15 minutes. A correct PIN deletes the count. When the lock lifts, the
  next wrong PIN starts a new run of one.
- **Per device.** Thirty wrong PINs of any Employee number inside 15 minutes
  lock the whole device for 15 minutes. A correct PIN does not reset this
  count; otherwise a person who knows one PIN could reset it between guesses at
  the others.
- **The lock is asked before the PIN.** A locked pair refuses even the right
  PIN, and a locked pair does not count further failures.
- **The Employee number is counted as typed**, whether or not an Employee holds
  it, so a lock never tells a caller who exists (the endpoint already answers a
  wrong number and a wrong PIN identically). Numbers longer than 64 characters
  are counted against the device only.
- **The answer is `423`**, `{ code: 'pin_locked', retryAfterSeconds, message }`
  with a `Retry-After` header. A wrong PIN stays `401`. A locked Employee is
  not unauthenticated, and `423` keeps every client from reading it as a dead
  session.
- **An administrator setting the PIN lifts the lock**, on every device, because
  setting it is already the reset action (`PUT /floor-technician-credentials`).

## Why a backoff window, not a lock until an administrator resets it

A lock that only an administrator lifts turns the attack into a denial of
service: anyone with a device can lock every Employee on a shift by typing
their numbers, and the plant cannot log work until an administrator is found.
Most Employees have no Account and cannot reset anything themselves. A 15 minute
window caps a guesser at 5 guesses per 15 minutes per Employee per device (a
4-digit PIN would take about 20 days of continuous guessing on one device), and
costs a genuine Employee who fat-fingers a PIN at most one coffee break, with
the administrator reset available when they cannot wait.

The limit is per device because the device credential is what the attacker
holds; an attacker with several devices gets several counters. Locking an
Employee across devices would let any one device holder lock everyone out
everywhere, which is the denial of service again.

## PIN length

The minimum stays at 4 digits (4 to 8). With the lockout in place the length is
not what stands between a guesser and a PIN, and raising it would not help the
4-digit PINs already issued: they would have to keep working until changed,
so the weak PINs would remain. A later change can raise the floor for newly set
PINs without touching stored ones, since the hash does not depend on length.

## Consequences

- One new table, `floor_pin_attempts`, deny-all RLS, not audited (a failed guess
  is not a record).
- The floor UI shows the server's message for a `423`; the client no longer
  signs a person out on a floor 401 (see `SignOutOnUnauthorized`).
- Counters are never pruned except by a success, an administrator's PIN reset
  or the device's removal. Rows are bounded by devices times distinct numbers
  typed, which the per-device lock bounds in turn.
