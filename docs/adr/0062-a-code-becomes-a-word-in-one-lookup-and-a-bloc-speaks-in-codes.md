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

**And the render itself resolves it — at every boundary.** A code that reaches a
`Text` is the bug, so the rendering is where the rule is enforced, not a habit at
each site:

- `frontend/lib/widgets/notice_text.dart` holds `NoticeText`, a drop-in for
  `Text` whose first argument is the Bloc-held message. Every surface that prints
  one uses it: 147 sites across 128 files, including the standard "the write was
  refused" block every `*dialog*.dart` keeps in its own `child:` (93 of them), the
  per-Screen `_Notice` banners, and the four Maintenance Screens that used to
  print `state.notice` / `state.failure` raw.
- `AppDialog`'s own `description` resolves the same way, so a dialog's refusal
  sentence is covered by the shell rather than by each caller (this is the path
  `action_escalate_dialog` reaches).
- `PlatformFailureState` already did (it is what the first pass wired, and it is
  the one site the tree had right).

`noticeText` returns prose unchanged, so `NoticeText` is safe everywhere, not
only where a code is expected — that is why the rule can be stated as "no
`notice:` value reaches a `Text`" rather than a list of call sites to remember.
Shared widgets resolve through `noticeTextFor(context, message)`, which leaves
the message alone when the tree carries no catalogue at all — that is a widget
test pumping one banner or one dialog on its own, not the app, where the
delegates are unconditional.

**Where the boundary of the rule is.** What this ADR forbids is a *word living
where no language exists*: on a model, on a Bloc, or in a static that cannot see
an `AppLocalizations`. A switch that already takes `l10n` is the same mechanism
wherever it sits — the router's 67 screen titles and one screen's own prose
switch (`action_phase_complete_dialog`) stay where they are, because moving them
would buy nothing and hide the sentence from the file that says it. The
catalogue is the home of the *vocabulary* (statuses, types, roles, severities,
the board's and handover's fixed sets), not of every sentence a Screen writes.

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

### Round 2: the registers the first pass did not reach

The first pass converted the words a *Screen* printed through a model getter and
wired the notice resolver at ten render sites. Both left work behind, and it was
the same defect in two shapes — an English word or a raw code still reaching a
reader:

- **Seven more model-level vocabularies**, each a table of English words beside
  its codes: `ComplaintStatus`/`ComplaintType`, `SupplierNcrStatus`/
  `SupplierNcrDisposition`, Downtime's `_statuses`, `AssetType`/`Criticality`
  (enum `label` fields), `DefectCategory`, `BoardKpi.statusLabel`, and
  `IssueKind.label`/`shortLabel` — plus `ReviewStatus` (the KPI Review's
  Met/Missed/Not measured) and the skill coverage legend. `HandoverVocabulary`
  was a `HandoverChoice(wire, label)` pair repeated seven times; it is now seven
  `List<String>` of wires, with the words in the adapter.
- **The Bloc's own copy, in the two places it was still literal**: the four
  `AccountsBloc` sites that inline "Another action is already in progress…" and
  the eight that inline "This session has ended. Sign in again to continue." now
  emit `BlocNotice.actionInFlight` / `BlocNotice.sessionEnded`.
- **The render boundary, everywhere.** Ten sites resolved notices and the rest
  printed the code: `notice:session-ended` was reachable in a dialog. `NoticeText`
  (above) and `AppDialog.description` close that class.

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
- Not converted by this ADR, and still English. The list is bounded and measured
  (grep, not a census) rather than "everything else", and
  `docs/agents/domain.md` carries it so the next slice starts from a list:
  - **21 English `static const String`s in 6 files** outside `l10n/` — the KPI
    targets table's own column headings, the palette toggle's tooltips, the slide
    show's tooltip, the KPI Review's two hints, one attendance sheet label;
  - **33 notices a Bloc still composes inline** (`notice: '${…} was called off.'`)
    — the parameterised registry covers the ones the sweep converted, not these;
  - **3 sentence-shaped model getters** (`CustomerComplaint.quantityLabel` /
    `dueLabel`, `SupplierNcr.dueLabel`) and `PlatformFailureState.retryLabel`'s
    English default;
  - **one filter count line** (`AppFilterField.countLabel`) and **two form-mode
    title sets** (`product_cost_form_dialog`, `cost_rate_form_dialog`).

  Every *status, type, role, severity and code* word is converted. What is left
  is prose the tree composes from several values at once, which is a different
  mechanism (a parameterised message, not a code → word lookup) and is why it is
  named here rather than quietly included.
