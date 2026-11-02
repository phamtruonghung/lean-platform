/// The Job plan catalogue (issue #74): every reusable description of a
/// recurring job, each with its ordered steps, laid over an administrator's
/// own write surface for it (`POST`/`PATCH /api/maintenance/job-plans`).
///
/// CONTEXT.md's distinction is load-bearing in the copy: a Job plan is the
/// instructions, the Work order that carries it out is one particular occasion
/// of following them. The read is open to any approved Account
/// (job-plan-routes.js's own header); the write affordances inside — adding a
/// plan, deactivating or reactivating one — are offered only to an
/// administrator ([isAdmin]), since the server refuses them for every other
/// role. A non-administrator sees the catalogue and no way to change it.
///
/// **A register of five columns, and a card per plan below 700px of content.**
/// At or above [JobPlansScreen.narrowBreakpoint] (at a text scale of 1) the
/// plans are an `AppTableHeader` band and one `AppTableRow` per plan, both built
/// from the one column spec [_columns]. A plan's steps (and its description) are
/// prose, not a value to compare down a column, so the register keeps them one
/// press away in a `RowDisclosure` under the row and loses none of them; the card
/// below the breakpoint shows them all, as it always has. There is no Site
/// selector on this Screen (a Job plan belongs to the plant, not a Site), so the
/// list's toolbar holds the filter alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_filter_field.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/app_page_header.dart';
import '../widgets/app_table.dart';
import '../widgets/app_toolbar.dart';
import '../widgets/disclosing_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'job_plan.dart';
import 'job_plan_form_dialog.dart';
import 'job_plans_bloc.dart';
import 'name_with_chip.dart';
import 'row_disclosure.dart';

class JobPlansScreen extends StatelessWidget {
  const JobPlansScreen({super.key, required this.isAdmin});

  /// Whether this caller may add, deactivate or reactivate a plan — read off
  /// `/me`'s own role, the same shape `SkillsScreen.isAdmin` follows.
  final bool isAdmin;

  static const double maxWidth = 960;

  /// The content width (at a text scale of 1) below which the register gives way
  /// to one card per plan, measured by `_JobPlansList`'s `LayoutBuilder`, never
  /// the window. Five columns is inside the five-column rule, so this is the
  /// Platform's own [AppBreakpoints.registerTable], not a number of this
  /// Screen's.
  static const double narrowBreakpoint = AppBreakpoints.registerTable;

  /// The toggle that opens a register row's steps.
  static ValueKey<String> stepsKey(String id) => ValueKey<String>('job-plan-steps-$id');

  static const ValueKey<String> addKey = ValueKey<String>('job-plans-add');
  static const ValueKey<String> noticeKey = ValueKey<String>('job-plans-notice');
  static const ValueKey<String> retryKey = ValueKey<String>('job-plans-retry');
  static const ValueKey<String> emptyKey = ValueKey<String>('job-plans-empty');
  static const ValueKey<String> failedKey = ValueKey<String>('job-plans-failed');

  static ValueKey<String> rowKey(String id) => ValueKey<String>('job-plan-row-$id');
  static ValueKey<String> toggleKey(String id) => ValueKey<String>('job-plan-toggle-$id');
  static ValueKey<String> inactiveChipKey(String id) => ValueKey<String>('job-plan-inactive-$id');

  /// The filter box's `name` (issue #191), seeding [filterFieldKey],
  /// [filterClearKey] and [filterCountKey] — kept in one place so the field's
  /// own name and the keys a test reaches it by cannot drift, the same device
  /// `WorkOrderAssignDialog.searchFieldName` uses (issue #187).
  static const String filterFieldName = 'job-plans-filter';

  static ValueKey<String> get filterFieldKey => AppFilterField.fieldKey(filterFieldName);
  static ValueKey<String> get filterClearKey => AppFilterField.clearKey(filterFieldName);
  static ValueKey<String> get filterCountKey => AppFilterField.countKey(filterFieldName);

  /// What a term matching none of the Job plans renders — a different fact from
  /// [emptyKey]: "nothing matched" is not "there is nothing here".
  static const ValueKey<String> noMatchKey = ValueKey<String>('job-plans-no-match');

  static ValueKey<String> taskKey(String planId, String taskId) =>
      ValueKey<String>('job-plan-task-$planId-$taskId');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<JobPlansBloc>().state;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, isAdmin: isAdmin),
          if (state is JobPlansLoaded && state.notice != null) _Notice(message: state.notice!),
          Expanded(
            child: switch (state) {
              JobPlansLoading() => const SkeletonList(rows: 4, maxWidth: maxWidth),
              JobPlansUnavailable(message: final message) => PlatformFailureState(
                key: JobPlansScreen.failedKey,
                title: 'The Job plans could not be read',
                message: message,
                retryKey: JobPlansScreen.retryKey,
                onRetry: () => context.read<JobPlansBloc>().add(const JobPlansStarted()),
              ),
              JobPlansLoaded(plans: final plans) when plans.isEmpty => const _JobPlansEmpty(),
              JobPlansLoaded(plans: final plans) => _JobPlansList(plans: plans, isAdmin: isAdmin),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.isAdmin});

  final JobPlansState state;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final loaded = state is JobPlansLoaded ? state as JobPlansLoaded : null;

    return Center(
      child: AppPageFrame(
        maxWidth: JobPlansScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
          child: AppPageHeader(
            title: 'Job plans',
            description:
                'How each recurring job is done — the steps it takes and what each one '
                'requires. A Work order follows a plan; it does not change one.',
            actions: [
              if (isAdmin && loaded != null)
                FilledButton.icon(
                  key: JobPlansScreen.addKey,
                  onPressed: loaded.isMutating ? null : () => JobPlanFormDialog.open(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a Job plan'),
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: AppPageFrame(
        maxWidth: JobPlansScreen.maxWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.md),
          child: Container(
            key: JobPlansScreen.noticeKey,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.dense(context)
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The list of Job plans. Stateful only because the filter box's term is the
/// Screen's own (issue #191): a filter is a view of the rows the Bloc already
/// holds, not a state of the domain, so typing costs a `setState` and never a
/// Bloc event.
class _JobPlansList extends StatefulWidget {
  const _JobPlansList({required this.plans, required this.isAdmin});

  final List<JobPlan> plans;
  final bool isAdmin;

  @override
  State<_JobPlansList> createState() => _JobPlansListState();
}

class _JobPlansListState extends State<_JobPlansList> {
  /// What the filter box is narrowing the Job plans to, `''` when nothing is.
  String _term = '';

  /// Whether [plan] matches [term], already lower-cased and trimmed: a
  /// case-insensitive substring over the fields that identify a Job plan —
  /// its name, its code and what it sets out to do. A Job plan carries no
  /// Asset of its own: an Asset is bound to a plan by a PM schedule, so the
  /// Asset names a planner types are matched on the PM schedules Screen,
  /// where that binding lives (issue #191).
  static bool _matches(JobPlan plan, String term) =>
      plan.name.toLowerCase().contains(term) ||
      plan.code.toLowerCase().contains(term) ||
      (plan.description ?? '').toLowerCase().contains(term);

  /// The rows actually rendered — every one of them while the term is empty.
  List<JobPlan> get _matchingPlans {
    final term = _term.trim().toLowerCase();
    if (term.isEmpty) return widget.plans;
    return widget.plans.where((plan) => _matches(plan, term)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Filtered here, immediately before the row widgets are built, so a term
    // can only ever narrow rows this Screen already read (issue #191).
    final matches = _matchingPlans;
    // The box this Screen actually got from its parent, scaled by the reader's
    // text size (design-language §10) — never the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth <
            AppBreakpoints.effective(context, JobPlansScreen.narrowBreakpoint);
        final columns = _columns(context, isAdmin: widget.isAdmin);
        return Center(
          child: AppPageFrame(
            maxWidth: JobPlansScreen.maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A toolbar's `Wrap` hands its children unbounded width, which a
                // text field cannot take, so the field is given the box's own width.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: LayoutBuilder(
                    builder: (context, box) => AppToolbar(
                      filters: [
                        SizedBox(
                          width: box.maxWidth,
                          child: AppFilterField(
                            name: JobPlansScreen.filterFieldName,
                            label: 'Filter Job plans',
                            helperText: 'By name, code or description.',
                            term: _term,
                            onChanged: (term) => setState(() => _term = term),
                            shown: matches.length,
                            total: widget.plans.length,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Expanded(
                  child: matches.isEmpty
                      ? PlatformEmptyState.noneMatched(
                          key: JobPlansScreen.noMatchKey,
                          title: 'No Job plans match',
                          message:
                              'The plant has Job plans, but none matches '
                              '"${_term.trim()}". Try a different name, code or description.',
                        )
                      : narrow
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                          itemBuilder: (context, index) =>
                              _JobPlanCard(plan: matches[index], isAdmin: widget.isAdmin),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.xl),
                          children: [
                            AppTableHeader(columns: columns),
                            // Keyed by the plan's id so a row that is open stays
                            // open when the list rebuilds on a filter keystroke.
                            for (final plan in matches)
                              _JobPlanTableRow(
                                key: ValueKey<String>('job-plan-disclosure-${plan.id}'),
                                columns: columns,
                                plan: plan,
                                isAdmin: widget.isAdmin,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The widest of [labels] in the button label style at the reader's text scale.
double _widestLabel(BuildContext context, Iterable<String> labels) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  var widest = 0.0;
  for (final label in labels) {
    painter.text = TextSpan(text: label, style: Theme.of(context).textTheme.labelLarge);
    painter.layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest;
}

/// A band label's width in the band's own style (`AppTableHeader`: `labelMedium`,
/// w600, letter spacing 0.2) at the reader's text scale, so a number column
/// sized to it never ellipsizes its label.
double _bandLabelWidth(BuildContext context, String label) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// The register's one column spec. [AppTableHeader] and every [AppTableRow] are
/// built from this list, so a label and its cells start at the same x. The Plan
/// cell carries the name, the `code · kind` line and the `Inactive` chip, as the
/// card's header does; the hours are a number, so end-aligned in tabular
/// figures; the shutdown marker is the card's own words. Only an administrator
/// has the Actions column, because only an administrator is offered the act.
List<AppTableColumn> _columns(BuildContext context, {required bool isAdmin}) => [
  const AppTableColumn('Plan', flex: 4),
  const AppTableColumn('Steps', flex: 2),
  // A number column is sized to its label, which is wider than its digits.
  AppTableColumn(
    'Estimated hours',
    width: _bandLabelWidth(context, 'Estimated hours') + Spacing.sm,
    align: AppColumnAlign.end,
  ),
  const AppTableColumn('Shutdown', flex: 2),
  if (isAdmin)
    AppTableColumn(
      'Actions',
      // The button's widest label, its own horizontal padding either side
      // (`Spacing.xl`), and the slot's gutter.
      width:
          _widestLabel(context, const ['Deactivate', 'Reactivate']) + 2 * Spacing.xl + Spacing.sm,
      align: AppColumnAlign.end,
    ),
];

class _JobPlanTableRow extends StatelessWidget {
  const _JobPlanTableRow({
    super.key,
    required this.columns,
    required this.plan,
    required this.isAdmin,
  });

  final List<AppTableColumn> columns;
  final JobPlan plan;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final state = context.watch<JobPlansBloc>().state;
    final busy = state is JobPlansLoaded && state.isMutating;
    final dense = AppTypography.dense(context);
    final muted = dense?.copyWith(color: palette.textMuted);
    final stepCount = plan.tasks.length;
    // The framework's padded tap target is lifted on the chip and the button: the
    // button states its own 44 through `minimumSize`.
    Widget shrinkWrapTargets(Widget child) => Theme(
      data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: child,
    );

    return RowDisclosure(
      toggleKey: JobPlansScreen.stepsKey(plan.id),
      label: '$stepCount ${stepCount == 1 ? 'step' : 'steps'}',
      rowBuilder: (context, toggle) => KeyedSubtree(
        key: JobPlansScreen.rowKey(plan.id),
        child: AppTableRow(
          columns: columns,
          cells: [
            NameWithChip(
              name: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DisclosingText(plan.name, style: dense?.copyWith(color: palette.textPrimary)),
                  DisclosingText('${plan.code} · ${plan.workTypeLabel}', style: muted),
                ],
              ),
              chipLabel: 'Inactive',
              chip: plan.isActive
                  ? null
                  : shrinkWrapTargets(
                      StatusChip(
                        key: JobPlansScreen.inactiveChipKey(plan.id),
                        label: 'Inactive',
                        tone: StatusTone.neutral,
                      ),
                    ),
            ),
            toggle,
            // No estimate is unknown, so the em dash, never a blank (design-language
            // §13). The Shutdown cell beside it stays empty for a plan that needs
            // none: that is a known "no", shown by the marker's absence as the
            // card shows it.
            Text(
              plan.estimatedHours == null ? '—' : '${plan.estimatedHours}',
              maxLines: 1,
              style: AppTableRow.numberStyle(context)?.copyWith(
                color: plan.estimatedHours == null ? palette.textMuted : palette.textPrimary,
              ),
            ),
            plan.requiresShutdown
                ? DisclosingText('Requires a shutdown', style: muted)
                : const SizedBox.shrink(),
            if (isAdmin)
              shrinkWrapTargets(
                OutlinedButton(
                  key: JobPlansScreen.toggleKey(plan.id),
                  onPressed: busy
                      ? null
                      : () => context.read<JobPlansBloc>().add(
                          JobPlanActiveToggled(jobPlanId: plan.id, isActive: !plan.isActive),
                        ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(AppTouchTarget.min, AppTouchTarget.min),
                  ),
                  child: Text(plan.isActive ? 'Deactivate' : 'Reactivate'),
                ),
              ),
          ],
        ),
      ),
      // What the card shows below its header: the description, then every step
      // exactly as the card draws it.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            Text(plan.description!, style: dense?.copyWith(color: palette.textPrimary)),
            const SizedBox(height: Spacing.sm),
          ],
          if (plan.tasks.isEmpty)
            Text('No steps recorded.', style: muted)
          else
            for (final task in plan.tasks) _JobPlanTaskRow(plan: plan, task: task),
        ],
      ),
    );
  }
}

class _JobPlanCard extends StatelessWidget {
  const _JobPlanCard({required this.plan, required this.isAdmin});

  final JobPlan plan;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    final state = context.watch<JobPlansBloc>().state;
    final busy = state is JobPlansLoaded && state.isMutating;

    return Card(
      key: JobPlansScreen.rowKey(plan.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: AppTypography.dense(context)?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text('${plan.code} · ${plan.workTypeLabel}', style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                if (!plan.isActive)
                  StatusChip(
                    key: JobPlansScreen.inactiveChipKey(plan.id),
                    label: 'Inactive',
                    tone: StatusTone.neutral,
                  ),
              ],
            ),
            if (plan.description != null && plan.description!.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Text(plan.description!, style: AppTypography.dense(context)),
            ],
            if (plan.requiresShutdown || plan.estimatedHours != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                [
                  if (plan.requiresShutdown) 'Requires a shutdown',
                  if (plan.estimatedHours != null) 'About ${plan.estimatedHours} h',
                ].join(' · '),
                style: muted,
              ),
            ],
            const SizedBox(height: Spacing.md),
            if (plan.tasks.isEmpty)
              Text('No steps recorded.', style: muted)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final task in plan.tasks) _JobPlanTaskRow(plan: plan, task: task)],
              ),
            if (isAdmin) ...[
              const SizedBox(height: Spacing.md),
              OutlinedButton(
                key: JobPlansScreen.toggleKey(plan.id),
                onPressed: busy
                    ? null
                    : () => context.read<JobPlansBloc>().add(
                        JobPlanActiveToggled(jobPlanId: plan.id, isActive: !plan.isActive),
                      ),
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(plan.isActive ? 'Deactivate' : 'Reactivate'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One step: its number and instruction, and the required Skill's name when
/// one is set — the fact the ticket's own criterion asks to be visible.
class _JobPlanTaskRow extends StatelessWidget {
  const _JobPlanTaskRow({required this.plan, required this.task});

  final JobPlan plan;
  final JobPlanTask task;

  @override
  Widget build(BuildContext context) {
    final muted = AppTypography.floor(context)?.copyWith(color: AppColors.of(context).textMuted);
    return Padding(
      key: JobPlansScreen.taskKey(plan.id, task.id),
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: Text('${task.stepNo}.', style: muted)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.instruction, style: AppTypography.dense(context)),
                if (task.hasSkill)
                  Text('Requires ${task.skillName}', style: muted)
                else
                  Text('No skill required', style: muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobPlansEmpty extends StatelessWidget {
  const _JobPlansEmpty();

  @override
  Widget build(BuildContext context) {
    return const PlatformEmptyState.noneExist(
      key: JobPlansScreen.emptyKey,
      title: 'No Job plans yet',
      message: 'No reusable job plan has been defined. Add one and its steps will show here.',
    );
  }
}
