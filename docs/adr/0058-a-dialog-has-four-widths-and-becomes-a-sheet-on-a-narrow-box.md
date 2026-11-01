---
status: accepted
---

# A dialog has four widths, one shell, and becomes a sheet on a narrow box

Date: 2026-11-01

Issue #398, part of #385, writes down the three conventions a per-Screen
programme never touches: dialogs, feedback and data display. Dialogs are the one
that needed a decision rather than a description. Of the 113 files under
`frontend/lib/` whose name contains `dialog` before this card added two more, 112
build an `AlertDialog` and 110 put a `SizedBox` directly in `content:`, so the width the author chose is the
width of the *content* and the title and the action row are whatever the platform's
padding makes them. The widths themselves are seven numbers, counted by occurrence:
**420 ×34, 520 ×28, 460 ×20, 560 ×11, 480 ×10, 640 ×5, 620 ×5**. None of them
considers the box: a 520 dialog on a 440 box, or at twice the text size, has less
room than a phone.

## The decision

**A dialog is one of four widths, and the width belongs to the shell.**
`AppDialog` takes an `AppDialogSize`: `decision` 420 (one question, two actions, no
fields), `picker` 460 (choose one thing from a list), `form` 520 (a short form, up
to about six fields) and `wide` 640 (a long form, or content with its own
columns). The width is on the surface, not on a box inside it, so the title, the
content and the actions share one pair of edges. Four, not seven: 420, 460 and
520 each answer a question of their own, and 560, 620 and 640 are one dialog drawn
three ways. Four, not one: a confirmation at 640 is a question lost in a field
of white, and a long form at 420 is a scroll bar with a title. Four, not "whatever
the author sets": 113 dialogs and seven numbers is what that produced, and two of
the numbers (620 and 640) differ by 20px.

**At or below a box of 700, or at a text scale of 1.5, the dialog is a bottom sheet.**
`AppBreakpoints.dialogSheet` (700, `<=`) and `AppBreakpoints.dialogSheetTextScale`
(1.5, `>=`) in `theme.dart`. The sheet is full width, anchored to the bottom,
rounded on its top corners, with the title and the action row pinned and the
content the only scroller; the action row is full-width and the primary action
fills the inline end. **The text scale is a trigger of its own because it is the
thing that spends the width**: a 520 form has 488 of usable width, which at 2x
text holds what 244 holds at 1x, against 328 for a 360px phone at 1x. The box is
compared as it is, not multiplied by the scale, which would count the text twice.
The decision is read from the `LayoutBuilder` at the dialog's root, because a dialog
route is handed the whole window and the window is its box.

**`AppDialog` is a surface; `DialogPage` stays the route.** ADR-0019 and ADR-0021
made a transition dialog an address, a `DialogRoute` whose list stays visible and
which survives a refresh. That is `platform/dialog_page.dart` and it does not change.
`AppDialog` is what a `DialogPage`'s `builder` returns. There are 52
`DialogPage<void>(` pages in `router.dart` and 137 `showDialog` call sites across
68 files; both stay legal, and a dialog with no address of its own is a `showDialog`
that builds an `AppDialog`. No route helper was added: opening a dialog from a
focused button with plain `showDialog` and closing it returns focus to the button
(`app_dialog_test.dart`), so there was nothing for one to fix.

**The primitive guarantees the accessibility and the caller owns the words.**
Focus is trapped by a focus scope of the dialog's own, inside the route's and under
the `Esc` handler, and starts on the first field, or on the first enabled primary
action, or on the enabled dismiss when the only act is destructive. `Esc` runs the
dialog's own dismiss action (Flutter's `ModalRoute` handles `Esc` only when the
barrier is dismissible, which a `DialogPage` is not by default), so `Esc` on a
destructive confirm cancels. Focus returns to the invoker. The caller keeps its
strings, its field keys and labels, its enable conditions and `DialogPage`'s barrier
flag. A destructive confirm is filled `statusDanger` with the `canvas` on it:
6.18:1 in light and 9.41:1 in dark, where white on the dark `statusDanger` is
1.90:1.

**Feedback is one inline surface, `AppBanner`; data display is a convention.**
The same card writes sections 12 and 13 of `docs/design-language.md`. They are
recorded there, not here, and they are not what this record decides.

**Rejected: keep hand-sizing.** It is the status quo and its cost is the census
above. It also makes the sheet impossible: each dialog would have to learn the
box on its own, 113 times.

**Rejected: one width for everything.** A single 520 makes a confirmation larger
than its question and puts a long form in a box that scrolls on every laptop. It
would have removed the argument and kept the cost.

**Rejected: a full-screen route on a narrow box.** It hands the reader the whole
window for a question that needs a line, it ends the "the list is still behind it"
property that `DialogPage` exists to keep (ADR-0019), and it changes the route
type, which is the address.

**Rejected: Flutter's `BottomSheet`.** It is a second route and a second set of
focus, dismiss and barrier rules to keep in step with the dialog's, for a surface
that is the same four rows laid out differently. One widget that reshapes itself
means one test of those rules.

## What it costs

- **Nothing has adopted it.** `AppDialog` and `AppConfirmDialog` are new files; the
  112 `AlertDialog` dialogs keep their `AlertDialog` until each slice moves one. The document
  says so and lists the mapping from the seven widths to the four as the adopting
  slice's to make by content.
- **A dialog that does not fit its width moves up a size, never down**, which makes
  some 480 and 560 dialogs a little wider than they are and is deliberate.
- **The sheet decision reads the box.** The `LayoutBuilder` at the dialog's root
  measures whatever box the dialog is given, so a dialog hosted in anything narrower
  is handled correctly; for a route that box is the window. The document says not to
  "fix" it into `MediaQuery.sizeOf`, which would ignore the host, and a test mounts
  the shell in a box of its own for the golden.
- **A stateful widget.** The shell is a `StatefulWidget`, because first focus and a
  body that survives crossing 700 genuinely need one.
- **Two more numbers in `AppBreakpoints`**, which the rest of the class does not
  treat the same way (compared as they are, not scaled by the text); section 10 says
  why.

## What it does not decide

- **Which dialog moves when**, and at which of the four widths. Each is a slice.
- **The Shell's 700px rail breakpoint**, which section 2 names a cliff and which
  this record reuses as a number but does not touch.
- **A route helper.** None is needed today; if a future measurement shows focus is
  not restored, the smallest fix is added then.
- **A date, number or money helper.** Section 13 is a convention, and the client
  has no `intl` dependency to build one on.
