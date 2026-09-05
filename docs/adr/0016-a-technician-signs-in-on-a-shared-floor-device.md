---
status: accepted
---

# A technician signs in on a shared floor device

Date: 2026-09-05

Issue #77, constrained by issue #33: the Shell is desktop-first, and a
floor-facing surface is designed as its own surface, never reached by
widening a breakpoint down until a desktop layout happens to fit a tablet. A
floor-facing screen for logging work against a machine has to be designed on
those terms rather than assumed to inherit the Shell's own sign-in.

## The decision

The floor-facing surface runs on a shared device at the machine, not a
personal one issued to a technician. One tablet or terminal sits at the line,
reachable by whoever is working there, rather than each technician carrying
their own signed-in device onto the floor.

## The tension this creates with what an Account already means

CONTEXT.md's own "Account" entry is built around a person: an Account is what
lets somebody sign in and act, carrying the role that says what kind of work
they may do and the Org Units it may be done in, at most one per Employee.
Every read and write this Platform makes today is attributed to whichever
Account made it, and that attribution is what the reliability numbers, the
audit trail, and the whole Approval model are built to trust. A shared device
fits that model badly: the ordinary shape of a session — sign in once, stay
signed in, act freely until sign-out — means that on a device nobody signs
out of between jobs, every action for the rest of the shift is attributed to
whoever happened to sign in first, whether or not they are the one standing
at the machine when the next job is logged. That is not a minor inaccuracy;
it corrupts exactly the attribution the reliability numbers depend on,
silently, because nothing about a wrongly-attributed action looks different
from a correctly-attributed one.

## Consequences

Identifying who performed a given action has to happen at the action, not at
the session. The shared device cannot hold a long-lived privileged session
the way a personal one safely can — whatever lets someone log labour or close
out a job on this surface has to re-establish who is doing it close to the
moment they do it, not once at the start of a shift and then trust the device
for hours afterward. This ADR does not pick how: no PIN, no badge, no NFC tap
is decided here, and picking one is deliberately left to the ticket that
builds this surface. What is decided is the shape any such mechanism must
have — it must re-confirm identity per action, or at most within a short
enough window that "who was at the machine" and "who the system attributed
the action to" cannot drift apart across a shift change, and it must never
leave the shared device itself holding a privileged session that outlives the
moment it was used, the way a personal device signed into the desktop Shell
is allowed to.

This is the same posture this repo already takes elsewhere on authentication
and authorization: ADR-0004 records the database's own auth floor rather than
leaving RLS's absence to be discovered by accident, and ADR-0013 records why
an administrator cannot act on their own Account rather than leaving that
refusal to read as a bug the next person "fixes". This ADR belongs beside
them for the same reason — the shared device changes the shape of who a
session can be trusted to represent, and that is exactly the kind of decision
this repo records rather than makes in passing.
