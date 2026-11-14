/// Every word the Platform prints for a **code**, in the language the reader
/// chose (ADR-0062).
///
/// **Why this file exists.** A status, a type, a severity and a role arrive
/// from the server as a stable wire code (`in_progress`, `near_miss`,
/// `return_to_supplier`), and every one of them is printed on a register, in a
/// chip, or in a dropdown. Until this file existed each of those words lived as
/// an English string beside its code — a `const Map`, an enum's own `label`
/// field, or a `String get statusLabel` on the model — so a Screen could render
/// a Vietnamese page with an English chip on it. The models keep the **codes**
/// and the **tones** (neither is language) and this file holds the words.
///
/// **The mechanism, and why there is only one.** A lookup function takes the
/// catalogue and the code, and falls back to the raw code for a value it has
/// not been taught:
///
/// ```dart
/// String workOrderStatusLabel(AppLocalizations l10n, String status) => ...
/// ```
///
/// It is the same shape `destination_labels.dart` already uses for the sidebar
/// (a stable code → a catalogue word, falling back to the code itself), so the
/// tree asks one question one way. The alternative — a field on the model —
/// cannot work at all: a model is built from JSON without a `BuildContext`, and
/// a Bloc has no `BuildContext` either (which is why a Bloc's own copy travels
/// as a code too, see `notices.dart`).
///
/// The cost of that choice is that **every call site passes `l10n`**, which this
/// file softens with extensions (`workOrder.statusLabel(l10n)`), and that a
/// column sized from a set of labels has to resolve them through the same
/// function rather than reading a list of English words
/// ([workOrderKnownStatusLabels]).
///
/// A model file stays free of Flutter and of the catalogue: it imports nothing
/// from `lib/l10n` (this file imports it). Only this adapter knows both sides.
library;

import '../actions/action.dart';
import '../actions/capa.dart';
import '../maintenance/pm_schedule.dart';
import '../maintenance/request.dart';
import '../maintenance/work_order.dart';
import '../people/cost_rate.dart';
import '../people/leave_request.dart';
import '../people/training_record.dart';
import '../quality/nonconformance.dart';
import '../safety/body_part.dart';
import '../safety/safety_incident.dart';
import '../safety/safety_observation.dart';
import 'app_localizations.dart';

// ---------------------------------------------------------------------------
// Maintenance
// ---------------------------------------------------------------------------

/// What a Work order's stored status reads as.
String workOrderStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'draft' => l10n.workOrderStatusDraft,
      'approved' => l10n.workOrderStatusApproved,
      'scheduled' => l10n.workOrderStatusScheduled,
      'in_progress' => l10n.workOrderStatusInProgress,
      'on_hold' => l10n.workOrderStatusOnHold,
      'completed' => l10n.workOrderStatusCompleted,
      'closed' => l10n.workOrderStatusClosed,
      'cancelled' => l10n.workOrderStatusCancelled,
      _ => status,
    };

/// Every word [workOrderStatusLabel] can produce for a status this build knows
/// about — what a fixed column is sized against, in the reader's own language.
///
/// The raw-code fallback is deliberately not included: that string is
/// unbounded, and only known labels are worth sizing a fixed column against.
List<String> workOrderKnownStatusLabels(AppLocalizations l10n) => [
      for (final status in const [
        'draft',
        'approved',
        'scheduled',
        'in_progress',
        'on_hold',
        'completed',
        'closed',
        'cancelled',
      ])
        workOrderStatusLabel(l10n, status),
    ];

/// What a step inside a Work order reads as.
String workOrderTaskStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'pending' => l10n.workOrderTaskStatusPending,
      'done' => l10n.workOrderTaskStatusDone,
      'skipped' => l10n.workOrderTaskStatusSkipped,
      'failed' => l10n.workOrderTaskStatusFailed,
      _ => status,
    };

/// What a Work order's kind of work reads as.
String workOrderWorkTypeLabel(AppLocalizations l10n, String workType) => switch (workType) {
      'corrective' => l10n.workOrderWorkTypeCorrective,
      'preventive' => l10n.workOrderWorkTypePreventive,
      'predictive' => l10n.workOrderWorkTypePredictive,
      'inspection' => l10n.workOrderWorkTypeInspection,
      'improvement' => l10n.workOrderWorkTypeImprovement,
      'calibration' => l10n.workOrderWorkTypeCalibration,
      _ => workType,
    };

/// How a fitted part reached the job, in words.
String partSourceLabel(AppLocalizations l10n, String source) => switch (source) {
      'stores' => l10n.partSourceStores,
      'purchased' => l10n.partSourcePurchased,
      'refurbished' => l10n.partSourceRefurbished,
      'cannibalised' => l10n.partSourceCannibalised,
      _ => source,
    };

/// The urgency a maintenance Request's reporter chose, in words.
String requestUrgencyLabel(AppLocalizations l10n, String urgency) => switch (urgency) {
      'low' => l10n.requestUrgencyLow,
      'normal' => l10n.requestUrgencyNormal,
      'high' => l10n.requestUrgencyHigh,
      'immediate' => l10n.requestUrgencyImmediate,
      _ => urgency,
    };

/// What a maintenance Request's stored status reads as.
String requestStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'new' => l10n.requestStatusNew,
      'triaged' => l10n.requestStatusTriaged,
      'accepted' => l10n.requestStatusAccepted,
      'rejected' => l10n.requestStatusRejected,
      'duplicate' => l10n.requestStatusDuplicate,
      _ => status,
    };

/// Every word [requestStatusLabel] can produce for a status this build knows
/// about — what the triage queue's Status column is sized against.
List<String> requestKnownStatusLabels(AppLocalizations l10n) => [
      for (final status in const ['new', 'triaged', 'accepted', 'rejected', 'duplicate'])
        requestStatusLabel(l10n, status),
    ];

/// Every word [requestUrgencyLabel] can produce, in the order the form offers
/// them — what the queue's Urgency column is sized against.
List<String> requestKnownUrgencyLabels(AppLocalizations l10n) => [
      for (final urgency in const ['low', 'normal', 'high', 'immediate'])
        requestUrgencyLabel(l10n, urgency),
    ];

/// What a booked labour line's activity reads as.
String labourActivityLabel(AppLocalizations l10n, String activity) => switch (activity) {
      'work' => l10n.labourActivityWork,
      'travel' => l10n.labourActivityTravel,
      'waiting' => l10n.labourActivityWaiting,
      'diagnosis' => l10n.labourActivityDiagnosis,
      'documentation' => l10n.labourActivityDocumentation,
      _ => activity,
    };

/// What a meter's type reads as.
String meterTypeLabel(AppLocalizations l10n, String meterType) => switch (meterType) {
      'cumulative' => l10n.meterTypeCumulative,
      'gauge' => l10n.meterTypeGauge,
      _ => meterType,
    };

/// The help text under a meter's type.
String meterTypeExplanation(AppLocalizations l10n, String meterType) => switch (meterType) {
      'cumulative' => l10n.meterTypeCumulativeExplanation,
      'gauge' => l10n.meterTypeGaugeExplanation,
      _ => '',
    };

/// What a PM schedule's anchor reads as.
String pmScheduleAnchorLabel(AppLocalizations l10n, String anchor) => switch (anchor) {
      'due' => l10n.pmAnchorDueDate,
      'completed' => l10n.pmAnchorCompletion,
      _ => anchor,
    };

/// The help text under a PM schedule's anchor.
String pmScheduleAnchorExplanation(AppLocalizations l10n, String anchor) => switch (anchor) {
      'due' => l10n.pmAnchorDueDateExplanation,
      'completed' => l10n.pmAnchorCompletionExplanation,
      _ => '',
    };

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// What an Action's stored status reads as.
String actionStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'open' => l10n.actionStatusOpen,
      'in_progress' => l10n.actionStatusInProgress,
      'blocked' => l10n.actionStatusBlocked,
      'done' => l10n.actionStatusDone,
      'cancelled' => l10n.actionStatusCancelled,
      _ => status,
    };

/// What an Action is to a problem, in words.
String actionTypeLabel(AppLocalizations l10n, String actionType) => switch (actionType) {
      'concern' => l10n.actionTypeConcern,
      'containment' => l10n.actionTypeContainment,
      'countermeasure' => l10n.actionTypeCountermeasure,
      'preventive' => l10n.actionTypePreventive,
      'improvement' => l10n.actionTypeImprovement,
      'routine' => l10n.actionTypeRoutine,
      _ => actionType,
    };

/// What one turn of the PDCA cycle reads as.
String actionPhaseLabel(AppLocalizations l10n, String phase) => switch (phase) {
      'plan' => l10n.actionPhasePlan,
      'do' => l10n.actionPhaseDo,
      'check' => l10n.actionPhaseCheck,
      'act' => l10n.actionPhaseAct,
      _ => phase,
    };

/// What a Check's verdict reads as, or null for a phase that recorded none.
String? actionCheckOutcomeLabel(AppLocalizations l10n, String? outcome) => switch (outcome) {
      null => null,
      'effective' => l10n.actionCheckOutcomeHeld,
      'not_effective' => l10n.actionCheckOutcomeDidNotHold,
      _ => outcome,
    };

/// What the five Action priorities read as — 1 is worst.
String actionPriorityLabel(AppLocalizations l10n, int priority) => switch (priority) {
      1 => l10n.actionPriorityWorst,
      2 => l10n.actionPriority2,
      3 => l10n.actionPriorityNormal,
      4 => l10n.actionPriority4,
      5 => l10n.actionPriorityLeast,
      _ => 'P$priority',
    };

/// The five priorities as (code, word) pairs, in the order the raise form
/// offers them — what a dropdown or a filter iterates.
List<(int, String)> actionPriorityChoices(AppLocalizations l10n) =>
    [for (final priority in actionPriorities) (priority, actionPriorityLabel(l10n, priority))];

/// An Action's five states as (code, word) pairs, in the order the register
/// reads them — what a status filter iterates.
List<(String, String)> actionStatusChoices(AppLocalizations l10n) => [
      for (final status in const ['open', 'in_progress', 'blocked', 'done', 'cancelled'])
        (status, actionStatusLabel(l10n, status)),
    ];

/// Every kind of Action as (code, word) pairs — what a kind filter iterates.
List<(String, String)> actionTypeChoices(AppLocalizations l10n) => [
      for (final type in ActionType.values) (type.wire, actionTypeLabel(l10n, type.wire)),
    ];

/// A Check's two verdicts as (code, word) pairs, in the order the dialog
/// offers them.
List<(String, String)> actionCheckOutcomeChoices(AppLocalizations l10n) => [
      for (final outcome in const ['effective', 'not_effective'])
        (outcome, actionCheckOutcomeLabel(l10n, outcome)!),
    ];

/// What a CAPA's stored status reads as.
String capaStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'open' => l10n.capaStatusOpen,
      'containment' => l10n.capaStatusContainment,
      'root_cause' => l10n.capaStatusRootCause,
      'actions' => l10n.capaStatusActions,
      'verifying' => l10n.capaStatusVerifying,
      'closed' => l10n.capaStatusClosed,
      'cancelled' => l10n.capaStatusCancelled,
      _ => status,
    };

/// A CAPA's seven states as (code, word) pairs, in the order the register
/// reads them — what a status filter iterates.
List<(String, String)> capaStatusChoices(AppLocalizations l10n) => [
      for (final status in const [
        'open',
        'containment',
        'root_cause',
        'actions',
        'verifying',
        'closed',
        'cancelled',
      ])
        (status, capaStatusLabel(l10n, status)),
    ];

/// The method a CAPA was opened by, in words.
String capaMethodLabel(AppLocalizations l10n, String method) => switch (method) {
      '8d' => l10n.capaMethod8d,
      '5why' => l10n.capaMethodFiveWhy,
      'a3' => l10n.capaMethodA3,
      'simple' => l10n.capaMethodSimple,
      _ => method,
    };

/// One 5 Why chain, named by the question it answers.
String capaChainLabel(AppLocalizations l10n, String chain) => switch (chain) {
      'occurrence' => l10n.capaChainOccurrence,
      'escape' => l10n.capaChainEscape,
      _ => chain,
    };

/// One of the 6M bones a candidate cause hangs from.
String capaCauseCategoryLabel(AppLocalizations l10n, String category) => switch (category) {
      'man' => l10n.capaCauseCategoryMan,
      'machine' => l10n.capaCauseCategoryMachine,
      'method' => l10n.capaCauseCategoryMethod,
      'material' => l10n.capaCauseCategoryMaterial,
      'measurement' => l10n.capaCauseCategoryMeasurement,
      'environment' => l10n.capaCauseCategoryEnvironment,
      _ => category,
    };

/// A candidate cause's verdict, in words.
String capaCauseVerdictLabel(AppLocalizations l10n, String verdict) => switch (verdict) {
      'candidate' => l10n.capaCauseVerdictCandidate,
      'confirmed' => l10n.capaCauseVerdictConfirmed,
      'ruled_out' => l10n.capaCauseVerdictRuledOut,
      _ => verdict,
    };

/// An effectiveness check's verdict, in words.
String capaEffectivenessOutcomeLabel(AppLocalizations l10n, String outcome) =>
    switch (outcome) {
      'effective' => l10n.capaEffectivenessHeld,
      'not_effective' => l10n.capaEffectivenessDidNotHold,
      _ => outcome,
    };

// ---------------------------------------------------------------------------
// Safety
// ---------------------------------------------------------------------------

/// What a Safety incident's stored status reads as.
String safetyIncidentStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'open' => l10n.safetyIncidentStatusOpen,
      'investigating' => l10n.safetyIncidentStatusInvestigating,
      'actions_pending' => l10n.safetyIncidentStatusActionsPending,
      'closed' => l10n.safetyIncidentStatusClosed,
      _ => status,
    };

/// What kind of Safety incident this was, in words.
String safetyIncidentTypeLabel(AppLocalizations l10n, String incidentType) =>
    switch (incidentType) {
      'injury' => l10n.safetyIncidentTypeInjury,
      'near_miss' => l10n.safetyIncidentTypeNearMiss,
      'property_damage' => l10n.safetyIncidentTypePropertyDamage,
      'environmental' => l10n.safetyIncidentTypeEnvironmental,
      'fire' => l10n.safetyIncidentTypeFire,
      'ergonomic' => l10n.safetyIncidentTypeErgonomic,
      'security' => l10n.safetyIncidentTypeSecurity,
      _ => incidentType,
    };

/// The injury ladder: how bad it was.
String safetySeverityLabel(AppLocalizations l10n, String severity) => switch (severity) {
      'near_miss' => l10n.safetySeverityNoInjury,
      'first_aid' => l10n.safetySeverityFirstAid,
      'medical_treatment' => l10n.safetySeverityMedicalTreatment,
      'restricted_work' => l10n.safetySeverityRestrictedWork,
      'lost_time' => l10n.safetySeverityLostTime,
      'fatality' => l10n.safetySeverityFatality,
      _ => severity,
    };

/// What kind of observation was recorded, in words.
String observationTypeLabel(AppLocalizations l10n, String observationType) =>
    switch (observationType) {
      'safe_act' => l10n.safetyObservationTypeSafeAct,
      'unsafe_act' => l10n.safetyObservationTypeUnsafeAct,
      'unsafe_condition' => l10n.safetyObservationTypeUnsafeCondition,
      _ => observationType,
    };

/// What the observation was about, in words.
String observationCategoryLabel(AppLocalizations l10n, String category) => switch (category) {
      'ppe' => l10n.safetyObservationCategoryPpe,
      'machine_guarding' => l10n.safetyObservationCategoryMachineGuarding,
      'housekeeping' => l10n.safetyObservationCategoryHousekeeping,
      'ergonomics' => l10n.safetyObservationCategoryErgonomics,
      'chemical' => l10n.safetyObservationCategoryChemical,
      'working_at_height' => l10n.safetyObservationCategoryWorkingAtHeight,
      'traffic' => l10n.safetyObservationCategoryTraffic,
      'energy_isolation' => l10n.safetyObservationCategoryEnergyIsolation,
      'procedure' => l10n.safetyObservationCategoryProcedure,
      'other' => l10n.safetyObservationCategoryOther,
      _ => category,
    };

/// How bad an observation could have been, in words.
String severityPotentialLabel(AppLocalizations l10n, String potential) => switch (potential) {
      'low' => l10n.safetyPotentialLow,
      'medium' => l10n.safetyPotentialMedium,
      'high' => l10n.safetyPotentialHigh,
      'fatal' => l10n.safetyPotentialFatal,
      _ => potential,
    };

/// The region of the body a Body part is filed under, in words.
String bodyPartRegionLabel(AppLocalizations l10n, String region) => switch (region) {
      'head' => l10n.bodyPartRegionHead,
      'trunk' => l10n.bodyPartRegionTrunk,
      'upper_limb' => l10n.bodyPartRegionUpperLimb,
      'lower_limb' => l10n.bodyPartRegionLowerLimb,
      'multiple' => l10n.bodyPartRegionMultiple,
      'other' => l10n.bodyPartRegionOther,
      _ => region,
    };

// ---------------------------------------------------------------------------
// People
// ---------------------------------------------------------------------------

/// An Account's role, in words.
String admissionRoleLabel(AppLocalizations l10n, String role) => switch (role) {
      'operator' => l10n.roleOperator,
      'supervisor' => l10n.roleSupervisor,
      'engineer' => l10n.roleEngineer,
      'manager' => l10n.roleManager,
      'admin' => l10n.roleAdministrator,
      _ => role,
    };

/// What an Account's role means, in one line — what the admission picker says
/// under the role's own name.
String admissionRoleDescription(AppLocalizations l10n, String role) => switch (role) {
      'operator' => l10n.roleOperatorDescription,
      'supervisor' => l10n.roleSupervisorDescription,
      'engineer' => l10n.roleEngineerDescription,
      'manager' => l10n.roleManagerDescription,
      'admin' => l10n.roleAdministratorDescription,
      _ => '',
    };

/// An Employee's employment type, in words.
String employmentTypeLabel(AppLocalizations l10n, String employmentType) =>
    switch (employmentType) {
      'permanent' => l10n.employmentTypePermanent,
      'temporary' => l10n.employmentTypeTemporary,
      'agency' => l10n.employmentTypeAgency,
      'contractor' => l10n.employmentTypeContractor,
      'apprentice' => l10n.employmentTypeApprentice,
      '' => '',
      _ => employmentType,
    };

/// How a Trainee was evaluated, in words.
String trainingEvaluationLabel(AppLocalizations l10n, String evaluation) =>
    switch (evaluation) {
      'paper' => l10n.trainingEvaluationPaper,
      'job_training' => l10n.trainingEvaluationJobTraining,
      _ => evaluation,
    };

/// What a Training record's stored status reads as.
String trainingStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'draft' => l10n.trainingStatusDraft,
      'sent' => l10n.trainingStatusSent,
      _ => status,
    };

/// What one attendance row's status reads as.
String attendanceStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'present' => l10n.attendanceStatusPresent,
      'late' => l10n.attendanceStatusLate,
      'absent_planned' => l10n.attendanceStatusAbsentPlanned,
      'absent_unplanned' => l10n.attendanceStatusAbsentUnplanned,
      'training' => l10n.attendanceStatusTraining,
      'not_scheduled' => l10n.attendanceStatusNotScheduled,
      _ => status,
    };

/// What an attendance sheet's own state reads as.
String attendanceSheetStateLabel(AppLocalizations l10n, String sheetState) =>
    switch (sheetState) {
      'missing' => l10n.attendanceSheetStateMissing,
      'unconfirmed' => l10n.attendanceSheetStateUnconfirmed,
      _ => sheetState,
    };

/// What a leave request's stored status reads as.
String leaveRequestStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'pending' => l10n.leaveRequestStatusPending,
      'approved' => l10n.leaveRequestStatusApproved,
      'rejected' => l10n.leaveRequestStatusRejected,
      'cancelled' => l10n.leaveRequestStatusCancelled,
      _ => status,
    };

/// What a cost rate applies to, in words.
String costRateScopeTypeLabel(AppLocalizations l10n, String scopeType) => switch (scopeType) {
      'site' => l10n.costRateScopeSite,
      'org_unit' => l10n.costRateScopeOrgUnit,
      'asset' => l10n.costRateScopeAsset,
      'cost_center' => l10n.costRateScopeCostCentre,
      _ => scopeType,
    };

/// What a cost rate's kind is, in words.
String costRateTypeLabel(AppLocalizations l10n, String rateType) => switch (rateType) {
      'labor_per_hour' => l10n.costRateTypeLabourPerHour,
      'overtime_premium_multiplier' => l10n.costRateTypeOvertimePremium,
      'machine_downtime_per_hour' => l10n.costRateTypeMachineDowntime,
      'overhead_per_hour' => l10n.costRateTypeOverhead,
      'rework_labor_per_hour' => l10n.costRateTypeReworkLabour,
      _ => rateType,
    };

// ---------------------------------------------------------------------------
// Quality
// ---------------------------------------------------------------------------

/// What a Non-conformance's stored status reads as.
String nonconformanceStatusLabel(AppLocalizations l10n, String status) => switch (status) {
      'open' => l10n.nonconformanceStatusOpen,
      'contained' => l10n.nonconformanceStatusContained,
      'dispositioned' => l10n.nonconformanceStatusDispositioned,
      'closed' => l10n.nonconformanceStatusClosed,
      'cancelled' => l10n.nonconformanceStatusCancelled,
      _ => status,
    };

/// What a Disposition decided the product gets, in words.
String dispositionTypeLabel(AppLocalizations l10n, String type, {bool isConcession = false}) {
  if (isConcession) return l10n.dispositionConcession;
  return switch (type) {
    'scrap' => l10n.dispositionScrap,
    'rework' => l10n.dispositionRework,
    'return_to_supplier' => l10n.dispositionReturnToSupplier,
    'use_as_is' => l10n.dispositionUseAsIs,
    _ => type,
  };
}

/// What a Defect code's default severity reads as.
String defectSeverityLabel(AppLocalizations l10n, String severity) => switch (severity) {
      'minor' => l10n.defectSeverityMinor,
      'major' => l10n.defectSeverityMajor,
      'critical' => l10n.defectSeverityCritical,
      _ => severity,
    };

/// What a Non-conformance correction is, in words.
String correctionKindLabel(AppLocalizations l10n, String kind) => switch (kind) {
      'severity_lowered' => l10n.severityChangeLowered,
      'reopened' => l10n.correctionKindReopened,
      'cancelled' => l10n.correctionKindCancelled,
      _ => kind,
    };

/// What one correction of a Non-conformance changed, as a history row reads it.
String correctionSummary(AppLocalizations l10n, Correction correction) {
  final by = correction.correctedByAccountDisplayName;
  final who = by ?? l10n.commonUnknown;
  return switch (correction.kind) {
    'severity_lowered' => l10n.correctionSummarySeverityLowered(
        defectSeverityLabel(l10n, correction.previousSeverity ?? ''),
        defectSeverityLabel(l10n, correction.newSeverity ?? ''),
      ),
    'reopened' =>
      '${l10n.correctionSummaryReopened(nonconformanceStatusLabel(l10n, correction.previousStatus ?? ''))} · $who',
    'cancelled' =>
      '${l10n.correctionSummaryCancelled(nonconformanceStatusLabel(l10n, correction.previousStatus ?? ''))} · $who',
    _ => correctionKindLabel(l10n, correction.kind),
  };
}

/// What one event of a Safety incident changed, as a history row reads it.
String incidentEventSummary(AppLocalizations l10n, SafetyIncidentEvent event) =>
    switch (event.kind) {
      'severity' => l10n.incidentEventSeverityChanged(
          safetySeverityLabel(l10n, event.previousValue),
          safetySeverityLabel(l10n, event.newValue),
        ),
      'status' => l10n.incidentEventStatusMoved(
          safetyIncidentStatusLabel(l10n, event.previousValue),
          safetyIncidentStatusLabel(l10n, event.newValue),
        ),
      'days' => l10n.incidentEventDaysRecorded(event.newValue),
      'closure' => l10n.incidentEventClosed,
      'classification' => l10n.incidentEventClassified,
      _ => '${event.previousValue} → ${event.newValue}',
    };

/// [name], or the catalogue's own word for "nobody was named".
String namedOrUnknown(AppLocalizations l10n, String? name) =>
    name == null || name.isEmpty ? l10n.commonUnknown : name;

/// What kind of thing a Non-conformance was found at.
String detectionPointLabel(AppLocalizations l10n, String point) => switch (point) {
      'incoming' => l10n.detectionPointIncoming,
      'in_process' => l10n.detectionPointInProcess,
      'final_inspection' => l10n.detectionPointFinalInspection,
      'audit' => l10n.detectionPointAudit,
      'customer' => l10n.detectionPointCustomer,
      _ => point,
    };

/// What a Non-conformance's own history calls a change it recorded.
String nonconformanceChangeLabel(AppLocalizations l10n, String changeType) =>
    switch (changeType) {
      'severity_lowered' => l10n.severityChangeLowered,
      _ => changeType,
    };

// ---------------------------------------------------------------------------
// Read the words off the record itself: `record.statusLabel(l10n)`, the same
// name the model used to carry, with the catalogue as the argument. The model
// keeps the codes and the tones; only the words live here.
// ---------------------------------------------------------------------------

extension WorkOrderWords on WorkOrder {
  /// What this Work order's stored status reads as, in [l10n]'s language.
  String statusLabel(AppLocalizations l10n) => workOrderStatusLabel(l10n, status);

  /// What this Work order's kind of work reads as.
  String workTypeLabel(AppLocalizations l10n) => workOrderWorkTypeLabel(l10n, workType);
}

extension WorkOrderTaskWords on WorkOrderTask {
  /// What this step's stored status reads as.
  String statusLabel(AppLocalizations l10n) => workOrderTaskStatusLabel(l10n, status);
}

extension WorkOrderLabourActivityWords on WorkOrderLabourActivity {
  /// What this booked line's activity reads as.
  String label(AppLocalizations l10n) => labourActivityLabel(l10n, activity);
}

extension WorkOrderPartLineWords on WorkOrderPartLine {
  /// How this fitted part reached the job, in words.
  String sourcedLabel(AppLocalizations l10n) => partSourceLabel(l10n, sourced);
}

extension RequestWords on Request {
  /// What this Request's stored status reads as.
  String statusLabel(AppLocalizations l10n) => requestStatusLabel(l10n, status);

  /// The urgency its reporter chose, in words.
  String urgencyLabel(AppLocalizations l10n) => requestUrgencyLabel(l10n, urgency);
}

extension PmScheduleWords on PmSchedule {
  /// What this schedule's anchor reads as.
  String anchorLabel(AppLocalizations l10n) => pmScheduleAnchorLabel(l10n, anchor);
}

extension ActionWords on Action {
  /// What this Action's stored status reads as.
  String statusLabel(AppLocalizations l10n) => actionStatusLabel(l10n, status);

  /// What this Action is to its problem, in words.
  String typeLabel(AppLocalizations l10n) => actionTypeLabel(l10n, actionType);

  /// What this Action's priority reads as.
  String priorityLabel(AppLocalizations l10n) => actionPriorityLabel(l10n, priority);
}

extension ActionPhaseWords on ActionPhase {
  /// What this turn of the cycle reads as.
  String phaseLabel(AppLocalizations l10n) => actionPhaseLabel(l10n, phase);

  /// What this Check's verdict reads as, or null when it recorded none.
  String? outcomeLabel(AppLocalizations l10n) => actionCheckOutcomeLabel(l10n, outcome);
}

extension CapaWords on Capa {
  /// What this CAPA's stored status reads as.
  String statusLabel(AppLocalizations l10n) => capaStatusLabel(l10n, status);

  /// The method this CAPA was opened by, in words.
  String methodLabel(AppLocalizations l10n) => capaMethodLabel(l10n, method);
}

extension CapaWhyWords on CapaWhy {
  /// Which chain this Why belongs to, named by the question it answers.
  String chainLabel(AppLocalizations l10n) => capaChainLabel(l10n, chain);
}

extension CapaCauseWords on CapaCause {
  /// Which 6M bone this cause hangs from.
  String categoryLabel(AppLocalizations l10n) => capaCauseCategoryLabel(l10n, category);

  /// This cause's verdict, in words.
  String verdictLabel(AppLocalizations l10n) => capaCauseVerdictLabel(l10n, verdict);
}

extension ActionParentWords on ActionParent {
  /// What this Concern's stored status reads as.
  String statusLabel(AppLocalizations l10n) => actionStatusLabel(l10n, status);

  /// What kind of Action this parent is, in words.
  String typeLabel(AppLocalizations l10n) => actionTypeLabel(l10n, actionType);
}

extension CapaLinkWords on CapaLink {
  /// What the linked CAPA's stored status reads as.
  String statusLabel(AppLocalizations l10n) => capaStatusLabel(l10n, status);
}

extension LinkedConcernWords on LinkedConcern {
  /// What the Concern's stored status reads as.
  String statusLabel(AppLocalizations l10n) => actionStatusLabel(l10n, status);

  /// What kind of Action the Concern is, in words.
  String typeLabel(AppLocalizations l10n) => actionTypeLabel(l10n, actionType);
}

extension SafetyIncidentWords on SafetyIncident {
  /// What this incident's stored status reads as.
  String statusLabel(AppLocalizations l10n) => safetyIncidentStatusLabel(l10n, status);

  /// What kind of incident this was, in words.
  String incidentTypeLabel(AppLocalizations l10n) => safetyIncidentTypeLabel(l10n, incidentType);

  /// How bad it was, on the injury ladder.
  String severityLabel(AppLocalizations l10n) => safetySeverityLabel(l10n, severityLevel);
}

extension SafetyIncidentConcernWords on SafetyIncidentConcern {
  /// What this Concern's stored status reads as — the action log's own words.
  String statusLabel(AppLocalizations l10n) => actionStatusLabel(l10n, status);

  /// What kind of Action this Concern is, in words.
  String typeLabel(AppLocalizations l10n) => actionTypeLabel(l10n, actionType);
}

extension SafetyObservationWords on SafetyObservation {
  /// What the observation was about, in words.
  String categoryLabel(AppLocalizations l10n) => observationCategoryLabel(l10n, category);
}

extension SafetyObservationActionWords on SafetyObservationAction {
  /// What this Action's stored status reads as.
  String statusLabel(AppLocalizations l10n) => actionStatusLabel(l10n, status);

  /// What kind of Action this is, in words.
  String typeLabel(AppLocalizations l10n) => actionTypeLabel(l10n, actionType);
}

extension BodyPartWords on BodyPart {
  /// The region this part is filed under, in words.
  String regionLabel(AppLocalizations l10n) => bodyPartRegionLabel(l10n, region);

  /// What a row and a chosen value both read as: the name, the code a person
  /// quotes, and the region it is filed under — the field that groups the
  /// catalogue and the only one this model has that an Injury type does not.
  String label(AppLocalizations l10n) => '$name · $code · ${regionLabel(l10n)}';
}

extension TrainingRecordWords on TrainingRecord {
  /// What this record's stored status reads as.
  String statusLabel(AppLocalizations l10n) => trainingStatusLabel(l10n, status);
}

extension LeaveRequestWords on LeaveRequest {
  /// What this request's stored status reads as.
  String statusLabel(AppLocalizations l10n) => leaveRequestStatusLabel(l10n, status);
}

extension DispositionWords on Disposition {
  /// What this Disposition decided the product gets, in words.
  String label(AppLocalizations l10n) =>
      dispositionTypeLabel(l10n, dispositionType, isConcession: isConcession);
}

extension CorrectionWords on Correction {
  /// What this correction is, in words.
  String label(AppLocalizations l10n) => correctionKindLabel(l10n, kind);

  /// What it changed, as a history row reads it.
  String summary(AppLocalizations l10n) => correctionSummary(l10n, this);
}

extension SafetyIncidentEventWords on SafetyIncidentEvent {
  /// What this event changed, as a history row reads it.
  String summary(AppLocalizations l10n) => incidentEventSummary(l10n, this);
}

extension CostRateWords on CostRate {
  /// The scope as a row reads it: the record's own name where it is still
  /// there, and the kind of thing it is.
  String scopeLabel(AppLocalizations l10n) =>
      '${scopeName ?? 'Scope $scopeId'} · ${costRateScopeTypeLabel(l10n, scopeType)}';
}

extension NonconformanceWords on Nonconformance {
  /// What this Non-conformance's stored status reads as.
  String statusLabel(AppLocalizations l10n) => nonconformanceStatusLabel(l10n, status);

  /// What its severity reads as.
  String severityLabel(AppLocalizations l10n) => defectSeverityLabel(l10n, severity);
}
