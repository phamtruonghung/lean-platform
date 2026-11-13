// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get shellBrand => 'Platform';

  @override
  String get shellSkipToContent => 'Skip to content';

  @override
  String get shellAccountMenu => 'Account menu';

  @override
  String get shellChangePassword => 'Change password';

  @override
  String get shellDarkPalette => 'Dark palette';

  @override
  String get shellLightPalette => 'Light palette';

  @override
  String get shellSignOut => 'Sign out';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsDescription =>
      'How the Platform looks, and the language it speaks.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageHelp =>
      'Applies across the whole Platform at once, and is remembered on this browser.';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageVietnamese => 'Vietnamese';

  @override
  String get groupPeople => 'People';

  @override
  String get groupMaintenance => 'Maintenance';

  @override
  String get groupQuality => 'Quality';

  @override
  String get groupActions => 'Actions';

  @override
  String get groupSafety => 'Safety';

  @override
  String get groupProduction => 'Production';

  @override
  String get groupInsights => 'Insights';

  @override
  String get groupAdministration => 'Administration';

  @override
  String get navHome => 'Home';

  @override
  String get navDirectory => 'Directory';

  @override
  String get navJobRoles => 'Job roles';

  @override
  String get navSkills => 'Skills';

  @override
  String get navOrgUnits => 'Org Units';

  @override
  String get navAttendance => 'Attendance';

  @override
  String get navTraining => 'Training';

  @override
  String get navMySignature => 'My signature';

  @override
  String get navLeaveRequests => 'Leave requests';

  @override
  String get navCostRates => 'Cost rates';

  @override
  String get navProductStandardCosts => 'Product standard costs';

  @override
  String get navAssets => 'Assets';

  @override
  String get navParts => 'Parts';

  @override
  String get navStores => 'Stores';

  @override
  String get navWorkOrders => 'Work orders';

  @override
  String get navMyRequests => 'My requests';

  @override
  String get navTriageQueue => 'Triage queue';

  @override
  String get navDowntime => 'Downtime';

  @override
  String get navPmSchedules => 'PM schedules';

  @override
  String get navMeters => 'Meters';

  @override
  String get navJobPlans => 'Job plans';

  @override
  String get navTierBoard => 'Tier board';

  @override
  String get navSkillCoverage => 'Skill coverage';

  @override
  String get navKpiCatalogue => 'KPI catalogue';

  @override
  String get navKpiReview => 'KPI review';

  @override
  String get navActionLog => 'Action log';

  @override
  String get navProducts => 'Products';

  @override
  String get navDefectCodes => 'Defect codes';

  @override
  String get navNonConformances => 'Non-conformances';

  @override
  String get navCapas => 'CAPAs';

  @override
  String get navCustomers => 'Customers';

  @override
  String get navCustomerComplaints => 'Customer complaints';

  @override
  String get navSlideShow => 'Slide show';

  @override
  String get navSuppliers => 'Suppliers';

  @override
  String get navSupplierNcrs => 'Supplier NCRs';

  @override
  String get navIncidents => 'Incidents';

  @override
  String get navObservations => 'Observations';

  @override
  String get navInjuryTypes => 'Injury types';

  @override
  String get navBodyParts => 'Body parts';

  @override
  String get navShiftHandovers => 'Shift handovers';

  @override
  String get navApprovals => 'Approvals';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navRoles => 'Roles';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSaving => 'Saving…';

  @override
  String get accountPasswordCurrent => 'Current password';

  @override
  String get accountPasswordNew => 'New password';

  @override
  String accountPasswordMinimum(int count) {
    return 'At least $count characters.';
  }

  @override
  String get accountPasswordCurrentRequired => 'Enter your current password.';

  @override
  String accountPasswordTooShort(int count) {
    return 'Use at least $count characters for the new password.';
  }

  @override
  String get accountPasswordChanged => 'Your password was changed.';

  @override
  String homeGreeting(String name) {
    return 'Welcome, $name';
  }

  @override
  String get homeNothingWaiting => 'Nothing is waiting on you.';

  @override
  String get homeActionsUnavailable => 'Your Actions are unavailable';

  @override
  String get homeAssignedToYou => 'Assigned to you';

  @override
  String get homeAssignedToYouCaption => 'Open Actions whose owner is you';

  @override
  String get homeAccountNotLinked =>
      'Your Account is not linked to an Employee record, so no Action can be assigned to you — link one under Accounts';

  @override
  String get homeTrainingUnavailable =>
      'Your Training to confirm is unavailable';

  @override
  String get trainingToConfirm => 'Training to confirm';

  @override
  String get homeTrainingToConfirmCaption =>
      'Training records sent to you that you have not answered';

  @override
  String get homeWorkOrdersUnavailable => 'Work orders are unavailable';

  @override
  String get homeOpenWorkOrders => 'Open work orders';

  @override
  String get homeOpenWorkOrdersCaption => 'Raised and not yet complete';

  @override
  String get homeAwaitingAssignment => 'Awaiting assignment';

  @override
  String get homeAwaitingAssignmentScopedCaption =>
      'On the Org Units granted to you, and everything beneath them';

  @override
  String get homeAwaitingAssignmentCaption =>
      'Open, with nobody holding them yet';

  @override
  String get homeApprovalsUnavailable => 'Approvals are unavailable';

  @override
  String get accountsAwaitingApproval => 'Accounts awaiting Approval';

  @override
  String get homeAccountsAwaitingApprovalCaption => 'Waiting to be admitted';

  @override
  String get commonSite => 'Site';

  @override
  String get commonSummary => 'Summary';

  @override
  String get commonAsset => 'Asset';

  @override
  String get commonOrgUnit => 'Org Unit';

  @override
  String get commonStatus => 'Status';

  @override
  String get commonAssignee => 'Assignee';

  @override
  String get commonActions => 'Actions';

  @override
  String get commonUnassigned => 'Unassigned';

  @override
  String get commonMoreActions => 'More actions';

  @override
  String workOrdersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Work orders',
      one: '1 Work order',
    );
    return '$_temp0';
  }

  @override
  String workOrdersCountNarrowed(String name) {
    return ', narrowed to $name';
  }

  @override
  String get workOrdersCountHistory => ', including completed and cancelled';

  @override
  String get workOrdersUnavailableTitle => 'The Work orders could not be read';

  @override
  String get workOrdersDescription =>
      'The work raised at this Site, which Asset it is against, and who has it.';

  @override
  String get workOrdersRaise => 'Raise a Work order';

  @override
  String get workOrdersNarrowToOrgUnit => 'Narrow to an Org Unit';

  @override
  String workOrdersNarrowedTo(String name) {
    return 'Narrowed to $name';
  }

  @override
  String get workOrdersShowWholeSite => 'Show the whole Site again';

  @override
  String get workOrdersShowHistory => 'Show completed and cancelled';

  @override
  String get workOrdersNarrowTitle => 'Narrow the list';

  @override
  String get workOrdersNarrowDescription =>
      'Choose the Org Unit to narrow the list to. Everything beneath it is included too.';

  @override
  String get workOrdersTruncated =>
      'There are more Work orders than this list shows. Narrow it by Org Unit, or turn history off, to see the rest.';

  @override
  String get workOrdersFilter => 'Filter Work orders';

  @override
  String get workOrdersFilterHelp => 'By summary, Work order number or Asset.';

  @override
  String get workOrdersNoMatch => 'No Work orders match';

  @override
  String workOrdersNoMatchMessage(String term) {
    return 'Work is open at this Site, but none of it matches “$term”. Try a different summary or Asset, or clear the filter.';
  }

  @override
  String get workOrdersStart => 'Start';

  @override
  String get workOrdersComplete => 'Complete';

  @override
  String get workOrdersNumberColumn => 'WO#';

  @override
  String get workOrdersAssign => 'Assign';

  @override
  String get workOrdersReassign => 'Reassign';

  @override
  String get workOrdersFilteredEmptyTitle => 'No work orders match';

  @override
  String workOrdersFilteredEmptyMessage(String name) {
    return 'There is work at this Site, but none of it is raised at $name or beneath it.';
  }

  @override
  String workOrdersFilteredEmptyMessageOpen(String name) {
    return 'There is work at this Site, but none of it is raised at $name or beneath it and still open.';
  }

  @override
  String get workOrdersThisOrgUnit => 'this Org Unit';

  @override
  String get workOrdersClearFilters => 'Clear filters';

  @override
  String get workOrdersNoneExistTitle => 'No work at this Site';

  @override
  String get workOrdersNoneOpenTitle => 'No open work at this Site';

  @override
  String get workOrdersNoneExistMessage =>
      'Nothing has been raised against the Org Units you can act in. Raise a Work order and it will show up right away.';

  @override
  String get commonWorkType => 'Work type';

  @override
  String get commonPriority => 'Priority';

  @override
  String commonHours(String hours) {
    return '$hours h';
  }

  @override
  String get commonNoCostRecorded => 'No cost recorded';

  @override
  String get workOrderUnavailableTitle => 'This Work order could not be read';

  @override
  String get workOrderBackToList => 'Back to Work orders';

  @override
  String get workOrderTitle => 'Work order';

  @override
  String get workOrderTasksDescription =>
      'The tasks copied from the Job plan that raised it.';

  @override
  String get workOrderBookLabour => 'Book labour';

  @override
  String get workOrderBookPart => 'Book a part';

  @override
  String get workOrderTasks => 'Tasks';

  @override
  String get workOrderNoTasks => 'No steps were copied onto this Work order.';

  @override
  String get workOrderCostSoFar => 'Cost so far';

  @override
  String get workOrderNoLabour => 'No labour has been booked.';

  @override
  String workOrderOvertime(String hours, String overtime) {
    return '$hours · $overtime overtime';
  }

  @override
  String get workOrderLabourNote =>
      'Booked labour is part of the plant labour cost already reported, not new money.';

  @override
  String workOrderOvertimeNote(String hours) {
    return '$hours of it is overtime.';
  }

  @override
  String get workOrderNoParts => 'No parts have been fitted.';

  @override
  String get workOrderPartsNote =>
      'Parts are new cost — the one maintenance component that adds.';

  @override
  String workOrderRequiresSkill(String name) {
    return 'Requires $name';
  }

  @override
  String get workOrderNoSkill => 'No skill required';

  @override
  String workOrderRecordsMeter(String name) {
    return 'Records $name';
  }

  @override
  String workOrderReading(String value) {
    return 'Reading $value';
  }

  @override
  String get workOrderRecordReading => 'Record a reading';

  @override
  String get requestsUnavailableTitle => 'The requests could not be read';

  @override
  String get requestsDescription =>
      'The Requests waiting for a decision at this Site. Accepting one raises a Work order for it.';

  @override
  String get requestsFilter => 'Filter requests';

  @override
  String get requestsFilterHelp => 'By description, Request number or Asset.';

  @override
  String get requestsNoMatch => 'No requests match';

  @override
  String requestsNoMatchMessage(String term) {
    return 'Requests are waiting at this Site, but none matches “$term”. Try a different description or Asset.';
  }

  @override
  String get requestsNumberColumn => 'Request';

  @override
  String get requestsRaisedBy => 'Raised by';

  @override
  String get requestsRaisedDate => 'Raised';

  @override
  String get requestsUrgency => 'Urgency';

  @override
  String get requestsProductionStopped => 'Production is stopped';

  @override
  String get requestsAccept => 'Accept';

  @override
  String get requestsDecline => 'Decline';

  @override
  String get requestsMarkDuplicate => 'Mark duplicate';

  @override
  String requestsRaisedByPerson(String name) {
    return 'Raised by $name';
  }

  @override
  String get requestsNoneExistTitle => 'Nothing is waiting';

  @override
  String get requestsNoneExistMessage =>
      'No Requests are waiting for a decision at this Site.';

  @override
  String get downtimeDescription =>
      'The machines not running at this Site, the reasons they stopped, and how long they have been down.';

  @override
  String get downtimeUnavailableTitle =>
      'The downtime events could not be read';

  @override
  String get downtimeReport => 'Report a breakdown';

  @override
  String get downtimeTruncated =>
      'There are more downtime events than this list shows.';

  @override
  String get downtimeFilter => 'Filter downtime';

  @override
  String get downtimeFilterHelp => 'By Asset, reason or description.';

  @override
  String get downtimeNoMatch => 'No downtime matches';

  @override
  String downtimeNoMatchMessage(String term) {
    return 'This Site has downtime recorded, but none matches “$term”. Try a different Asset, reason or description.';
  }

  @override
  String get downtimeStarted => 'Started';

  @override
  String get downtimeReason => 'Reason';

  @override
  String get downtimeReportedByColumn => 'Reported by';

  @override
  String get downtimeClose => 'Close';

  @override
  String get downtimeClassify => 'Classify';

  @override
  String downtimeStartedAt(String instant) {
    return 'Started $instant';
  }

  @override
  String downtimeReasonLine(String name) {
    return 'Reason: $name';
  }

  @override
  String downtimeReportedByPerson(String name) {
    return 'Reported by $name';
  }

  @override
  String get downtimeNoneExistTitle => 'Nothing is down';

  @override
  String get downtimeNoneExistMessage =>
      'No machine is recorded as down at this Site.';

  @override
  String get commonDetails => 'Details';

  @override
  String get commonDescription => 'Description';

  @override
  String get commonNow => 'now';

  @override
  String get metersDescription =>
      'The running counts a PM schedule can come due on, and the readings taken against them.';

  @override
  String get metersUnavailableTitle => 'The meters could not be read';

  @override
  String get metersDefine => 'Define a meter';

  @override
  String get metersFilter => 'Filter meters';

  @override
  String get metersFilterHelp => 'By meter name, code or Asset.';

  @override
  String get metersNoMatch => 'No meters match';

  @override
  String metersNoMatchMessage(String term) {
    return 'This Site has meters, but none matches “$term”. Try a different name, code or Asset.';
  }

  @override
  String get metersNoReading => 'No reading yet';

  @override
  String get metersType => 'Type';

  @override
  String get metersUnit => 'Unit';

  @override
  String get metersLatestReading => 'Latest reading';

  @override
  String get metersAccumulated => 'Accumulated use';

  @override
  String metersCarriedForward(String value, String unit) {
    return 'Carried forward: $value $unit';
  }

  @override
  String metersLatestLine(String label) {
    return 'Latest: $label';
  }

  @override
  String metersAccumulatedLine(String label) {
    return 'Accumulated use: $label';
  }

  @override
  String get metersNoneExistTitle => 'No meters yet';

  @override
  String get metersNoneExistMessage =>
      'No meter is defined on this Site\'s Assets yet.';

  @override
  String get commonCode => 'Code';

  @override
  String get commonName => 'Name';

  @override
  String get jobPlansUnavailableTitle => 'The Job plans could not be read';

  @override
  String get jobPlansDescription =>
      'How each recurring job is done — the steps it takes and what each one requires. A Work order follows a plan; it does not change one.';

  @override
  String get jobPlansAdd => 'Add a Job plan';

  @override
  String get jobPlansFilter => 'Filter Job plans';

  @override
  String get jobPlansFilterHelp => 'By name, code or description.';

  @override
  String get jobPlansNoMatch => 'No Job plans match';

  @override
  String jobPlansNoMatchMessage(String term) {
    return 'The plant has Job plans, but none matches “$term”. Try a different name, code or description.';
  }

  @override
  String get jobPlansPlanColumn => 'Plan';

  @override
  String get jobPlansSteps => 'Steps';

  @override
  String get jobPlansEstimatedHours => 'Estimated hours';

  @override
  String get jobPlansShutdown => 'Shutdown';

  @override
  String jobPlansStepCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '1 step',
    );
    return '$_temp0';
  }

  @override
  String get jobPlansInactive => 'Inactive';

  @override
  String get jobPlansRequiresShutdown => 'Requires a shutdown';

  @override
  String jobPlansAboutHours(String hours) {
    return 'About $hours h';
  }

  @override
  String get jobPlansNoSteps => 'No steps recorded.';

  @override
  String get jobPlansDeactivate => 'Deactivate';

  @override
  String get jobPlansReactivate => 'Reactivate';

  @override
  String get jobPlansNoneExistTitle => 'No Job plans yet';

  @override
  String get jobPlansNoneExistMessage =>
      'No reusable job plan has been defined. Add one and its steps will show here.';

  @override
  String get pmSchedulesUnavailableTitle =>
      'The PM schedules could not be read';

  @override
  String get pmSchedulesDescription =>
      'The Job plans attached to this Site\'s Assets that raise a Work order before something breaks.';

  @override
  String get pmSchedulesAdd => 'Add a PM schedule';

  @override
  String get pmSchedulesFilter => 'Filter PM schedules';

  @override
  String get pmSchedulesFilterHelp => 'By schedule name, Asset or Job plan.';

  @override
  String get pmSchedulesNoMatch => 'No PM schedules match';

  @override
  String pmSchedulesNoMatchMessage(String term) {
    return 'This Site has PM schedules, but none matches “$term”. Try a different name, Asset or Job plan.';
  }

  @override
  String get pmSchedulesJobPlanColumn => 'Job plan';

  @override
  String get pmSchedulesInterval => 'Interval';

  @override
  String get pmSchedulesDue => 'Due';

  @override
  String get pmSchedulesRules => 'Rules';

  @override
  String pmSchedulesRuleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rules',
      one: '1 rule',
    );
    return '$_temp0';
  }

  @override
  String pmSchedulesRollsFrom(String anchor) {
    return 'Rolls from $anchor';
  }

  @override
  String pmSchedulesLeadTime(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Raised $days days early',
      one: 'Raised 1 day early',
    );
    return '$_temp0';
  }

  @override
  String pmSchedulesAccumulated(String current, String target) {
    return 'Accumulated $current of $target';
  }

  @override
  String pmSchedulesEveryMeter(String interval, String meter) {
    return 'Every $interval of $meter';
  }

  @override
  String pmSchedulesEveryDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Every $days days',
      one: 'Every day',
    );
    return '$_temp0';
  }

  @override
  String get pmSchedulesTheMeter => 'the meter';

  @override
  String pmSchedulesPriorityLine(String priority) {
    return 'Priority $priority';
  }

  @override
  String get pmSchedulesDueNow => 'Due now';

  @override
  String get pmSchedulesNoMeterTarget => 'No meter target yet';

  @override
  String pmSchedulesDueAt(String value) {
    return 'Due at $value';
  }

  @override
  String get pmSchedulesNoDueDate => 'No due date yet';

  @override
  String pmSchedulesNextDue(String date) {
    return 'Next due $date';
  }

  @override
  String pmSchedulesOverdueSince(String date) {
    return 'Overdue since $date';
  }

  @override
  String get pmSchedulesDueToday => 'Due today';

  @override
  String pmSchedulesDueIn(String date, int days) {
    return 'Due $date (in $days days)';
  }

  @override
  String get pmSchedulesNoneExistTitle => 'Nothing is scheduled';

  @override
  String get pmSchedulesNoneExistMessage =>
      'No PM schedule is attached to this Site\'s Assets yet.';

  @override
  String get titleSignIn => 'Sign in';

  @override
  String get titleAwaitingApproval => 'Awaiting approval';

  @override
  String get titleChooseNewPassword => 'Choose a new password';

  @override
  String get titleFloor => 'Floor';

  @override
  String get titleCapaReport => 'CAPA report';

  @override
  String get titleTrainingRecordForm => 'Training record form';

  @override
  String get titleWelcome => 'Welcome';

  @override
  String get titleEmployee => 'Employee';

  @override
  String get titleWorkedHours => 'Worked hours';

  @override
  String get titleAttendanceToConfirm => 'Attendance to confirm';

  @override
  String get titleAttendanceSheet => 'Attendance sheet';

  @override
  String get titleTrainingRecords => 'Training records';

  @override
  String get titleTrainingRecord => 'Training record';

  @override
  String get titleQualitySlideShow => 'Quality slide show';

  @override
  String get titleCustomerComplaint => 'Customer complaint';

  @override
  String get titleSupplierNcr => 'Supplier NCR';

  @override
  String get titleNonConformance => 'Non-conformance';

  @override
  String get titleShiftHandover => 'Shift handover';

  @override
  String get titleSafetyIncidents => 'Safety incidents';

  @override
  String get titleSafetyIncident => 'Safety incident';

  @override
  String get titleSafetyObservations => 'Safety observations';

  @override
  String get titleSafetyObservation => 'Safety observation';

  @override
  String get titleKpiTargets => 'KPI targets';

  @override
  String get titleActions => 'Actions';

  @override
  String get titleAction => 'Action';

  @override
  String get titleApprovalQueue => 'Approval queue';

  @override
  String get titleStoreStock => 'Store stock';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonAssetsFailed => 'The Assets could not be read.';

  @override
  String get commonJobPlan => 'Job plan';

  @override
  String get commonMeter => 'Meter';

  @override
  String get commonEmployee => 'Employee';

  @override
  String get commonUnitOfMeasure => 'Unit of measure';

  @override
  String get commonQuantity => 'Quantity';

  @override
  String get commonPart => 'Part';

  @override
  String get commonStore => 'Store';

  @override
  String get commonNoteOptional => 'Note (optional)';

  @override
  String get commonPriorityMostUrgent => 'Most urgent';

  @override
  String get commonPriorityUrgent => 'Urgent';

  @override
  String get commonPriorityNormal => 'Normal';

  @override
  String get commonPriorityLow => 'Low';

  @override
  String get commonPriorityLeastUrgent => 'Least urgent';

  @override
  String get pmScheduleFormTitle => 'Schedule preventive maintenance';

  @override
  String get pmScheduleFormSubmit => 'Schedule';

  @override
  String get pmScheduleFormBasisField => 'Comes round on';

  @override
  String get pmScheduleFormBasisElapsed => 'Elapsed time';

  @override
  String get pmScheduleFormBasisAccumulated => 'Accumulated use';

  @override
  String get pmScheduleFormEveryDays => 'Every how many days';

  @override
  String get pmScheduleFormEveryAccumulated => 'Every how much accumulated use';

  @override
  String get pmScheduleFormMeterNotChosen => 'Choose a cumulative meter first.';

  @override
  String pmScheduleFormMeterIntervalHelp(String uom) {
    return 'In $uom, one interval past where the meter stands now.';
  }

  @override
  String get pmScheduleFormAnchor => 'The interval rolls from';

  @override
  String get pmScheduleFormLeadTime => 'Raise this many days early';

  @override
  String get pmScheduleFormPriorityMostUrgent => '1 — most urgent';

  @override
  String get pmScheduleFormPriorityLeastUrgent => '5 — least urgent';

  @override
  String get pmScheduleFormFirstDue => 'First due date (optional)';

  @override
  String get pmScheduleFormFirstDueHelp =>
      'Left blank, the first due date is the interval from today.';

  @override
  String get pmScheduleFormJobPlansFailed => 'The Job plans could not be read.';

  @override
  String get pmScheduleFormMetersFailed => 'The meters could not be read.';

  @override
  String get pmScheduleFormMeterHelp =>
      'Only cumulative meters can drive a schedule.';

  @override
  String get jobPlanFormSubmit => 'Add plan';

  @override
  String get jobPlanFormWorkType => 'Kind of work';

  @override
  String get jobPlanFormDescriptionOptional => 'Description (optional)';

  @override
  String get jobPlanFormEstimatedHoursOptional => 'Estimated hours (optional)';

  @override
  String get jobPlanFormRequiresShutdown => 'Requires a shutdown';

  @override
  String get jobPlanFormSafetyNoteOptional => 'Safety note (optional)';

  @override
  String get jobPlanFormAddStep => 'Add a step';

  @override
  String get jobPlanFormSkillsFailed =>
      'The skill catalogue could not be read.';

  @override
  String get jobPlanFormStep => 'Step';

  @override
  String get jobPlanFormInstruction => 'Instruction';

  @override
  String get jobPlanFormRemoveStep => 'Remove this step';

  @override
  String get jobPlanFormRequiredSkill => 'Required skill (optional)';

  @override
  String get jobPlanFormHoursOptional => 'Hours (optional)';

  @override
  String get meterFormSubmit => 'Define';

  @override
  String get meterFormCodeHelp =>
      'How this meter is known on the Asset, e.g. RUN-HRS.';

  @override
  String get meterFormType => 'Kind of meter';

  @override
  String get meterFormUomFailed => 'The units of measure could not be read.';

  @override
  String readingFormTitle(String meter) {
    return 'Record a reading on $meter';
  }

  @override
  String get readingFormSubmitRollover => 'Record rollover';

  @override
  String get readingFormSubmit => 'Record reading';

  @override
  String readingFormAccumulatedSoFar(String value) {
    return 'Accumulated use so far: $value';
  }

  @override
  String get readingFormNewCounterReads => 'What the new counter reads now';

  @override
  String get readingFormCounterReads => 'What the counter reads';

  @override
  String get readingFormRolloverHelp =>
      'The accumulated use is carried forward into the offset; the new counter usually reads 0.';

  @override
  String readingFormReadingHelp(String uom) {
    return 'In $uom, exactly as the counter shows.';
  }

  @override
  String get readingFormRolloverTitle => 'The counter was reset or replaced';

  @override
  String get readingFormRolloverSubtitle =>
      'Carries the accumulated use into the offset and records this as the new counter\'s start.';

  @override
  String requestAcceptTitle(String requestNo) {
    return 'Accept $requestNo?';
  }

  @override
  String get requestAcceptDismiss => 'Keep it waiting';

  @override
  String get requestAcceptSubmit => 'Accept this Request';

  @override
  String get requestAcceptBody =>
      'Accepting raises a Work order for this Request. Its priority is your call, not the reporter\'s urgency.';

  @override
  String requestDeclineTitle(String requestNo) {
    return 'Decline $requestNo?';
  }

  @override
  String get requestDeclineReason => 'Why is this being declined?';

  @override
  String get requestDeclineSubmit => 'Decline this Request';

  @override
  String get requestDuplicateTitle => 'Mark as a duplicate';

  @override
  String get requestDuplicateDismiss => 'Keep it separate';

  @override
  String get requestDuplicateNone =>
      'There is no other open Request for this one to duplicate.';

  @override
  String requestDuplicateWhich(String requestNo) {
    return 'Which Request survives? $requestNo leaves the queue.';
  }

  @override
  String get labourBookingTitle => 'Book labour';

  @override
  String get labourBookingActivity => 'Activity';

  @override
  String get labourBookingStartedAt => 'Started at';

  @override
  String get labourBookingEndedAt => 'Ended at';

  @override
  String get labourBookingOvertime => 'Overtime';

  @override
  String get labourBookingEmployeesFailed => 'The Employees could not be read.';

  @override
  String get partBookingTitle => 'Book a part';

  @override
  String get partBookingSubmit => 'Book part';

  @override
  String get partBookingSourced => 'Sourced';

  @override
  String get partBookingOptionsFailed => 'The options could not be read.';

  @override
  String get partBookingPartNoOptional => 'Part number (optional)';

  @override
  String get partBookingUnitCostOptional => 'Unit cost (optional)';

  @override
  String get nonconformancesUnavailableTitle =>
      'The Non-conformance register could not be read';

  @override
  String get nonconformancesNoSiteTitle => 'No Site to show';

  @override
  String get nonconformancesNoSiteMessage =>
      'Your Account can see no Site yet, so there is nothing to read here.';

  @override
  String get nonconformancesDescription =>
      'What was found not to conform at this Site, where it was found, and how much of it there is.';

  @override
  String get nonconformanceRecord => 'Record a Non-conformance';

  @override
  String get commonAllOrgUnits => 'All Org Units';

  @override
  String get nonconformancesAnyStatus => 'Any status';

  @override
  String get commonDefectCode => 'Defect code';

  @override
  String get nonconformancesEveryDefectCode => 'Every Defect code';

  @override
  String get commonProduct => 'Product';

  @override
  String get nonconformancesEveryProduct => 'Every Product';

  @override
  String get nonconformancesSeverity => 'Severity';

  @override
  String get nonconformancesAnySeverity => 'Any severity';

  @override
  String get nonconformancesDetectedFrom => 'Detected from';

  @override
  String get nonconformancesDetectedTo => 'Detected to';

  @override
  String get nonconformancesTruncated =>
      'There are more Non-conformances than this list shows. Narrow it by Org Unit, by status or by date to see the rest.';

  @override
  String get nonconformancesNoMatchTitle => 'Nothing matches these filters';

  @override
  String get nonconformancesNoMatchMessage =>
      'The register has Non-conformances, but none of them is in the area, state, Defect code, Product, severity or dates you picked.';

  @override
  String get nonconformancesClearTheFilters => 'Clear the filters';

  @override
  String get nonconformancesNoneExistTitle =>
      'Nothing has been found not to conform';

  @override
  String get nonconformancesNoneExistMessage =>
      'No Non-conformance has been recorded at this Site.';

  @override
  String get nonconformancesNumberColumn => 'Non-conformance';

  @override
  String get nonconformancesFoundColumn => 'What was found';

  @override
  String get commonState => 'State';

  @override
  String get nonconformancesFiledColumn => 'Filed';

  @override
  String get commonOpen => 'Open';

  @override
  String nonconformanceQuantityAffected(String count, String uom) {
    return '$count $uom affected';
  }

  @override
  String nonconformanceQuantityRaised(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'raised $count times',
      one: 'raised 1 time',
    );
    return '$_temp0';
  }

  @override
  String nonconformanceFiledAgainst(String orgUnit, String against) {
    return '$orgUnit · filed against $against';
  }

  @override
  String get nonconformanceFormRecord => 'Record it';

  @override
  String get nonconformanceFormProductHelp =>
      'What the nonconforming product is.';

  @override
  String get nonconformanceFormDefectCodeHelp =>
      'What is wrong with it. The severity starts at this code own default.';

  @override
  String get nonconformanceFormChooseCode => 'Choose a code';

  @override
  String get nonconformanceFormDetectionPoint => 'Detection point';

  @override
  String get nonconformanceFormDetectionPointHelp =>
      'Where the control plan caught it.';

  @override
  String get nonconformanceFormChoosePoint => 'Choose a point';

  @override
  String get nonconformanceFormSeverityHelpUnset =>
      'Chosen with the Defect code.';

  @override
  String nonconformanceFormSeverityHelpSet(String severity) {
    return 'Starts at $severity. Raising it is allowed; lowering it is a later decision.';
  }

  @override
  String get nonconformanceFormChooseCodeFirst => 'Choose a Defect code first';

  @override
  String nonconformanceFormStartsAt(String severity) {
    return 'Starts at $severity';
  }

  @override
  String get nonconformanceFormQuantityHelp => 'How many pieces.';

  @override
  String get nonconformanceFormLotRef => 'Lot reference (optional)';

  @override
  String get nonconformanceFormLotRefHelp =>
      'What else is affected — a batch number is better than nothing.';

  @override
  String get nonconformanceFormAssetOptional => 'Asset (optional)';

  @override
  String get nonconformanceFormAssetHelp =>
      'Which machine, if the find was on one. It must sit at that Org Unit.';

  @override
  String get nonconformanceFormDetailOptional => 'Detail (optional)';

  @override
  String get nonconformanceFormContainment =>
      'Immediate containment (optional)';

  @override
  String get nonconformanceFormContainmentHelp =>
      'What was done at once. Recording it makes this contained.';

  @override
  String get nonconformanceFormDetectedAt => 'Detected at (optional)';

  @override
  String get nonconformanceFormDetectedAtHelp =>
      'When it was found, if that is not now. This is what decides the production day and shift it is filed against.';

  @override
  String get nonconformanceFormWhereFound => 'Where it was found';

  @override
  String get nonconformanceFormWhereFoundHelp =>
      'Choose the Org Unit the nonconforming product was found at. This is what decides who may act on it.';

  @override
  String nonconformanceFormWillBeRecorded(String orgUnit) {
    return 'This Non-conformance will be recorded at $orgUnit.';
  }

  @override
  String get nonconformanceFloorIntro =>
      'What was found not to conform? Everything with a known set is chosen from what this device can see.';

  @override
  String get nonconformanceFloorChooseProduct => 'Choose a Product';

  @override
  String get nonconformanceFloorDetectedAt => 'Detected at';

  @override
  String nonconformanceFloorStartsAt(String severity) {
    return 'Starts at $severity — this Defect code\'s own severity.';
  }

  @override
  String get nonconformanceFloorHowMuch => 'How much of it';

  @override
  String get nonconformanceFloorLot => 'Lot or batch (if it has one)';

  @override
  String get nonconformanceFloorWhatDidYouSee => 'What did you see?';

  @override
  String get nonconformanceFloorWhoFound =>
      'Who found it? Your Employee number and PIN identify you for this record only — it is filed as your find.';

  @override
  String get nonconformanceFloorEmployeeNumber => 'Employee number';

  @override
  String get nonconformanceFloorPin => 'PIN';

  @override
  String get nonconformanceTitle => 'Non-conformance';

  @override
  String get nonconformanceDetailMissingTitle => 'No such Non-conformance';

  @override
  String get nonconformanceDetailMissingMessage =>
      'Nothing is recorded at this address. It may have been removed, or the address may be wrong.';

  @override
  String get nonconformanceDetailBack => 'Back to Non-conformances';

  @override
  String get nonconformanceDetailUnavailableTitle =>
      'The Non-conformance could not be read';

  @override
  String nonconformanceDetailSeverityChip(String severity) {
    return '$severity severity';
  }

  @override
  String nonconformanceDetailFinishedAt(String date) {
    return 'Finished $date';
  }

  @override
  String get nonconformanceDetailDetail => 'Detail';

  @override
  String get nonconformanceDetailQuantityAffected => 'Quantity affected';

  @override
  String get nonconformanceDetailFiledAgainst => 'Filed against';

  @override
  String get commonNoneGiven => 'None given';

  @override
  String get commonNoneNamed => 'None named';

  @override
  String get commonNotGiven => 'Not given';

  @override
  String get commonNotRecorded => 'Not recorded';

  @override
  String get commonNoneRecorded => 'None recorded yet';

  @override
  String get nonconformanceDetailLotRef => 'Lot reference';

  @override
  String get nonconformanceDetailContainment => 'Immediate containment';

  @override
  String nonconformanceDetailDefectCodeValue(
    String name,
    String code,
    String severity,
  ) {
    return '$name · $code · starts at $severity';
  }

  @override
  String get nonconformanceDetailActionsSection => 'What can be done';

  @override
  String get nonconformanceIncreaseQuantity => 'Increase the quantity';

  @override
  String get nonconformanceUpdate => 'Raise severity or contain it';

  @override
  String get nonconformanceDisposition => 'Record a Disposition';

  @override
  String get nonconformanceConcession => 'Grant a Concession';

  @override
  String get nonconformanceLowerSeverity => 'Lower the severity';

  @override
  String get nonconformanceReopen => 'Reopen it';

  @override
  String get nonconformanceCancel => 'Cancel it in error';

  @override
  String get nonconformanceDetailQuantityHistory => 'Quantity history';

  @override
  String get nonconformanceDetailQuantityHistoryNote =>
      'Sorting finds more than the first count. Every change is kept, and the affected quantity never shrinks.';

  @override
  String get nonconformanceDetailNoQuantityHistory =>
      'The affected quantity has not been changed since it was recorded.';

  @override
  String get nonconformanceDetailDispositions => 'Dispositions';

  @override
  String get nonconformanceDetailDispositionsNote =>
      'Product is dealt with in parts. A Non-conformance closes by itself once all of its quantity has a Disposition.';

  @override
  String nonconformanceDetailDispositioned(
    String done,
    String total,
    String uom,
  ) {
    return '$done of $total $uom dispositioned';
  }

  @override
  String get nonconformanceDetailNoDispositions =>
      'Nothing has been decided about this product yet.';

  @override
  String nonconformanceDetailReworkMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes of rework',
      one: '1 minute of rework',
    );
    return '$_temp0';
  }

  @override
  String get nonconformanceDetailCorrections => 'Corrections';

  @override
  String get nonconformanceDetailCorrectionsNote =>
      'What a holder of Quality authority has changed about this record, and why.';

  @override
  String get nonconformanceDetailNoCorrections =>
      'This record has not been corrected.';

  @override
  String get nonconformanceDetailCause => 'The cause';

  @override
  String get nonconformanceDetailCauseNote =>
      'Nonconforming product is dealt with here; the problem behind it is solved in the action log, as a Concern. One problem that shows up several times stays one Concern.';

  @override
  String get nonconformanceDetailNoConcerns =>
      'Nothing is being done about the cause yet.';

  @override
  String get nonconformanceDetailRaisedFrom => 'raised from this record';

  @override
  String get nonconformanceDetailOverdue => 'overdue';

  @override
  String get nonconformanceRaiseConcern => 'Raise a Concern';

  @override
  String get nonconformanceLinkConcern => 'Link it to a Concern';

  @override
  String get commonNoSiteTitle => 'No Site to show';

  @override
  String get commonNoSiteMessage =>
      'Your Account can see no Site yet, so there is nothing to read here.';

  @override
  String commonFiledAgainst(String orgUnit, String against) {
    return '$orgUnit · filed against $against';
  }

  @override
  String get commonFiledAgainstColumn => 'Filed against';

  @override
  String get commonAny => 'Any';

  @override
  String get commonType => 'Type';

  @override
  String get commonCategory => 'Category';

  @override
  String get commonAction => 'Action';

  @override
  String get commonSeverity => 'Severity';

  @override
  String get safetyIncidentsUnavailableTitle =>
      'The Safety incident register could not be read';

  @override
  String get safetyIncidentsDescription =>
      'What went wrong at this Site, where it happened, and where it sits on the severity ladder.';

  @override
  String get safetyIncidentRecord => 'Record a Safety incident';

  @override
  String get safetyIncidentType => 'Incident type';

  @override
  String get safetyRecordable => 'Recordable';

  @override
  String get safetyNotRecordable => 'Not recordable';

  @override
  String get safetyOccurredFrom => 'Occurred from';

  @override
  String get safetyOccurredTo => 'Occurred to';

  @override
  String get safetyIncidentsTruncated =>
      'There are more Safety incidents than this list shows. Narrow it by Org Unit, by status or by date to see the rest.';

  @override
  String get safetyIncidentsNoMatchMessage =>
      'The register has Safety incidents, but none of them is in the area, state, type, severity, recordability or dates you picked.';

  @override
  String get safetyIncidentsNoneTitle =>
      'No incidents recorded for this period';

  @override
  String get safetyIncidentsNoneMessage =>
      'No Safety incident has been recorded at this Site for the area and dates shown.';

  @override
  String get safetyIncidentNumberColumn => 'Incident #';

  @override
  String get safetyObservationsUnavailableTitle =>
      'The Safety observation register could not be read';

  @override
  String get safetyObservationsDescription =>
      'What was seen before anything went wrong, ranked worst-first by the worst credible outcome.';

  @override
  String get safetyObservationRecord => 'Record an observation';

  @override
  String get safetyAnyType => 'Any type';

  @override
  String get safetyAnyCategory => 'Any category';

  @override
  String get safetySeverityPotential => 'Severity potential';

  @override
  String get safetyAnyPotential => 'Any potential';

  @override
  String get safetyStopWork => 'Stop-work';

  @override
  String get safetyStopWorkOnly => 'Stop-work only';

  @override
  String get safetyNotStopWork => 'Not stop-work';

  @override
  String get safetyNoActionRaised => 'No Action raised';

  @override
  String get safetyActionRaised => 'Action raised';

  @override
  String get safetyObservedFrom => 'Observed from';

  @override
  String get safetyObservedTo => 'Observed to';

  @override
  String get safetyObservationsTruncated =>
      'There are more Safety observations than this list shows. Narrow it by Org Unit, by type or by date to see the rest.';

  @override
  String get safetyObservationsNoMatchMessage =>
      'The register has Safety observations, but none of them is in the area, type, category, potential, stop-work or dates you picked.';

  @override
  String get safetyObservationsNoneTitle =>
      'No observations recorded. The leading indicator is empty.';

  @override
  String get safetyObservationsNoneMessage =>
      'No Safety observation has been recorded at this Site for the area and dates shown.';

  @override
  String get safetyPotentialColumn => 'Potential';

  @override
  String get safetyIncidentReport => 'Report a Safety incident';

  @override
  String get safetyReportSubmit => 'Report it';

  @override
  String get safetyIncidentFloorIntro =>
      'What happened? Everything with a known set is chosen from a fixed list.';

  @override
  String get safetyWhatHappened => 'What happened';

  @override
  String get safetyImmediateAction => 'Immediate action (optional)';

  @override
  String get safetyOccurredAt => 'Occurred at';

  @override
  String get safetyIncidentFloorWho =>
      'Who is reporting this? Your Employee number and PIN identify you for this record only — it is filed as your report.';

  @override
  String get safetyObservationRecordTitle => 'Record a Safety observation';

  @override
  String get safetyObservationFloorIntro =>
      'What was seen? Everything with a known set is chosen from a fixed list.';

  @override
  String get safetyWhatWasSeen => 'What was seen';

  @override
  String get safetyActionTaken => 'Action taken (optional)';

  @override
  String get safetyStopWorkExercised => 'Stop-work authority was exercised';

  @override
  String get safetyObservationFloorWho =>
      'Who is recording this? Your Employee number and PIN identify you for this record only.';

  @override
  String get commonBack => 'Back';

  @override
  String get routerLeaveNotDecidable =>
      'This leave request is not one you can decide.';

  @override
  String get routerLeaveNotCancellable =>
      'This leave request cannot be cancelled.';

  @override
  String get routerNotAMeasure => 'That is not a measure';

  @override
  String get routerNotAMeasureBody =>
      'A measure is a containment, a countermeasure or a preventive action.';

  @override
  String get routerBackToAction => 'Back to the Action';

  @override
  String get routerCannotDoThatHere => 'You cannot do that here';

  @override
  String get routerNoWriteGrant =>
      'You do not hold a write Grant anywhere at this Site.';

  @override
  String get routerBackToList => 'Back to the list';

  @override
  String get cameraScanButton => 'Scan with the camera';

  @override
  String get cameraScanTitle => 'Scan a code';

  @override
  String get cameraScanPointAtCode =>
      'Point the camera at the code — it is read as soon as it is recognised.';

  @override
  String get cameraScanClose => 'Close';

  @override
  String get cameraScanRefusedTitle => 'The camera could not be opened';

  @override
  String get cameraScanRefusedBody =>
      'Allow this site to use the camera in the browser, then try again.';

  @override
  String get cameraScanUnsupportedTitle =>
      'This browser cannot read a code with the camera';

  @override
  String get cameraScanUnsupportedBody =>
      'Type the code instead, or use the shop-floor reader.';
}
