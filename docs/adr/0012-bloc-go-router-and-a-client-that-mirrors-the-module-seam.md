---
status: accepted
---

# bloc for state, go_router for addresses, and a client that mirrors the backend's Module seam

Date: 2026-09-02

Issue #33 gave the client three Screens (sign-in, awaiting-Approval, home) and
no foundation beneath them: no shared state-management pattern, no addresses a
Screen can be linked to, and no layered structure separating what is common to
every Screen from what belongs to one Module. Three future issues (#39 the
Shell and Directory, #40 onward) will each add Screens that need all three of
these at once, and each of the three choices constrains the other two — a
Screen's address decides what state it needs when navigated to directly, and a
Module's state needs a place to live that a routing layer can reach. They are
decided together here, in one record, so a reader arriving at any one of the
three finds the other two rather than three separate ADRs that each assume
the others already happened.

## The decision: state management is bloc, full Bloc rather than Cubit

Every Screen-driving state machine in the client — "is there a session, is
that Account admitted yet, what did the last fetch return" — gets an explicit
event type and state type, dispatched through a `Bloc`, not a `Cubit`'s bare
methods. This is more ceremony than a two-line `Cubit` method for a Screen as
small as sign-in, and that cost is accepted deliberately: the People, Tier
Board and Maintenance Modules that follow will each carry more complex state
(a Directory's search-and-filter, a tier board's per-Pillar drill-down) where
the same event/state vocabulary the small Screens already use is what keeps
one pattern legible across all three, rather than the small Screens reading
as `setState` in a trenchcoat while only the complex ones justify `bloc`. This
is a deliberate departure from both predecessor apps this Platform absorbs
(issue #33's Implementation Decisions): `employee-management` and its sibling
both hold state with `setState` and a bare `http.Client` call per Screen, a
pattern that does not scale past the three-Screen client either of them
shipped.

## The decision: go_router, so every Screen has an address

Every Screen (CONTEXT.md's own new entry: "a full destination with its own
address") gets a route, and the sign-in / awaiting-Approval / home redirect
logic `AuthGate` currently expresses as three branches of a widget tree is
instead expressed once, as `go_router`'s `redirect`, reading the same Account
state Bloc exposes. Concretely this replaces `AuthGate`'s own StreamBuilder-
over-FutureBuilder nesting: a router-level redirect that inspects session and
Approval state runs before a Screen builds at all, rather than each Screen's
own widget tree deciding whether it is allowed to be on screen. Retrofitting
addresses across a dozen Screens once the Shell (#39) and the Modules behind
it (#40 onward) exist would cost materially more than establishing the
routing layer now, while there are still only three Screens whose navigation
needs re-expressing.

## The decision: the client mirrors the backend's Module seam

The client gets the same two-layer shape ADR-0006 gives the backend: a
platform layer — Shell, theme, routing, the HTTP client — that every Module
sits beneath, and a per-Module layer (People's Directory and Approval queue,
Maintenance's Screens, the Tier Board's) that owns its own Blocs and routes
the same way a backend Module owns its own routes and services. A seam
present on the server and absent on the client is only half a seam: today
nothing stops a People Screen from reaching directly into Maintenance's
state, the same problem ADR-0006 solved for the backend by making
cross-Module calls go through a service rather than a private import.

## Consequences

This record is written ahead of its implementation. This ticket (#37) lands
the design system and this ADR; the `bloc` and `go_router` packages
themselves, and the actual routing and state-management wiring the three
decisions above describe, land in #38 — `pubspec.yaml` gains neither
dependency here, and `AuthGate`'s redirect logic and the three Screens'
`setState` are untouched by this ticket. A corollary follows from the same
gap: `bloc_test` is not adopted here either, since there is no Bloc yet to
test. The one test seam this ticket does establish — a widget test
substituting a fake HTTP client in for the network at the wire, rather than
constructing its own client where nothing above the widget tree can reach it
— is `PeopleApi`'s and `PlatformApp`'s new `http.Client?` injection point, and
the tests that exercise it (`people_api_test.dart`,
`screens_theme_test.dart`). That seam is deliberately client-agnostic to
Bloc's arrival: whichever Bloc eventually calls `PeopleApi` will substitute
the same fake client at the same point, rather than #38 needing a second
injection mechanism.

#38 landed the routing and state-management wiring itself — `AccountBloc`,
`go_router`'s redirect table, and `AuthGate`'s deletion — and with it a second
injection seam, `AuthGateway`, for Supabase Auth. This does not contradict the
paragraph above: that sentence was specifically about `PeopleApi`'s HTTP
client, and remains true unchanged for it. `AuthGateway` is a distinct,
necessary seam because `Supabase.initialize()` cannot run under `flutter
test`, and every router redirect test needs to drive session state (sign-in,
sign-out, token refresh) directly rather than through a real Supabase client.
`SupabaseAuthGateway` is the production implementation; tests substitute a
fake at the same point `router_redirect_test.dart` exercises.
