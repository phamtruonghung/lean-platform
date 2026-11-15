---
status: accepted
---

# The Shell continues a modal's barrier

Date: 2026-11-15

Issue #559: a popup left the sidebar undimmed. Measured on `/leave-requests/new` in
the pinned image at 1280x900: the modal's own `ModalBarrier` read
`Rect.fromLTRB(260, 0, 1280, 900)` — the raise form's shade began exactly where
the sidebar ended — and the 260px column stayed bright, hoverable and clickable
under an open dialog. Every popup in the client had this shape, both of the two
populations `docs/design-language.md` §11 counts: the 52 addressable
`DialogPage` routes and the `showDialog` call sites.

## Why the popup cannot simply move

A Screen is a route of a `ShellRoute`'s inner navigator, and a popup over it is a
route of that *same* navigator. That is not incidental. It is what lets a dialog
read the blocs its Screen was built with: `LeaveRequestsBloc`,
`ComplaintDetailBloc`, `SafetyIncidentDetailBloc`, `CapaDetailBloc` and the rest
are created per area, inside the Shell, one `BlocProvider` deep in the
`ShellRoute` whose routes the dialog is a sibling of. Fifty of the 52
`DialogPage` page builders read one of them.

Presenting modals on the root navigator is the other obvious fix, and it is the
one that fails: a route on the root navigator is a child of `MaterialApp`, not of
the Shell, so every route-scoped bloc above it is out of reach. Making that work
means hoisting those blocs above the navigator — which they cannot be, because
they are keyed by the address the navigator is showing (`/complaints/:id`) and
disposed when that address is left. The barrier's own geometry is therefore
fixed by where the route has to live: a `ModalBarrier` fills its navigator's box,
and the navigator's box is the content area.

## The decision

**The Shell draws the modal's own barrier across the column the Screen does not
own**, for as long as a route that shades anything is on top of it.

`platform/modal_layer.dart` is one `NavigatorObserver` on the router's observers,
so it hears every navigator go_router builds — the popups live on the
`ShellRoute`s' inner ones, and `ShellRoute.notifyRootObserver` hands them the
router's observers. It holds the topmost route that *shades*: a `ModalRoute`,
non-opaque, with a non-transparent `barrierColor`. A `PopupRoute` with no
barrier — a dropdown's menu, a popup menu, an autocomplete's list — is a popup
over a *control*, not a modal over a Screen, and leaves the chrome available.

`PlatformShell` then paints that route's own barrier over its own column, in the
route's own colour, on the route's own animation, and with the route's own
`barrierDismissible` — so tapping the chrome dismisses exactly what tapping
beside the dialog dismisses. The two barriers abut at the sidebar's edge and read
as one shade across the window, and they cannot drift: there is one colour, and
it is the route's.

## Consequences

- **The card does not move.** ADR-0058's four widths and its sheet mode still
  measure the Screen's box, so a 520 form on a 1280 window is centred in
  `260..1280`, not in `0..1280`. The complaint was the shade, not the card, and
  the card's geometry is a decision of its own.
- **The chrome is inert while a modal is up**, pointer-wise: the shade is a real
  `ModalBarrier` over the sidebar column, so a Destination cannot be clicked
  through an open dialog. Focus was already the modal's, from the route's own
  scope.
- **Two widgets, one shade.** They meet exactly at the sidebar's edge, and the
  Shell's width is the width it draws at the current breakpoint — 260 expanded,
  64 at the rail — so there is no seam at either.
- **Nothing else is touched.** No call site, no route, no `DialogPage`, no
  `showDialog`: the observer sees whichever navigator announced the push.
- Measurement and guards: `test/modal_cover_test.dart` asserts an
  addressable form, a `showDialog` confirm, the 64px rail, and the empty case
  (no shade, so a stray scrim cannot hide the chrome).
