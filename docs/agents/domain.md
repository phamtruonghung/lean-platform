# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

**Layout: single-context.** One `CONTEXT.md` and one `docs/adr/` at the repo root. The multi-context section below is kept for reference; it only applies if a `CONTEXT-MAP.md` is added at the root later.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists: it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo (most repos):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_

## Words, codes and the catalogue (ADR-0062)

A status, a type, a severity, a role or a Bloc's notice is a **code**; the word
a person reads for it is a catalogue entry. The lookup lives in one place,
`frontend/lib/l10n/vocabulary.dart` (codes) and `frontend/lib/l10n/notices.dart`
(Bloc-held copy), and the models carry codes and tones only. Add a code by
adding it to the model's own constants, to **both** ARB catalogues, and to one
arm of the lookup — the `_ => code` arm is what makes a forgotten one visible.

### Codes this build has no catalogue word for yet

These still render as their own English/code value in every language, in the
vocabulary's own fallback. They are the residue of the sweep, not a decision
that they need no translation. The **status / type / role / severity words are
all converted**: ADR-0062's rounds 2 and 3 closed the model-level tables
(complaints, supplier NCRs, downtime, assets, defect categories, the KPI board
and Review, the slide show's kinds, the skill coverage legend, the Shift
handover's seven sets, and — round 3, the last three model-level labels — an
Account's standing, a Grant's level and the board's period), and the set the
review of round 3 found had escaped them is closed too: the Shift handover's own
status chip (`submitted` / `acknowledged`, `handoverStatusLabel`), on the board
and in the record's header. The three `StatusChip` render sites the review after
it found were the last of the class, and are closed as well: a slide's status
(which printed the wire itself, now `SlideIssueWords.statusLabel`), the
Attendance picker's sheet state (`attendanceSheetStateLabel`, the worklist's own
lookup) and the attendance sheet's legend (`attendanceToneLegendLabel`). That
census was mechanical — every `StatusChip(label: …)` in `lib/` resolves to an
`l10n.*` entry, a vocabulary lookup, or a record's own name; the two
`toneWord` legends read the `StatusTone` enum's name and are the design
language's tone words, not a domain code. What is left is the one status-shaped
answer word in the table below (a Trainee's `declined`) and prose, measured by
grep at the end of that round:

| Code set / prose | Where | What is still English |
| --- | --- | --- |
| A Trainee's answer | `lib/people/training_form_screen.dart` | `declined` |
| Form-mode titles | `lib/people/{product_cost, cost_rate}_form_dialog.dart` | add / correct / revise |
| A filter's count line | `lib/widgets/app_filter_field.dart` | "Showing N of M" |
| The measure dialog's help text | `lib/actions/action_measure_dialog.dart` | per measure type |
| Register column headings kept as constants | `lib/kpi/kpi_targets_screen.dart`, `lib/people/attendance_sheet_screen.dart` | "Valid from", "Grain", "Entered by", … |
| Widget tooltips kept as constants | `lib/widgets/palette_toggle.dart`, `lib/quality/slide_show_toggle.dart` | the palette and slide-show tooltips |
| The KPI Review's two hints | `lib/kpi/kpi_review_screen.dart` | "No target — set one first", the clears-note sentence |
| A form's never-edited rule | `lib/kpi/change_target_dialog.dart` | `rule`'s English sentence |
| A Signature's provenance sentence | `lib/people/training_detail_screen.dart` | "Signed with their kept Signature", … |
| The board's handover button | `lib/production/section_board_screen.dart` | "Write the handover" / "Continue the handover" / "Open the handover" |
| Model prose getters | `lib/quality/{customer_complaint,supplier_ncr}.dart` | `quantityLabel`, `dueLabel` — "No quantity given" |
| A failed read's retry label | `lib/widgets/failure_state.dart` | `retryLabel`'s English default ("Try again") |
| A failed suggestion read | `lib/widgets/app_search_field.dart` | "Couldn't load suggestions…" |

A **Bloc's interpolated notices** (`'${action.actionNo} was called off.'`) are
the other half: `notices.dart` covers the constant messages and the parameterised
ones the sweep converted (`BlocNotice.employeeLeft`, `assetBack`, …), and **every
render of a Bloc-held message goes through `NoticeText`** (`lib/widgets/notice_text.dart`)
or `AppDialog`'s own `description`, so a code cannot reach a reader unresolved —
but a notice a Bloc still composes inline is English until a later slice turns it
into a code. Measured at 33 such literals.

