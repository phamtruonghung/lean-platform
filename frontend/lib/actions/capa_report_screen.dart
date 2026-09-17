/// The CAPA report (issue #212): one investigation laid out as an 8D, at its
/// own address, printable from the browser — the record an auditor or a
/// customer reads.
///
/// **A read and a layout, and nothing recorded.** Every section below renders
/// what ONE request already answers — `GET /api/actions/capas/:id`, the read
/// `CapaDetailScreen` makes — so there is no report endpoint, deliberately: a
/// second address for the same rows would be a second answer to one question,
/// and the first thing to drift. The sections are 8D's own order, and each maps
/// to a fact that read carries:
///
///   - D1 the team: `teamLead` and `teamMembers` (issue #209);
///   - D2 the problem: `problemStatement` (issue #209);
///   - D3 the containment, D5-D6 the Countermeasures and D7 the Preventive
///     actions with every PDCA phase each has been round: the Concern's own
///     measures, which ADR-0034 makes the CAPA's actions (issues #177, #209);
///   - D4 the fishbone of candidate causes with each verdict, then both chains
///     with their confirmed root causes: `causes` and `whys` (issues #210,
///     #213);
///   - D8 the effectiveness check with its verifier, date and note:
///     `effectivenessVerifiedBy`/`At`/`Note` (issue #211);
///   - the evidence: the Non-conformances the Concern answers, with their
///     number, Product, Defect code, quantity and Dispositions (issues #208,
///     #212 — the Dispositions are the one field this ticket added to that
///     read, because no earlier read sent them).
///
/// **What it does not record is the point.** ADR-0034 rejected a CAPA that owns
/// its own 8D steps in as many words: the same fix would be tracked twice and
/// the two would drift. Nothing here offers a control that writes, and the one
/// thing that changes a CAPA from this corner of the client is the link at the
/// top back to the CAPA's own Screen, where the chains and the check are
/// written.
///
/// **An unfinished investigation still reads**, which is half of what this
/// Screen is for: a section whose work has not been done says so in its own
/// sentence, and a CAPA with anything outstanding opens with a "Not yet done"
/// list of exactly what is missing (`_Report._outstanding`, computed from the
/// record rather than from the status). Nothing renders blank, and nothing
/// pretends.
///
/// **Its width is its own, deliberately.** `AppLayout.pageWidth` (900) is what
/// a catalogue spends; this is a document with two chains, three kinds of
/// measure and a table of evidence on it, so it spends the registers' own 1100
/// and says so here rather than inheriting a number nobody chose
/// (`docs/frontend-layout.md`'s page-widths bullet names it too). It is the
/// same licence the wide tables take.
library;

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'action.dart';
import 'capa.dart';
import 'capa_detail_bloc.dart';

/// The words this report prints for a Disposition's kind.
///
/// A deliberate second copy of Quality's `DispositionType.label` rather than a
/// shared one, and the seam is why: the client's dependency runs one way
/// (`quality` imports `actions` — see `actions.dart`), and this is the one
/// Screen in this Module that has to *print* the words, because a report is
/// read on paper and cannot link to the record that owns them. Four strings are
/// the cheaper half of that trade; if a second caller in this Module needs
/// them, they move into Quality's client entry point and this map goes.
///
/// `use_as_is` is labelled by [LinkedDisposition.isConcession] rather than by
/// its wire value, the same way Quality's own model labels it.
const Map<String, String> _dispositionLabels = {
  'scrap': 'Scrap',
  'rework': 'Rework',
  'return_to_supplier': 'Return to supplier',
};

String _dispositionLabel(LinkedDisposition disposition) =>
    disposition.isConcession
        ? 'Concession'
        : (_dispositionLabels[disposition.dispositionType] ?? disposition.dispositionType);

class CapaReportScreen extends StatelessWidget {
  const CapaReportScreen({super.key, required this.capaId});

  /// The CAPA this report is of — carried down from the route rather than
  /// re-read off the Bloc, so a retry asks for the same record.
  final String capaId;

  /// The report's own page width: the registers' 1100, not `AppLayout.pageWidth`
  /// — a document with two chains, three kinds of measure and a table of
  /// evidence on it (see this file's header for why that is a decision rather
  /// than an omission).
  static const double maxWidth = 1100;

  static const ValueKey<String> loadedKey = ValueKey<String>('capa-report-loaded');
  static const ValueKey<String> failedKey = ValueKey<String>('capa-report-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('capa-report-retry');
  static const ValueKey<String> backKey = ValueKey<String>('capa-report-back');

  /// What an investigation has not done yet, said once at the top rather than
  /// left to be inferred from seven sections.
  static const ValueKey<String> outstandingKey = ValueKey<String>('capa-report-outstanding');

  /// D1 — the team, and the sentence a team nobody has been named to yet reads.
  static const ValueKey<String> teamKey = ValueKey<String>('capa-report-team');
  static const ValueKey<String> noTeamKey = ValueKey<String>('capa-report-no-team');

  /// D2 — the problem description.
  static const ValueKey<String> problemKey = ValueKey<String>('capa-report-problem');
  static const ValueKey<String> noProblemKey = ValueKey<String>('capa-report-no-problem');

  /// D3, D5-D6 and D7 — the Concern's own work, one section per kind.
  static const ValueKey<String> containmentKey = ValueKey<String>('capa-report-containment');
  static const ValueKey<String> noContainmentKey =
      ValueKey<String>('capa-report-no-containment');
  static const ValueKey<String> countermeasuresKey =
      ValueKey<String>('capa-report-countermeasures');
  static const ValueKey<String> noCountermeasuresKey =
      ValueKey<String>('capa-report-no-countermeasures');
  static const ValueKey<String> preventiveKey = ValueKey<String>('capa-report-preventive');
  static const ValueKey<String> noPreventiveKey = ValueKey<String>('capa-report-no-preventive');

  /// D4 — the two 5 Why chains, and the fishbone they begin from.
  static const ValueKey<String> rootCauseKey = ValueKey<String>('capa-report-root-cause');

  /// The fishbone (issue #213) — the candidate causes by 6M category with each
  /// one's verdict, read above the chains because that is the order the team
  /// worked in and the order a customer's engineer reads a causality section.
  static const ValueKey<String> fishboneKey = ValueKey<String>('capa-report-fishbone');
  static const ValueKey<String> noCausesKey = ValueKey<String>('capa-report-no-causes');

  static ValueKey<String> causeCategoryKey(String category) =>
      ValueKey<String>('capa-report-cause-category-$category');

  static ValueKey<String> causeKey(String id) => ValueKey<String>('capa-report-cause-$id');

  static ValueKey<String> causeVerdictKey(String id) =>
      ValueKey<String>('capa-report-cause-$id-verdict');

  static ValueKey<String> causeEvidenceKey(String id) =>
      ValueKey<String>('capa-report-cause-$id-evidence');

  /// D8 — the effectiveness check.
  static const ValueKey<String> effectivenessKey = ValueKey<String>('capa-report-effectiveness');
  static const ValueKey<String> effectivenessRecordedKey =
      ValueKey<String>('capa-report-effectiveness-recorded');
  static const ValueKey<String> effectivenessDueKey =
      ValueKey<String>('capa-report-effectiveness-due');
  static const ValueKey<String> effectivenessOverdueKey =
      ValueKey<String>('capa-report-effectiveness-overdue');
  static const ValueKey<String> effectivenessNotRecordedKey =
      ValueKey<String>('capa-report-effectiveness-not-recorded');

  /// The evidence: the Non-conformances the Concern answers.
  static const ValueKey<String> nonconformancesKey =
      ValueKey<String>('capa-report-nonconformances');
  static const ValueKey<String> noNonconformancesKey =
      ValueKey<String>('capa-report-no-nonconformances');

  static ValueKey<String> chainKey(String chain) => ValueKey<String>('capa-report-chain-$chain');

  static ValueKey<String> chainEmptyKey(String chain) =>
      ValueKey<String>('capa-report-chain-$chain-empty');

  static ValueKey<String> chainRootKey(String chain) =>
      ValueKey<String>('capa-report-chain-$chain-root');

  static ValueKey<String> whyKey(String whyId) => ValueKey<String>('capa-report-why-$whyId');

  static ValueKey<String> measureKey(String actionId) =>
      ValueKey<String>('capa-report-measure-$actionId');

  static ValueKey<String> measurePhaseKey(String actionId, int cycle, String phase) =>
      ValueKey<String>('capa-report-measure-$actionId-phase-$cycle-$phase');

  static ValueKey<String> nonconformanceKey(String id) =>
      ValueKey<String>('capa-report-nonconformance-$id');

  static ValueKey<String> dispositionsKey(String id) =>
      ValueKey<String>('capa-report-nonconformance-$id-dispositions');

  static ValueKey<String> noDispositionsKey(String id) =>
      ValueKey<String>('capa-report-nonconformance-$id-no-dispositions');

  /// The report is its own `Scaffold` and nothing else: it is reached outside
  /// the Shell (see `buildRouter`), so there is no sidebar, no brand header and
  /// no account footer above it — and that is what makes the browser's own
  /// print produce the report rather than the navigation around it.
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CapaDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        CapaDetailLoading() => const SkeletonList(rows: 5, maxWidth: maxWidth),
        CapaDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: 'That CAPA report could not be read',
            message: message,
            retryKey: retryKey,
            onRetry: () => context.read<CapaDetailBloc>().add(CapaDetailStarted(capaId)),
          ),
        CapaDetailLoaded(capa: final capa) => _Report(capa: capa),
      },
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.capa});

  final Capa capa;

  /// What this investigation has not done yet, in the order the 8D asks for it.
  /// Computed from the record rather than from the CAPA's status: an
  /// investigation can be open with everything done but the check, or closed
  /// with no preventive action ever raised, and a reader of the report wants
  /// the facts rather than the status restated.
  List<String> get _outstanding {
    final missing = <String>[];
    if (capa.team.isEmpty) missing.add('The team has not been named.');
    if (capa.problemStatement == null) {
      missing.add('The problem description has not been written.');
    }

    final measures = capa.concern?.measures ?? const <Action>[];
    bool absent(String actionType) => !measures.any((measure) => measure.actionType == actionType);

    if (absent('containment')) missing.add('No containment action is recorded on the Concern.');
    for (final chain in capaChainOrder) {
      final whys = capa.whysIn(chain);
      if (whys.isEmpty) {
        missing.add('${capaChainLabel(chain)} has not been started.');
      } else if (capa.rootCauseOf(chain) == null) {
        missing.add('${capaChainLabel(chain)} has no confirmed root cause.');
      }
    }
    if (absent('countermeasure')) missing.add('No countermeasure is recorded on the Concern.');
    if (absent('preventive')) missing.add('No preventive action is recorded on the Concern.');
    if (capa.effectivenessVerifiedAt == null) {
      missing.add('The effectiveness check has not been recorded.');
    }
    return missing;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concern = capa.concern;
    final outstanding = _outstanding;

    return Center(
      child: AppPageFrame(
        maxWidth: CapaReportScreen.maxWidth,
        child: SingleChildScrollView(
          // A `SingleChildScrollView` rather than a `ListView`, deliberately:
          // a report is a document of a bounded length, so every section is
          // built and laid out whether or not it is on screen — which is what
          // a test can read, and what a printer's own pagination gets. A
          // lazily-built list would leave the foot of the report out of the
          // tree until somebody scrolled to it.
          key: CapaReportScreen.loadedKey,
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A `Wrap`, not a `Row`, for the reason every header in this
              // client is one: the link and the status chip are wider together
              // than an 800px window, and a `Wrap` drops the chip onto its own
              // line rather than overflowing.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  TextButton.icon(
                    key: CapaReportScreen.backKey,
                    onPressed: () => context.go('${Routes.actions}/capas/${capa.id}'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to the CAPA'),
                  ),
                  StatusChip(label: capa.statusLabel, tone: capa.statusTone),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Text(capa.capaNo, style: theme.textTheme.labelLarge),
              const SizedBox(height: Spacing.xs),
              Text(capa.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.sm),
              Text(
                'The 8D record of this investigation: its team, the problem it answers, what was '
                'done about it, and whether the fix held.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.sm),
              if (concern != null) ...[
                Text(
                  'Answers the Concern ${concern.actionNo} · ${concern.title}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.sm),
              ],
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(label: Text('${capa.methodLabel} investigation')),
                  Chip(label: Text(capa.orgUnitName)),
                  if (capa.openedAt != null)
                    Chip(
                      label: Text(
                        'opened ${capa.openedAt!.toLocal().toIso8601String().substring(0, 10)}',
                      ),
                    ),
                  if (capa.dueDate != null) Chip(label: Text('due ${capa.dueDate}')),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              if (outstanding.isNotEmpty)
                _Section(
                  key: CapaReportScreen.outstandingKey,
                  heading: 'Not yet done',
                  summary: 'What this report is still waiting for.',
                  children: [
                    for (final item in outstanding)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.xxs),
                        child: Text('· $item', style: theme.textTheme.bodyMedium),
                      ),
                  ],
                ),
              ..._sections(context),
            ],
          ),
        ),
      ),
    );
  }

  /// The 8D's own order, one section per step, with the evidence last.
  List<Widget> _sections(BuildContext context) {
    final theme = Theme.of(context);
    final concern = capa.concern;
    final measures = concern?.measures ?? const <Action>[];
    List<Action> ofType(String actionType) =>
        [for (final measure in measures) if (measure.actionType == actionType) measure];

    return [
      _Section(
        key: CapaReportScreen.teamKey,
        heading: 'D1 · Team',
        summary: 'Who investigated this problem, and who led it.',
        children: [
          if (capa.team.isEmpty)
            Text(
              key: CapaReportScreen.noTeamKey,
              'Nobody is on this investigation yet.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          for (final member in capa.team)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xxs),
              child: Text(
                member.employeeId == capa.teamLead?.employeeId
                    ? '${member.name} · team lead'
                    : member.name,
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
      _Section(
        key: CapaReportScreen.problemKey,
        heading: 'D2 · The problem',
        summary: 'What the team is investigating, in the investigation\'s own words.',
        children: [
          Text(
            key: capa.problemStatement == null ? CapaReportScreen.noProblemKey : null,
            capa.problemStatement ?? 'Nobody has written the problem description yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: capa.problemStatement == null ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
        ],
      ),
      _Section(
        key: CapaReportScreen.containmentKey,
        heading: 'D3 · Containment',
        summary: 'What was done to stop the bad product going any further.',
        emptyKey: CapaReportScreen.noContainmentKey,
        emptySentence: 'No containment action is recorded on the Concern yet.',
        measures: ofType('containment'),
      ),
      _Section(
        key: CapaReportScreen.rootCauseKey,
        heading: 'D4 · Root cause',
        summary: 'The candidate causes the team considered and the verdict on each, then two '
            'chains ending at one confirmed root cause: why the problem happened, and why it '
            'was not detected.',
        children: [
          _ReportFishbone(capa: capa),
          const SizedBox(height: Spacing.md),
          for (final chain in capaChainOrder) ...[
            _Chain(capa: capa, chain: chain),
            if (chain != capaChainOrder.last) const SizedBox(height: Spacing.md),
          ],
        ],
      ),
      _Section(
        key: CapaReportScreen.countermeasuresKey,
        heading: 'D5–D6 · Countermeasures',
        summary: 'What was done about the cause, and whether its Check held.',
        emptyKey: CapaReportScreen.noCountermeasuresKey,
        emptySentence: 'No countermeasure is recorded on the Concern yet.',
        measures: ofType('countermeasure'),
      ),
      _Section(
        key: CapaReportScreen.preventiveKey,
        heading: 'D7 · Preventive actions',
        summary: 'What stops it happening on this line again, with the outcome of every round.',
        emptyKey: CapaReportScreen.noPreventiveKey,
        emptySentence: 'No preventive action is recorded on the Concern yet.',
        measures: ofType('preventive'),
      ),
      _Effectiveness(capa: capa),
      _Section(
        key: CapaReportScreen.nonconformancesKey,
        heading: 'The Non-conformances this investigation answers',
        summary: 'The occurrences the Concern answers, with the number, the Product, the Defect '
            'code, the quantity and what was decided about the product.',
        children: [
          if (concern == null || concern.nonconformances.isEmpty)
            Text(
              key: CapaReportScreen.noNonconformancesKey,
              'No Non-conformance is linked to this Concern, so the report has no evidence to '
              'list.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          for (final occurrence in concern?.nonconformances ?? const <LinkedNonconformance>[])
            _Occurrence(occurrence: occurrence),
        ],
      ),
    ];
  }
}

/// One section of the report: an 8D step's heading, the sentence saying what
/// the step is for, and the facts it holds — or the one sentence saying the
/// investigation has not got there yet.
///
/// A section of measures is the same shape, which is why [measures] and
/// [emptyKey]/[emptySentence] are here rather than in three near-identical
/// widgets.
class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.heading,
    required this.summary,
    this.children = const [],
    this.measures = const [],
    this.emptyKey,
    this.emptySentence,
  });

  final String heading;
  final String summary;
  final List<Widget> children;

  /// The Actions this section prints, in the order the server sent them.
  final List<Action> measures;

  /// The sentence a section with nothing in it reads, and the key it carries —
  /// the report's explicit "not yet", rather than a blank space an auditor
  /// would read as an omission.
  final Key? emptyKey;
  final String? emptySentence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = children.isEmpty && measures.isEmpty;

    return Card(
      // `Card`'s own 4px margin would push this section off the page's left
      // edge, which is where a section belongs (the page frame's own inset,
      // measured by `page_alignment_test.dart`); the gap between sections is
      // the margin below.
      margin: const EdgeInsets.only(bottom: Spacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.xxs),
            Text(
              summary,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.md),
            if (empty && emptySentence != null)
              Text(
                key: emptyKey,
                emptySentence!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else ...[
              ...children,
              for (final measure in measures) _Measure(measure: measure),
            ],
          ],
        ),
      ),
    );
  }
}

/// One measure of the Concern — a Containment, a Countermeasure or a Preventive
/// action — with every phase of every cycle it has been round, which is the
/// PDCA outcome D5–D7 are read for (ADR-0033: the round that failed is kept).
class _Measure extends StatelessWidget {
  const _Measure({required this.measure});

  final Action measure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      key: CapaReportScreen.measureKey(measure.id),
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            measure.title,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: Spacing.xxs),
          Text(
            [
              measure.actionNo,
              measure.typeLabel,
              measure.statusLabel,
              measure.ownerName ?? 'Nobody yet',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          for (final phase in measure.phases)
            Padding(
              key: CapaReportScreen.measurePhaseKey(measure.id, phase.cycle, phase.phase),
              padding: const EdgeInsets.only(top: Spacing.xxs),
              child: Text(
                [
                  'Cycle ${phase.cycle} · ${phase.phaseLabel}',
                  if (phase.completedAt != null) 'done' else 'open',
                  if (phase.outcomeLabel != null) phase.outcomeLabel!,
                  if (phase.note != null) phase.note!,
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (measure.phases.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xxs),
              child: Text(
                'No phase of this Action has been completed yet.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// The fishbone as the report reads it (issue #213) — D4's own list of what the
/// team considered, before the chains say what it concluded.
///
/// **Only the bones that carry a cause are printed**, unlike the Screen, which
/// shows all six. The difference is deliberate and it is the medium's: a reader
/// of a Screen is working on the investigation and wants to see which category
/// nobody has thought about, where a printed 8D handed to a customer carries
/// what the team found, and six lines of "nothing is recorded under Man" is
/// noise in a document. A CAPA with no causes at all still says so in one
/// sentence rather than printing nothing, because "no fishbone was done" is a
/// fact about the investigation an auditor is entitled to read.
class _ReportFishbone extends StatelessWidget {
  const _ReportFishbone({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = [
      for (final category in capaCauseCategoryOrder)
        if (capa.causesIn(category).isNotEmpty) category,
    ];

    return Column(
      key: CapaReportScreen.fishboneKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('The candidate causes considered', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        if (categories.isEmpty)
          Text(
            key: CapaReportScreen.noCausesKey,
            'No candidate cause is recorded, so no fishbone was worked.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final category in categories)
          Padding(
            key: CapaReportScreen.causeCategoryKey(category),
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(capaCauseCategoryLabel(category), style: theme.textTheme.labelLarge),
                for (final cause in capa.causesIn(category))
                  Padding(
                    key: CapaReportScreen.causeKey(cause.id),
                    padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.xxs, 0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cause.statement,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.xxs),
                          child: Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusChip(
                                key: CapaReportScreen.causeVerdictKey(cause.id),
                                label: cause.verdictLabel,
                                tone: cause.verdictTone,
                              ),
                              if (cause.evidenceNote != null)
                                Text(
                                  key: CapaReportScreen.causeEvidenceKey(cause.id),
                                  'Evidence: ${cause.evidenceNote}',
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One of the two 5 Why chains (D4): its own heading, its Whys in the order they
/// were reasoned, and where it stopped.
class _Chain extends StatelessWidget {
  const _Chain({required this.capa, required this.chain});

  final Capa capa;
  final String chain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final whys = capa.whysIn(chain);
    final root = capa.rootCauseOf(chain);

    return Column(
      key: CapaReportScreen.chainKey(chain),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(capaChainLabel(chain), style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        if (whys.isEmpty)
          Text(
            key: CapaReportScreen.chainEmptyKey(chain),
            'Nobody has started this chain yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final why in whys)
          Padding(
            key: CapaReportScreen.whyKey(why.id),
            padding: const EdgeInsets.only(bottom: Spacing.xxs),
            child: Text(
              'Why ${why.sequence} · ${why.statement}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            key: CapaReportScreen.chainRootKey(chain),
            root == null
                ? 'This chain has no confirmed root cause yet.'
                : 'Confirmed root cause: ${root.statement}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: root == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
              fontWeight: root == null ? null : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// D8 — the effectiveness check: who verified that the fix held, when, and what
/// they said, or the sentence saying which of the three "not yet" states the
/// investigation is in.
class _Effectiveness extends StatelessWidget {
  const _Effectiveness({required this.capa});

  final Capa capa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verifiedAt = capa.effectivenessVerifiedAt;
    final dueAt = capa.effectivenessCheckDueAt;

    return _Section(
      key: CapaReportScreen.effectivenessKey,
      heading: 'D8 · Effectiveness',
      summary: 'A CAPA closes only when both chains have a confirmed root cause, its Concern is '
          'closed, and somebody holding Quality authority other than its team lead has verified, '
          'some time later, that the problem has not come back.',
      children: [
        if (verifiedAt != null)
          Column(
            key: CapaReportScreen.effectivenessRecordedKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(
                    label: capaEffectivenessOutcomeLabel(capa.effectivenessOutcome!),
                    tone: capaEffectivenessOutcomeTone(capa.effectivenessOutcome!),
                  ),
                  Text(
                    'verified by ${capa.effectivenessVerifiedBy?.name ?? 'an Account'} on '
                    '${verifiedAt.toLocal().toIso8601String().substring(0, 10)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              if (capa.effectivenessNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(capa.effectivenessNote!, style: theme.textTheme.bodyMedium),
                ),
            ],
          )
        else if (dueAt != null)
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                key: CapaReportScreen.effectivenessDueKey,
                'The Concern has closed, so the effectiveness check is due on $dueAt.',
                style: theme.textTheme.bodyMedium,
              ),
              if (capa.effectivenessCheckOverdue)
                StatusChip(
                  key: CapaReportScreen.effectivenessOverdueKey,
                  label: 'Overdue',
                  tone: StatusTone.warning,
                ),
            ],
          )
        else
          Text(
            key: CapaReportScreen.effectivenessNotRecordedKey,
            'The check falls due ${capa.effectivenessCheckDelayDays} days after the Concern '
            'closes, and the Concern has not closed yet, so nothing has been verified.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// One Non-conformance the Concern answers: the number a person quotes, what was
/// made wrong, why, how much of it, and — the reason an auditor reads this
/// section at all — every Disposition recorded against it.
class _Occurrence extends StatelessWidget {
  const _Occurrence({required this.occurrence});

  final LinkedNonconformance occurrence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dispositions = occurrence.dispositions;

    return Padding(
      key: CapaReportScreen.nonconformanceKey(occurrence.id),
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            occurrence.issueNo,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: Spacing.xxs),
          Text(
            [
              occurrence.productLabel,
              occurrence.defectCodeLabel,
              occurrence.quantityLabel,
              occurrence.isSource ? 'raised from this' : 'linked to this Concern',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.xs),
          if (dispositions.isEmpty)
            Text(
              key: CapaReportScreen.noDispositionsKey(occurrence.id),
              'No product from this occurrence has a Disposition yet.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Column(
              key: CapaReportScreen.dispositionsKey(occurrence.id),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final disposition in dispositions)
                  Text(
                    [
                      _dispositionLabel(disposition),
                      disposition.quantityLabel,
                      if (disposition.reworkMinutes != null && disposition.reworkMinutes != 0)
                        '${disposition.reworkMinutes!.toStringAsFixed(0)} min rework',
                      'decided by ${disposition.decidedBy}',
                      if (disposition.decidedOn != null) disposition.decidedOn!,
                      if (disposition.reference != null) disposition.reference!,
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
