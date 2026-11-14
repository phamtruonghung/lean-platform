# 0062 — A code becomes a word in one lookup, and a Bloc speaks in codes

- **Status:** Accepted
- **Date:** 2026-11-14
- **Issue:** t_d985118f (i18n sweep: the model-level vocabularies and the Bloc-held copy)

## Context

The i18n sweep left one thing behind, and it is the first thing a Vietnamese
reader sees on every register: the **status, type and role chips**. Those words
were not in a Screen at all. They lived on the models, as English strings next
to the codes they named:

- a `const Map<String, (String, StatusTone)>` per state set (`_statuses`,
  `actionStatuses`, `capaStatuses`, …), the label and the tone fused;
- an enum's own `label` field (`WorkType.corrective('corrective', 'Corrective')`,
  and the same on `ActionType`, `RequestUrgency`, `LabourActivity`,
  `PartSource`, `MeterType`, `PmScheduleAnchor`);
- a static `label(String)` on a value-class (`IncidentType.label`,
  `SeverityLevel.label`, `SafetyIncidentStatus.label`, `DispositionType.label`,
  `DefectSeverity.label`, …);
- a `String get statusLabel` on the record (`WorkOrder`, `Action`, `Capa`,
  `SafetyIncident`, `Nonconformance`, …), consumed by several Screens and, in
  one case (`WorkOrder.knownStatusLabels`), by a column that sizes itself to the
  longest label;
- `role_choice.dart`'s `admissionRoles`, which carried **both** an English label
  and an English description, and `roleLabel(String)` reading them back.

And it lived in the Blocs: every Bloc holds a `static const String
signedOutMessage` — 84 of these constants across 40-odd Blocs — plus its own
notices ("Another action is already in progress…", "… has left.", "There are no
Sites you can see, so …"). A Bloc has no `BuildContext`, so it could not read
the catalogue, and the sentence it emitted was printed verbatim under a
Vietnamese page.

## Decision

**One mechanism, in one place: a stable code mapped to a catalogue word by a
lookup that takes `AppLocalizations`, falling back to the raw code.**

`frontend/lib/l10n/vocabulary.dart` holds every such lookup:

```dart
String workOrderStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'approved' => l10n.workOrderStatusApproved,
      'in_progress' => l10n.workOrderStatusInProgress,
      …
      _ => status,          // a code this build has not been taught renders as itself
    };
```

It is the shape `l10n/destination_labels.dart` already used for the sidebar
(a stable address → a catalogue word, falling back to the address), so the tree
now answers "what does this code read as" one way. Readability at the call site
is kept with extensions in the same adapter — `workOrder.statusLabel(l10n)` —
and the **models keep only the codes and the tones**, because neither is a
language.

**A Bloc's copy travels as a code too.** `frontend/lib/l10n/notices.dart` holds
`BlocNotice.sessionEnded` and friends; a state carries the code, and the widget
that renders it resolves it through `noticeText(l10n, message)`. A message that
does not start with `notice:` is prose — a server's own error text — and passes
through untouched, which is the whole rule.

### What this cost, stated plainly

- **Call sites.** Every read of a label gained an argument: 131 instance-getter
  reads (`wo.statusLabel` → `wo.statusLabel(l10n)`), ~90 calls of a removed
  helper (`capaStatusLabel(wire)` → `capaStatusLabel(l10n, wire)`), and the
  `for (final entry in map.entries)` loops became `for (final (code, word) in
  actionTypeChoices(l10n))` so the *order* stays in one place too.
- **The column that sized itself from `knownStatusLabels`.** A model cannot
  produce localized words, so `WorkOrder.knownStatusLabels` became
  `workOrderKnownStatusLabels(l10n)` — the same known codes, resolved through
  the same function, so the Work orders Status column measures the words it is
  about to draw in *that* language. `requests_screen.dart` and
  `my_requests_screen.dart` had hard-coded English lists for the same purpose
  and now use `requestKnownStatusLabels(l10n)` / `requestKnownUrgencyLabels`.
- **Two duplicate maps died.** `action_detail_screen.dart` and
  `capa_report_screen.dart` each kept private copies of the Safety severity,
  observation type/category/potential and Quality disposition words, because
  `actions` did not import those Modules. The catalogue adapter imports both, so
  the copies were drift waiting to happen and are gone.
- **An English typo went with them.** `RequestWorkOrder.statusLabel` looked a
  Work order's status up in the *Request* map (a latent bug the model's own
  comment admitted). It is now read with the Work order vocabulary.

## Alternatives considered

- **A field on the model** (`WorkOrder(label: …)`). Impossible: a model is built
  from JSON with no context, and the same record is read by several Screens in
  whatever language is chosen *now*. It would also mean every Bloc holding a
  translated string, which is the bug rather than the fix.
- **A lookup keyed on the English label** (`l10n.byEnglish('In progress')`).
  Cheaper at the call site (no argument) but it makes English the identity of
  every word: rewording one English label silently breaks its translations, and
  a code with two English spellings has no home.
- **A global `AppLocalizations` singleton** set by the Shell. Fewest call-site
  edits, but it makes a widget's text depend on mutable global state, which no
  test can pump in two languages at once and no reviewer can trace.

## Consequences

- A code with no catalogue entry renders as itself (`blocked_by_qa` shows
  `blocked_by_qa`) rather than throwing or blanking. `docs/agents/domain.md`
  lists the codes this build has not been taught yet.
- `l10n/vocabulary.dart` imports the Module models (to declare the extensions)
  and `notices.dart` imports `vocabulary.dart` (to translate the code a notice
  carries). **Models import neither.** A model file stays free of Flutter and of
  the catalogue; only the adapters know both sides.
- A new status, type or role is added in three places, in this order: the code
  constant on the model, the ARB entry in both catalogues, and one arm of the
  lookup. The `_ => code` arm is what keeps a forgotten one visible rather than
  fatal.
- Not converted by this ADR, and still English: the ~150 interpolated notices a
  Bloc composes inline (`'${action.actionNo} was called off.'`), and the
  sentence-shaped getters that read as prose rather than vocabulary
  (`LeaveRequest.periodLabel`, `CostRate.amountLabel`). They are the next
  slice; the vocabulary and the notice registry are what it will build on.
