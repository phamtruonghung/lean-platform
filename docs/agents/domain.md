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
that they need no translation:

| Code set | Where | Codes |
| --- | --- | --- |
| KPI measurement outcome | `lib/kpi/kpi_catalogue.dart` | `met`, `missed`, `not_measured` |
| An Account's standing | `lib/people/managed_account.dart` | `rejected`, `approved` (active / deactivated), awaiting approval |
| A Trainee's answer | `lib/people/training_form_screen.dart` | `declined` |
| Skill coverage legend | `lib/people/skill_coverage_screen.dart` | "Nobody qualified", "Partly qualified", "Short" |
| Form-mode titles | `lib/people/{product_cost, cost_rate}_form_dialog.dart` | add / correct / revise |
| A filter's count line | `lib/widgets/app_filter_field.dart` | "Showing N of M" |
| The measure dialog's help text | `lib/actions/action_measure_dialog.dart` | per measure type |

A **Bloc's interpolated notices** (`'${action.actionNo} was called off.'`) are
the other half: `notices.dart` covers the constant messages and the parameterised
ones the sweep converted (`BlocNotice.employeeLeft`, `assetBack`, …); a notice a
Bloc still composes inline is English until a later slice turns it into a code.

