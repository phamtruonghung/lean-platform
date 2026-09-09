---
status: accepted
---

# A transition dialog is an address in the client too

Date: 2026-09-10

The four things a person does to a Work order that are not "read it" —
raise one, assign it, complete it, cancel it — each open a dialog. As of
issue #104 each of those dialogs is a `go_router` address of its own:
`/work-orders/new`, `/work-orders/:id/assign`, `/work-orders/:id/complete`,
`/work-orders/:id/cancel`.

Before #104 they were opened with a bare `showDialog(...)` from the list
Screen. That builds a route directly under the Navigator with no address, so
an open dialog did not survive a refresh and could not be linked to.

## This is not what ADR-0019 said

ADR-0019 is titled "A Work order transition is a route of its own" and is
about the **HTTP API**: `POST /work-orders/:id/start`,
`POST /work-orders/:id/complete` and `POST /work-orders/:id/cancel`, chosen
over a single `PATCH /work-orders/:id { status }`. Every route it names is a
backend route. It says nothing about the client, and the client was never in
violation of it.

That distinction is easy to lose — the two decisions share a word, a subject
and almost a title — and it was in fact lost while #104 was being written,
where ADR-0019 was cited as though it already required client-side
addressability. It did not. This ADR exists partly so the next person who
reads "a transition is a route of its own" knows which of the two routes is
meant, and does not have to reconstruct the difference from the code.

The client-side decision is therefore recorded here, on its own merits,
rather than resting on a misreading of a backend one.

## The decision

A transition dialog is an address. Opening one is `context.go`, not
`showDialog`; closing one returns to the list's address.

`DialogPage` is what makes this possible without changing how anything
looks. It is a `Page` whose `createRoute` returns a `DialogRoute` — a
`PopupRoute`, so it is non-opaque and paints over the page beneath it,
exactly the "the list stays visible underneath" appearance the four
`showDialog` calls already had. `barrierDismissible` defaults to `false`,
matching what all four dialogs already passed.

The four addresses are child `GoRoute`s under a `ShellRoute` that owns the
`WorkOrdersBloc`, so the list and its dialogs share one Bloc instance rather
than the dialog rebuilding a second copy of the list's state. A dialog
opened at an address must resolve its Work order from that shared list,
which produces three outcomes a `showDialog` never had to think about: the
list is still loading, the id is not in the list, or the id is there but the
transition is not available to this Account — for permission, or because the
Work order's status does not offer it. Each is rendered distinctly rather
than collapsed into one "something went wrong".

## Why

Two reasons, neither of them ADR-0019.

**Consistency with a decision the Platform already made.** Issue #39 shipped
the Shell with the criterion "Selecting a destination navigates by address,
so the browser's history and back button work". The Platform already holds
that what a person is looking at should be in the URL. A dialog that
silently vanishes on refresh is the same class of problem that criterion was
written against, one level down.

**Because this Screen is copied.** #104 makes Work orders the reference for
the six Maintenance Screens in #72–#80. Requests, Breakdowns, PM schedules,
Job plans and Parts all have transitions of their own. Settling this once,
here, is the entire point of having a reference Screen; leaving it unsettled
means six authors each choose, and they will not all choose the same.

## What this costs

It is more machinery than `showDialog`. A dialog now needs an address, a
route entry, a Bloc that outlives it, and a resolution path with three
failure outcomes — against one function call. For a dialog that genuinely
has no subject and no consequence (a confirm-and-forget, a picker feeding a
field already on screen) that trade is not worth making, and this ADR does
not ask for it: `work_orders_screen.dart`'s own Org Unit chooser stays a
plain `showDialog`, because there is nothing to link to and nothing to lose
on a refresh.

The rule is about **transitions** — the things that change a record and that
somebody might reasonably send a colleague a link to. That boundary needs
judgement, which is a real cost against the bright line "dialogs are
dialogs".

Hoisting the Bloc onto a `ShellRoute` also means the list's state is now
alive whenever any of its dialog addresses is, which is what makes a
deep-link into `/work-orders/:id/assign` work at all. A future Screen
copying this pattern inherits that lifetime, and should not assume its Bloc
is scoped to the list Screen alone.
