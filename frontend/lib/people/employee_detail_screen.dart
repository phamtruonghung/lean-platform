/// One Employee's record (issue #86, AC5): job role, Assignment history with
/// the current Assignment distinguished from past ones, and the skills held.
///
/// The administrator's write surface over the record itself — correcting it,
/// recording a departure, reinstating one — lands here too (issue #87): #86's
/// own comment already named this Screen, not a Directory row, as where
/// #87/#88/#89 would add their actions, since only here is the whole record
/// (and #88/#89's own Assignments and skills) on screen at once. [isAdmin]
/// hides all three from anyone else, a Member included (AC7 for #86, AC6 for
/// #87) — the same role gate `AssetsScreen.canPlaceAnAsset` follows, except
/// this one is a role check (`requireAdmin`, ADR-0009), not a Grant one.
///
/// Assigning an Employee to an Org Unit (issue #88) is gated differently from
/// those three: ADR-0010 puts `POST .../assignments` behind write scope on
/// the *destination* Org Unit, not behind `requireAdmin`, so [canAssign] is a
/// Grant check (`OrgUnitScope.canWriteSomewhere`), read at the router the same
/// way `AssetsScreen.canPlaceAnAsset` already is — not the [isAdmin] role
/// check the other three actions use. A supervisor with no administrator role
/// at all can still see this action; an administrator with no Grant of their
/// own still sees it too, since `canAct` already returns true for that role
/// unconditionally (ADR-0010's own decision).
///
/// **A summary card, then sections (#392, `design-language.md` §6's "The
/// detail").** The record opens with the four facts that identify a person —
/// their initials, their name, their Employee number with the job role and
/// employment type beside it, and whether they still work here — as one card,
/// because those are the facts a reader confirms before reading anything else.
/// The actions that write to the record are that card's footer, where the thing
/// they act on is; the sections below it are `AppDetailSection`s in an
/// `AppSectionGrid`, so Assignment history and Skills sit side by side once the
/// box reaches [AppBreakpoints.detailTwoColumn] (1000, and this page names a 1040
/// frame to reach it at a 1280 window) and stack below that. A section's own
/// empty state is a sentence inside the section, with the `Key` it always had.
///
/// **A date is worded the way a person says it (§13).** The Assignment history
/// reads `From 31 Jan 2026`, never `From 2026-01-31`: the two strings are the
/// same sentence, and [formatPeriod] is the helper this module owes that rule —
/// no `DateTime` is parsed out of a DATE column on the way, the same discipline
/// `employee.dart`'s own header keeps for the wire's calendar strings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../l10n/notices.dart';
import '../platform/router.dart';
import '../status_tone.dart';
import '../theme.dart';
import '../widgets/app_detail_section.dart';
import '../widgets/app_page_frame.dart';
import '../widgets/failure_state.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/status_chip.dart';
import 'assignee_candidate.dart' show HeldSkill;
import 'employee.dart';
import 'employee_assignment_dialog.dart';
import 'employee_correction_dialog.dart';
import 'employee_departure_dialog.dart';
import 'employee_signature_dialog.dart';
import 'employee_detail_bloc.dart';
import 'employee_skill_form_dialog.dart';
import 'period_format.dart';
import 'skill.dart';
import '../l10n/vocabulary.dart';

class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({
    super.key,
    required this.employeeId,
    required this.isAdmin,
    required this.canAssign,
  });

  /// Null for "my own record" — carried only so a failed load's retry asks
  /// for the same record again, rather than always falling back to `/me`.
  final String? employeeId;

  /// Whether this caller may correct, depart or reinstate this record
  /// (issue #87) — read off `/me`'s own role, the same shape
  /// `DirectoryScreen.isAdmin` follows.
  final bool isAdmin;

  /// Whether this caller may assign this Employee to *some* Org Unit
  /// (issue #88) — `OrgUnitScope.canWriteSomewhere`, the everywhere-first rule
  /// expressed once so this Screen does not re-derive it. This is coarser
  /// than "may assign to the Org Unit I am about to pick": the server is the
  /// real gate on any one destination (403 `OUTSIDE_GRANTED_ORG_UNITS`), the
  /// same shape `WorkOrdersScreen.canAssignWorkOrder` already accepts for the
  /// same reason.
  final bool canAssign;

  /// A detail page's width, not a catalogue's: at 1040 the page is handed 1020
  /// at a 1280 window, which is over [AppBreakpoints.detailTwoColumn] (1000), so
  /// the two sections share a row there. At a 900 window the same page has 640
  /// and the sections stack (§6's own paragraph on this number).
  static const double maxWidth = 1040;

  static const ValueKey<String> failedKey = ValueKey<String>('employee-detail-failed');
  static const ValueKey<String> retryKey = ValueKey<String>('employee-detail-retry');
  static const ValueKey<String> departedKey = ValueKey<String>('employee-detail-departed');
  static const ValueKey<String> noAssignmentsKey = ValueKey<String>('employee-detail-no-assignments');
  static const ValueKey<String> noSkillsKey = ValueKey<String>('employee-detail-no-skills');
  static const ValueKey<String> correctKey = ValueKey<String>('employee-detail-correct');
  static const ValueKey<String> departKey = ValueKey<String>('employee-detail-depart');
  static const ValueKey<String> reinstateKey = ValueKey<String>('employee-detail-reinstate');
  static const ValueKey<String> signatureKey = ValueKey<String>('employee-detail-signature');
  static const ValueKey<String> assignKey = ValueKey<String>('employee-detail-assign');
  static const ValueKey<String> workedHoursKey = ValueKey<String>('employee-detail-worked-hours');
  static const ValueKey<String> noticeKey = ValueKey<String>('employee-detail-notice');
  static ValueKey<String> assignmentRowKey(String id) =>
      ValueKey<String>('employee-detail-assignment-$id');
  static ValueKey<String> currentAssignmentKey(String id) =>
      ValueKey<String>('employee-detail-assignment-current-$id');
  static ValueKey<String> skillChipKey(String skillId) => ValueKey<String>('employee-detail-skill-$skillId');
  static ValueKey<String> lapsedSkillChipKey(String skillId) =>
      ValueKey<String>('employee-detail-skill-lapsed-$skillId');
  static const ValueKey<String> recordSkillKey = ValueKey<String>('employee-detail-record-skill');
  static ValueKey<String> reassessSkillKey(String skillId) =>
      ValueKey<String>('employee-detail-reassess-skill-$skillId');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<EmployeeDetailBloc>().state;

    return Scaffold(
      body: switch (state) {
        // The shared loading vocabulary (#103): a detail record's own ghost —
        // its summary card, then its field rows — rather than a spinner, the
        // same `SkeletonDetail` the Maintenance and Quality detail pages show
        // (`design-language.md`:537).
        EmployeeDetailLoading() => const SkeletonDetail(maxWidth: EmployeeDetailScreen.maxWidth),
        EmployeeDetailUnavailable(message: final message) => PlatformFailureState(
            key: failedKey,
            title: l10n.employeeDetailThisRecordCouldNotBeRead,
            message: message,
            retryKey: retryKey,
            onRetry: () => context
                .read<EmployeeDetailBloc>()
                .add(EmployeeDetailRequested(employeeId: employeeId)),
          ),
        EmployeeDetailLoaded() => _Detail(state: state, isAdmin: isAdmin, canAssign: canAssign),
      },
    );
  }
}

/// The Org Unit this Employee currently sits in, read off the Assignments the
/// wire already sent — the current one is the only place that name exists on
/// this record (`EmployeeDetail` carries no `orgUnitName` of its own). `—` when
/// there is no current Assignment at all, never a blank (§13).
String _currentOrgUnit(EmployeeDetail employee) {
  for (final assignment in employee.assignments) {
    if (assignment.isCurrent) return assignment.orgUnitName;
  }
  return '—';
}

class _Detail extends StatelessWidget {
  const _Detail({required this.state, required this.isAdmin, required this.canAssign});

  final EmployeeDetailLoaded state;
  final bool isAdmin;
  final bool canAssign;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final theme = Theme.of(context);
    final employee = state.employee;

    return Center(
      child: AppPageFrame(
        maxWidth: EmployeeDetailScreen.maxWidth,
        // The box is the page's, before its `Spacing.lg` inset: at a 1280px
        // window that is 1020, over [AppBreakpoints.detailTwoColumn]'s 1000, so
        // the two sections sit side by side; they are themselves handed 988. It
        // is the box, never the window, and it is compared at the reader's text
        // scale, so twice the text puts the page back to one column (§10).
        child: LayoutBuilder(
          builder: (context, box) {
            final wide =
                box.maxWidth >= AppBreakpoints.effective(context, AppBreakpoints.detailTwoColumn);
            return ListView(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xl),
              children: [
            if (state.notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Container(
                  key: EmployeeDetailScreen.noticeKey,
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
                          noticeText(l10n, state.notice!),
                          style: AppTypography.dense(context)
                              ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _SummaryCard(state: state, isAdmin: isAdmin, canAssign: canAssign),
            const SizedBox(height: Spacing.md),
            // Two sections side by side when the page's box reaches 1000, one
            // above the other when it does not (`AppSectionGrid`'s own rule,
            // made here on the page's box rather than on the sections' inset
            // box — the same shape #390's detail pages use).
            _SectionPair(
              wide: wide,
              first: AppDetailSection(
                  title: l10n.employeeDetailAssignmentHistory,
                  children: [
                    if (employee.assignments.isEmpty)
                      Text(
                        l10n.employeeDetailNoAssignmentHasBeenRecorded,
                        key: EmployeeDetailScreen.noAssignmentsKey,
                        style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                      )
                    else
                      for (final assignment in employee.assignments)
                        _AssignmentRow(assignment: assignment),
                  ],
                ),
              second: AppDetailSection(
                  title: l10n.navSkills,
                  trailing: isAdmin
                      // Administrator only (issue #89) — `PUT .../skills/:skillId`
                      // sits behind `requireAdmin`, not the destination-scoped
                      // write `canAssign` gates the "Assign" action with
                      // (skill-routes.js's own header, ADR-0010).
                      ? OutlinedButton(
                          key: EmployeeDetailScreen.recordSkillKey,
                          onPressed: state.isMutating
                              ? null
                              : () => EmployeeSkillFormDialog.open(
                                    context,
                                    employee: employee,
                                    skills: state.skills,
                                  ),
                          child: Text(l10n.employeeDetailRecordSkill),
                        )
                      : null,
                  children: [
                    if (employee.qualifications.isEmpty)
                      Text(
                        l10n.employeeDetailNoQualificationsRecorded,
                        key: EmployeeDetailScreen.noSkillsKey,
                        style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                      )
                    else
                      Wrap(
                        spacing: Spacing.xs,
                        runSpacing: Spacing.xs,
                        children: [
                          for (final skill in employee.qualifications)
                            _SkillChip(
                              skill: skill,
                              isAdmin: isAdmin,
                              employee: employee,
                              catalogue: state.skills,
                            ),
                        ],
                      ),
                  ],
                ),
            ),
          ],
            );
          },
        ),
      ),
    );
  }
}

/// Two sections side by side when [wide], one above the other when not — at
/// equal heights in the wide case, so the pair reads as one row rather than as
/// two cards of different lengths.
class _SectionPair extends StatelessWidget {
  const _SectionPair({required this.wide, required this.first, required this.second});

  final bool wide;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: Spacing.md), second],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: Spacing.md),
          Expanded(child: second),
        ],
      ),
    );
  }
}

/// The record's identifying facts, one card: who this is, the number and job
/// role the plant knows them by, the Org Unit they sit in, whether they still
/// work here — and, at its foot, every action that writes to the record, so
/// nothing that changes the record is further from it than the card that names
/// it.
///
/// The facts are a grid of two from [AppBreakpoints.formTwoColumn] (900) of box:
/// below that (a 900 window hands this page 608) they stack one per line, which
/// is also what twice the reader's text does to them.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state, required this.isAdmin, required this.canAssign});

  final EmployeeDetailLoaded state;
  final bool isAdmin;
  final bool canAssign;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    final theme = Theme.of(context);
    final employee = state.employee;

    final facts = <Widget>[
      _Fact(label: l10n.commonEmployeeNumber, value: employee.employeeNo),
      _Fact(label: l10n.commonJobRole, value: employee.jobRoleName ?? 'No job role'),
      _Fact(label: l10n.commonOrgUnit, value: _currentOrgUnit(employee)),
      _Fact(label: l10n.commonEmployment, value: employmentTypeLabel(l10n, employee.employmentType)),
      _Fact(
        label: l10n.employeeDetailHired,
        value: employee.hiredOn == null ? '—' : formatWireDate(employee.hiredOn),
      ),
      _Fact(label: l10n.employeeDetailWorkEmail, value: employee.workEmail ?? '—'),
      if (employee.terminatedOn != null)
        _Fact(label: l10n.commonDeparted, value: formatWireDate(employee.terminatedOn)),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Initials(displayName: employee.displayName),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The page's own title, and the only one: at 18 against
                      // this page's 14px body it is 1.29×, inside #367's
                      // ceiling.
                      Text(
                        employee.displayName,
                        style: theme.textTheme.headlineSmall?.copyWith(color: palette.textPrimary),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        employee.jobRoleName == null
                            ? employee.employeeNo
                            : '${employee.employeeNo} · ${employee.jobRoleName}',
                        style: AppTypography.dense(context)?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                if (!employee.isActive)
                  StatusChip(
                    key: EmployeeDetailScreen.departedKey,
                    label: l10n.commonDeparted,
                    tone: StatusTone.neutral,
                  )
                else
                  StatusChip(label: l10n.commonActive, tone: StatusTone.success),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            LayoutBuilder(
              builder: (context, box) {
                final twoColumns = box.maxWidth >=
                    AppBreakpoints.effective(context, AppBreakpoints.formTwoColumn);
                if (!twoColumns) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < facts.length; index++) ...[
                        if (index > 0) const SizedBox(height: Spacing.sm),
                        facts[index],
                      ],
                    ],
                  );
                }
                final rows = <Widget>[];
                for (var index = 0; index < facts.length; index += 2) {
                  rows.add(
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: facts[index]),
                          const SizedBox(width: Spacing.lg),
                          Expanded(
                            child: index + 1 < facts.length ? facts[index + 1] : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < rows.length; index++) ...[
                      if (index > 0) const SizedBox(height: Spacing.sm),
                      rows[index],
                    ],
                  ],
                );
              },
            ),
            _Actions(state: state, isAdmin: isAdmin, canAssign: canAssign, employee: employee),
          ],
        ),
      ),
    );
  }
}

/// One labelled fact: the label above the value, both on the palette's own
/// tones. The label is `labelMedium` (w600 by the theme's own role) and the
/// value is `dense`, so a reader scans the labels down one edge and the values
/// down the next.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: palette.textMuted),
        ),
        const SizedBox(height: Spacing.xxs),
        Text(value, style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary)),
      ],
    );
  }
}

/// The initials block, the same one the Directory draws, fitted rather than
/// scaled so twice the reader's text shrinks it inside its circle.
class _Initials extends StatelessWidget {
  const _Initials({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = displayName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? '·'
        : words.length == 1
            ? words.first.characters.first.toUpperCase()
            : '${words.first.characters.first.toUpperCase()}'
                '${words.last.characters.first.toUpperCase()}';
    return CircleAvatar(
      radius: 20,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xs),
          child: Text(
            initials,
            style: AppTypography.dense(context)?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Every action that writes to the record, at the summary card's foot. Each one
/// keeps the enable condition it has always had: hidden rather than
/// shown-and-refused, which is the rule `canPlaceAnAsset` already follows.
/// Wrapped, so a narrow card flows them onto further lines instead of dropping
/// or clipping any of them.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.isAdmin,
    required this.canAssign,
    required this.employee,
  });

  final EmployeeDetailLoaded state;
  final bool isAdmin;
  final bool canAssign;
  final EmployeeDetail employee;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!(isAdmin || (canAssign && employee.isActive))) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.lg),
      child: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          if (isAdmin) ...[
            OutlinedButton(
              key: EmployeeDetailScreen.correctKey,
              onPressed: state.isMutating
                  ? null
                  : () => EmployeeCorrectionDialog.open(context, employee),
              child: Text(l10n.commonCorrectRecord),
            ),
            // A Departed Employee has no Signature to set (the server answers
            // 404), so the door is left off, as Assign is.
            if (employee.isActive)
              OutlinedButton(
                key: EmployeeDetailScreen.signatureKey,
                onPressed: state.isMutating
                    ? null
                    : () => EmployeeSignatureDialog.open(context, employee),
                child: Text(l10n.employeeDetailSignature),
              ),
            if (employee.isActive)
              OutlinedButton(
                key: EmployeeDetailScreen.departKey,
                onPressed: state.isMutating
                    ? null
                    : () => EmployeeDepartureDialog.open(context, employee),
                child: Text(l10n.commonRecordDeparture),
              )
            else
              OutlinedButton(
                key: EmployeeDetailScreen.reinstateKey,
                onPressed: state.isMutating
                    ? null
                    : () => context
                        .read<EmployeeDetailBloc>()
                        .add(const EmployeeDetailReinstatementConfirmed()),
                child: Text(l10n.commonReinstate),
              ),
          ],
          // A Departed Employee cannot be assigned (issue #88's own criterion) —
          // `createAssignment` (directory.js) itself refuses one with a 409, so
          // the affordance is left off rather than offered and then always
          // refused.
          if (canAssign && employee.isActive)
            OutlinedButton(
              key: EmployeeDetailScreen.assignKey,
              onPressed: state.isMutating
                  ? null
                  : () => EmployeeAssignmentDialog.open(context, employee),
              child: Text(l10n.commonAssign),
            ),
          // Worked hours (issue #263) is offered to every approved Account, the
          // same openness the directory detail route itself has (see
          // `worked_hours_screen.dart`'s own header): the summary is an open read
          // from the server, so no role gate belongs on the door that leads to
          // it.
          OutlinedButton(
            key: EmployeeDetailScreen.workedHoursKey,
            onPressed: () => context.go('${Routes.directory}/${employee.id}/work-hours'),
            child: Text(l10n.titleWorkedHours),
          ),
        ],
      ),
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({required this.assignment});

  final EmployeeAssignment assignment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = AppColors.of(context);
    return Padding(
      key: EmployeeDetailScreen.assignmentRowKey(assignment.id),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  assignment.jobRoleName == null
                      ? assignment.orgUnitName
                      : '${assignment.orgUnitName} · ${assignment.jobRoleName}',
                  style: AppTypography.dense(context)?.copyWith(color: palette.textPrimary),
                ),
                Text(
                  // One sentence for both cases, worded §13's way: `From 31 Jan
                  // 2026` while it holds, `31 Jan 2026 – 31 Dec 2026` once it is
                  // closed.
                  formatPeriod(from: assignment.effectiveFrom, to: assignment.effectiveTo),
                  style: AppTypography.floor(context)?.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          if (assignment.isCurrent) ...[
            const SizedBox(width: Spacing.sm),
            StatusChip(
              key: EmployeeDetailScreen.currentAssignmentKey(assignment.id),
              label: l10n.employeeDetailCurrent,
              tone: StatusTone.info,
            ),
          ],
        ],
      ),
    );
  }
}

/// A held skill, drawn exactly the way `WorkOrderAssignDialog` already draws
/// one (issue #62) — same chip shape, same "· Lapsed" suffix, same
/// `KeyedSubtree` wrapping only the lapsed case, so a test can assert
/// "distinguished from current" by key rather than by colour. A lapsed
/// qualification is shown, never left out (AC6): nothing here is evaluative, the
/// same discipline ADR-0018 records for that dialog.
///
/// Carries its own "Re-assess" action for an administrator (issue #89) — a
/// lapsed chip is exactly the case re-assessing exists for, so the action is
/// offered on every chip alike, not only a current one.
class _SkillChip extends StatelessWidget {
  const _SkillChip({
    required this.skill,
    required this.isAdmin,
    required this.employee,
    required this.catalogue,
  });

  final HeldSkill skill;
  final bool isAdmin;
  final EmployeeDetail employee;
  final List<Skill> catalogue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A lapsed qualification is stated, not judged (issues #168/#169, and the
    // same rule ADR-0018 records for the assign dialog: the tone and the
    // trailing "· Lapsed" state a fact about what somebody holds, never a claim
    // about what should happen to them). It used to wear the error container's
    // red, which *was* a judgement — an expiry shown as a failure — so it is the
    // neutral tone now, beside every other factual status in the Platform.
    final chip = skill.isLapsed
        ? StatusChip(
            key: EmployeeDetailScreen.skillChipKey(skill.skillId),
            label: l10n.employeeDetailLapsed(skill.name),
            tone: StatusTone.neutral,
          )
        : Chip(
            key: EmployeeDetailScreen.skillChipKey(skill.skillId),
            label: Text(skill.name),
            visualDensity: VisualDensity.compact,
          );
    final keyedChip = skill.isLapsed
        ? KeyedSubtree(key: EmployeeDetailScreen.lapsedSkillChipKey(skill.skillId), child: chip)
        : chip;
    if (!isAdmin) return keyedChip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        keyedChip,
        IconButton(
          key: EmployeeDetailScreen.reassessSkillKey(skill.skillId),
          icon: const Icon(Icons.edit_outlined, size: 16),
          tooltip: l10n.employeeDetailReAssess,
          visualDensity: VisualDensity.compact,
          onPressed: () => EmployeeSkillFormDialog.open(
            context,
            employee: employee,
            skills: catalogue,
            existing: skill,
          ),
        ),
      ],
    );
  }
}
