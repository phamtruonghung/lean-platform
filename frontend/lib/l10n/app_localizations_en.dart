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

  @override
  String get accountCorrectionChangeRoleAndGrants => 'Change role and Grants';

  @override
  String get commonSave => 'Save';

  @override
  String accountCorrectionHoldsTheRoleAndTheOrgUnit(Object email) {
    return '$email holds the role and the Org Unit Grants chosen here. Whatever is set below replaces what it has now.';
  }

  @override
  String get accountCorrectionAnAdministratorCanActEverywhereThisAccount =>
      'An administrator can act everywhere. This Account will be able to see and change every Site and every Org Unit, and to admit other Accounts. Every Org Unit Grant it holds now is removed, and none are needed.';

  @override
  String get accountCorrectionThisAccountWasTurnedAwaySavingThis =>
      'This Account was turned away. Saving this admits it to the Platform and lets it sign in.';

  @override
  String get accountCorrectionThisAccountIsDeactivatedSavingThisReactivates =>
      'This Account is deactivated. Saving this reactivates it and lets it sign in again.';

  @override
  String get commonChangeEmployeeLink => 'Change Employee link';

  @override
  String accountEmployeeWillBeLinkedToTheEmployeeChosen(Object email) {
    return '$email will be linked to the Employee chosen here, or to none.';
  }

  @override
  String get commonResetPassword => 'Reset password';

  @override
  String accountPasswordChooseANewPasswordForTellThem(Object email) {
    return 'Choose a new password for $email. Tell them what it is yourself; it is not shown again.';
  }

  @override
  String accountPasswordAtLeastCharacters(Object minimumPasswordLength) {
    return 'At least $minimumPasswordLength characters.';
  }

  @override
  String accountRolesRolesFor(Object accountName) {
    return 'Roles for $accountName';
  }

  @override
  String get commonAssigning => 'Assigning…';

  @override
  String accountRolesRoleAssigned(int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length roles assigned',
      one: '1 role assigned',
    );
    return '$_temp0';
  }

  @override
  String accountRolesEveryAccountHoldsThis(Object code) {
    return '$code — every Account holds this';
  }

  @override
  String accountRolesEveryAccountWhoseOwnRoleIs(
    Object code,
    Object legacyRole,
  ) {
    return '$code — every Account whose own role is $legacyRole';
  }

  @override
  String accountRolesPermission(String code, int length) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length permissions',
      one: '1 permission',
    );
    return '$code — $_temp0';
  }

  @override
  String get accountsTheAccountsCouldNotBeLoaded =>
      'The Accounts could not be loaded';

  @override
  String get accountsNoAccountsYet => 'No Accounts yet';

  @override
  String get accountsAccountsAppearHereAsSoonAsSomebody =>
      'Accounts appear here as soon as somebody signs in for the first time.';

  @override
  String get accountsEveryAccountOnThisPlantWhatIt =>
      'Every Account on this plant: what it holds, and whether it can sign in.';

  @override
  String get commonFilterAccounts => 'Filter Accounts';

  @override
  String get accountsByNameEmailOrRole => 'By name, email or role.';

  @override
  String get commonNoAccountsMatch => 'No Accounts match';

  @override
  String accountsThisPlantHasAccountsButNoneMatches(Object term) {
    return 'This plant has Accounts, but none matches \"$term\". Try a different name, email or role, or clear the filter.';
  }

  @override
  String get accountsEmail => 'Email';

  @override
  String get accountsRole => 'Role';

  @override
  String get accountsStanding => 'Standing';

  @override
  String get accountsSince => 'Since';

  @override
  String get accountsGrants => 'Grants';

  @override
  String get accountsReviewInApprovals => 'Review in Approvals';

  @override
  String get accountsChange => 'Change';

  @override
  String get accountsLinkAnEmployee => 'Link an Employee';

  @override
  String get accountsEverywhere => 'Everywhere';

  @override
  String get accountsNone => 'None';

  @override
  String accountsOrgUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Org Units',
      one: '1 Org Unit',
    );
    return '$_temp0';
  }

  @override
  String get accountsActsEverywhereInEverySiteNoOrg =>
      'Acts everywhere, in every Site. No Org Unit Grants, and none needed.';

  @override
  String get accountsNoOrgUnitGrantsCanSignIn =>
      'No Org Unit Grants. Can sign in, but cannot act in any Org Unit.';

  @override
  String get accountsDeactivateThisAccount => 'Deactivate this Account?';

  @override
  String accountsWillNotBeAbleToSignIn(Object email) {
    return '$email will not be able to sign in. Nothing is deleted — the role and the Org Unit Grants stay exactly as they are, and an administrator can reactivate the Account at any time.';
  }

  @override
  String get admissionAdmitThisAccount => 'Admit this Account';

  @override
  String get commonAdmitting => 'Admitting…';

  @override
  String get commonAdmit => 'Admit';

  @override
  String admissionWillBeLetInToThePlatform(Object email) {
    return '$email will be let in to the Platform with the role chosen here.';
  }

  @override
  String get admissionAnAdministratorCanActEverywhereThisAccount =>
      'An administrator can act everywhere. This Account will be able to see and change every Site and every Org Unit, and to admit other Accounts. No Org Unit Grants are given, and none are needed.';

  @override
  String get admissionThisAccountWillBeAdmittedWithNo =>
      'This Account will be admitted with no Org Unit Grants, so it can sign in but cannot yet act in any Org Unit.';

  @override
  String get approvalQueueTheQueueCouldNotBeLoaded =>
      'The queue could not be loaded';

  @override
  String get approvalQueueNobodyIsWaiting => 'Nobody is waiting';

  @override
  String get approvalQueueEveryAccountHasBeenDealtWithNew =>
      'Every Account has been dealt with. New requests appear here.';

  @override
  String get approvalQueueEveryoneWaitingToBeLetInTo =>
      'Everyone waiting to be let in to the Platform.';

  @override
  String get approvalQueueByEmailAddress => 'By email address.';

  @override
  String approvalQueueAccountsAreWaitingButNoneMatchesTry(Object term) {
    return 'Accounts are waiting, but none matches \"$term\". Try a different email address, or clear the filter.';
  }

  @override
  String get approvalQueueAccount => 'Account';

  @override
  String get approvalQueueSuggestedEmployee => 'Suggested Employee';

  @override
  String get approvalQueueWaiting => 'Waiting';

  @override
  String get approvalQueueRejecting => 'Rejecting…';

  @override
  String get commonReject => 'Reject';

  @override
  String get approvalQueueRejectThisAccount => 'Reject this Account?';

  @override
  String approvalQueueWillNotBeLetInToThe(Object email) {
    return '$email will not be let in to the Platform, and will be told their request was turned down. An administrator can still admit them later.';
  }

  @override
  String get attendancePickerChooseAnOrgUnitAndAProduction =>
      'Choose an Org Unit and a production day to open that shift\'s attendance sheet.';

  @override
  String get attendancePickerProductionDay => 'Production day';

  @override
  String get attendancePickerTheShiftsCouldNotBeRead =>
      'The shifts could not be read';

  @override
  String get attendancePickerNoShiftsAreScheduledHereOnThat =>
      'No shifts are scheduled here on that day.';

  @override
  String get attendancePickerChooseAnotherProductionDayOrAnotherOrg =>
      'Choose another production day, or another Org Unit.';

  @override
  String get commonTheSitesAreUnavailable => 'The Sites are unavailable.';

  @override
  String get commonThereAreNoSitesToBrowseYet =>
      'There are no Sites to browse yet.';

  @override
  String get commonNothingToBrowseInThisSite =>
      'Nothing to browse in this Site.';

  @override
  String get commonCollapse => 'Collapse';

  @override
  String get commonExpand => 'Expand';

  @override
  String attendanceRecordMark(Object displayName) {
    return 'Mark $displayName';
  }

  @override
  String get attendanceRecordWorkedMinutes => 'Worked minutes';

  @override
  String get attendanceRecordOvertimeMinutes => 'Overtime minutes';

  @override
  String get attendanceSheetTheAttendanceSheetCouldNotBeRead =>
      'The attendance sheet could not be read';

  @override
  String get attendanceSheetNobodyWithAnEditGrantHereHas =>
      'Nobody with an edit Grant here has opened this sheet yet, so there is nothing to show. Only a supervisor holding an edit Grant reaching this shift — or an administrator — can start it.';

  @override
  String get attendanceSheetConfirmed => 'Confirmed';

  @override
  String get attendanceSheetConfirming => 'Confirming…';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get attendanceSheetNobodyIsOnThisSheetYet =>
      'Nobody is on this sheet yet.';

  @override
  String get attendanceSheetAddAStandInFromTheDirectory =>
      'Add a stand-in from the Directory below to open the sheet with somebody on it.';

  @override
  String get attendanceSheetASupervisorHoldingAnEditGrantReaching =>
      'A supervisor holding an edit Grant reaching this shift adds the people who were on it.';

  @override
  String get attendanceSheetMarkAnException => 'Mark an exception';

  @override
  String get attendanceSheetRemoveFromTheSheet => 'Remove from the sheet';

  @override
  String get attendanceSheetAddAStandIn => 'Add a stand-in';

  @override
  String get commonSearchTheDirectory => 'Search the Directory';

  @override
  String get attendanceSheetWorkedMin => 'Worked (min)';

  @override
  String get attendanceSheetOvertimeMin => 'Overtime (min)';

  @override
  String get attendanceToConfirmPastShiftsWhoseSheetIsMissingOr =>
      'Past shifts whose sheet is missing or hasn\'t been confirmed yet, oldest first, across the Org Units you can confirm one at.';

  @override
  String get attendanceToConfirmTheWorklistCouldNotBeRead =>
      'The worklist could not be read';

  @override
  String get attendanceToConfirmNothingToConfirmHere =>
      'Nothing to confirm here.';

  @override
  String get attendanceToConfirmEveryPastShiftYouCanConfirmHas =>
      'Every past shift you can confirm has a confirmed sheet.';

  @override
  String get attendanceToConfirmNoShiftInThisWindowNeedsConfirming =>
      'No shift in this window needs confirming. Widen the window, or clear the Org Unit.';

  @override
  String get commonFrom => 'From';

  @override
  String commonOrgUnit2(Object orgUnitName) {
    return 'Org Unit: $orgUnitName';
  }

  @override
  String get commonClear => 'Clear';

  @override
  String get commonHideOrgUnits => 'Hide Org Units';

  @override
  String get commonFilterByOrgUnit => 'Filter by Org Unit';

  @override
  String get attendanceToConfirmOpenSheet => 'Open sheet';

  @override
  String get commonUsd => 'USD';

  @override
  String get costRateFormTheRateBelowIsClosedOnThe =>
      'The rate below is closed on the day the new one takes effect. It stays readable, and a cost asked for an earlier date still resolves it.';

  @override
  String costRateFormTheListOfSitesOrgUnitsAssets(Object scopesFailure) {
    return 'The list of Sites, Org Units, Assets and cost centres could not be read, so a scope cannot be chosen: $scopesFailure';
  }

  @override
  String get commonScope => 'Scope';

  @override
  String costRateFormWhich(Object value) {
    return 'Which $value';
  }

  @override
  String get costRateFormRateType => 'Rate type';

  @override
  String get costRateFormScopeAndRateType => 'Scope and rate type';

  @override
  String get costRateFormARateSScopeAndRateType =>
      'A rate\'s scope and rate type cannot be corrected — add a rate for the new scope instead';

  @override
  String get costRateFormMultiplier15ForTimeAndA =>
      'Multiplier (1.5 for time-and-a-half)';

  @override
  String get costRateFormAmountPerHour => 'Amount per hour';

  @override
  String get costRateFormTheNewAmountFromTheDateBelow =>
      'The new amount, from the date below';

  @override
  String get commonCurrency => 'Currency';

  @override
  String get commonAThreeLetterCodeSuchAsUsd =>
      'A three-letter code, such as USD';

  @override
  String get costRateFormNewRateTakesEffectOn => 'New rate takes effect on';

  @override
  String get commonTakesEffectOn => 'Takes effect on';

  @override
  String get costRateFormTheOldRateIsClosedOnThis =>
      'The old rate is closed on this day, and the new one starts';

  @override
  String get commonAppliesUntilOptional => 'Applies until (optional)';

  @override
  String get costRateFormLeftBlankThisRateIsTheCurrent =>
      'Left blank, this rate is the current one. Setting it closes the rate on that day, which is the exclusive end of the period.';

  @override
  String get costRatesTheCostRateCatalogueCouldNotBe =>
      'The cost rate catalogue could not be read';

  @override
  String get costRatesWhatAnHourCostsOneCatalogueShared =>
      'What an hour costs — one catalogue shared by every Site, and what the Cost numbers on the tier board are worked out from. A rate is never overwritten: it is closed, and a new one opened, so a cost reported for an earlier month stays what it was.';

  @override
  String get costRatesAddCostRate => 'Add cost rate';

  @override
  String get costRatesNoCostRatesYet => 'No cost rates yet';

  @override
  String get costRatesUntilARateIsSetEveryCost =>
      'Until a rate is set, every Cost number resolves to nothing.';

  @override
  String get costRatesRate => 'Rate';

  @override
  String get commonPeriod => 'Period';

  @override
  String get commonCorrect => 'Correct';

  @override
  String get commonRevise => 'Revise';

  @override
  String get commonClosed => 'Closed';

  @override
  String get directoryTheDirectoryCouldNotBeRead =>
      'The Directory could not be read';

  @override
  String get directoryNobodyMatchesThisSearch => 'Nobody matches this search';

  @override
  String get directoryTryADifferentNameOrClearA =>
      'Try a different name, or clear a filter.';

  @override
  String get directoryWhoWorksHereSearchedFilteredAndDeparted =>
      'Who works here — searched, filtered, and Departed Employees kept out of sight until asked for.';

  @override
  String get commonAddEmployee => 'Add Employee';

  @override
  String get directoryMyRecord => 'My record';

  @override
  String get directorySearchByName => 'Search by name';

  @override
  String get commonJobRole => 'Job role';

  @override
  String get directoryAllJobRoles => 'All job roles';

  @override
  String get directoryIncludeDeparted => 'Include Departed';

  @override
  String get commonEmployment => 'Employment';

  @override
  String get commonDeparted => 'Departed';

  @override
  String get commonActive => 'Active';

  @override
  String employeeAssignmentAssignToAnOrgUnit(Object displayName) {
    return 'Assign $displayName to an Org Unit';
  }

  @override
  String get employeeAssignmentWhereItWorksNow => 'Where it works now';

  @override
  String get employeeAssignmentJobRoleOptional => 'Job role (optional)';

  @override
  String get employeeAssignmentNoJobRole => 'No job role';

  @override
  String get employeeAssignmentEffectiveDate => 'Effective date';

  @override
  String employeeCorrectionCorrectSRecord(Object displayName) {
    return 'Correct $displayName\'s record';
  }

  @override
  String get commonFirstName => 'First name';

  @override
  String get commonLastName => 'Last name';

  @override
  String get commonEmploymentType => 'Employment type';

  @override
  String get commonWorkEmailOptional => 'Work email (optional)';

  @override
  String employeeDepartureRecordThatHasLeft(Object displayName) {
    return 'Record that $displayName has left';
  }

  @override
  String get employeeDepartureAccountStillLinked => 'Account still linked';

  @override
  String get employeeDepartureTheRecordStaysNothingIsDeletedAnd =>
      'The record stays — nothing is deleted, and this can be undone by reinstating the record at any time.';

  @override
  String get employeeDepartureEffectiveDateOptional =>
      'Effective date (optional)';

  @override
  String get commonLeftBlankTodayIsRecorded => 'Left blank, today is recorded.';

  @override
  String get employeeDepartureRecording => 'Recording…';

  @override
  String get commonRecordDeparture => 'Record departure';

  @override
  String employeeDepartureHasLeftAndTheirAccountCanStill(
    Object displayName,
    Object email,
  ) {
    return '$displayName has left, and their Account ($email) can still sign in. The departure is already recorded either way — deactivating the Account is a separate, optional step.';
  }

  @override
  String get employeeDepartureNotNow => 'Not now';

  @override
  String get employeeDepartureDeactivating => 'Deactivating…';

  @override
  String get employeeDepartureDeactivateAccount => 'Deactivate Account';

  @override
  String get employeeDetailThisRecordCouldNotBeRead =>
      'This record could not be read';

  @override
  String get employeeDetailAssignmentHistory => 'Assignment history';

  @override
  String get employeeDetailNoAssignmentHasBeenRecorded =>
      'No Assignment has been recorded.';

  @override
  String get employeeDetailRecordSkill => 'Record skill';

  @override
  String get employeeDetailNoQualificationsRecorded =>
      'No qualifications recorded.';

  @override
  String get employeeDetailHired => 'Hired';

  @override
  String get employeeDetailWorkEmail => 'Work email';

  @override
  String get commonCorrectRecord => 'Correct record';

  @override
  String get employeeDetailSignature => 'Signature';

  @override
  String get commonReinstate => 'Reinstate';

  @override
  String get employeeDetailCurrent => 'Current';

  @override
  String employeeDetailLapsed(Object name) {
    return '$name · Lapsed';
  }

  @override
  String get employeeDetailReAssess => 'Re-assess';

  @override
  String get commonAdding => 'Adding…';

  @override
  String employeeLinkPickerSuggestedMatch(Object value) {
    return 'Suggested match: $value';
  }

  @override
  String employeeLinkPickerLinkedTo(Object value) {
    return 'Linked to: $value';
  }

  @override
  String get commonRemove => 'Remove';

  @override
  String get employeeLinkPickerNoEmployeeWillBeLinked =>
      'No Employee will be linked.';

  @override
  String employeeSignatureNoSignatureIsKeptForUploadA(Object displayName) {
    return 'No Signature is kept for $displayName. Upload a picture of it, or draw it here.';
  }

  @override
  String get commonThisSignatureCouldNotBeShown =>
      'This Signature could not be shown.';

  @override
  String employeeSignatureSetForBy(Object displayName, Object who) {
    return 'Set for $displayName by $who';
  }

  @override
  String employeeSignatureSetBy(Object displayName) {
    return 'Set by $displayName';
  }

  @override
  String employeeSignatureSignatureOf(Object displayName) {
    return 'Signature of $displayName';
  }

  @override
  String get commonUploadAPicture => 'Upload a picture';

  @override
  String get commonReplaceWithAPicture => 'Replace with a picture';

  @override
  String get commonDrawIt => 'Draw it';

  @override
  String get commonDrawANewOne => 'Draw a new one';

  @override
  String get commonKeepThisSignature => 'Keep this Signature';

  @override
  String employeeSkillFormReAssessFor(Object value, Object displayName) {
    return 'Re-assess $value for $displayName';
  }

  @override
  String employeeSkillFormRecordASkillFor(Object displayName) {
    return 'Record a skill for $displayName';
  }

  @override
  String get employeeSkillFormSkill => 'Skill';

  @override
  String get employeeSkillFormProficiency04Iluo => 'Proficiency (0–4, ILUO)';

  @override
  String get employeeSkillForm0None => '0 — none';

  @override
  String get employeeSkillFormAssessedOnOptional => 'Assessed on (optional)';

  @override
  String get employeeSkillFormExpiresOnOptional => 'Expires on (optional)';

  @override
  String get employeeSkillFormLeftBlankNeverExpiresOrIsRe =>
      'Left blank, never expires (or is re-derived from the skill\'s own revalidation period).';

  @override
  String get employeeSkillFormEvidenceReferenceOptional =>
      'Evidence reference (optional)';

  @override
  String floorTrainingTrainingFor(Object employeeName) {
    return 'Training for $employeeName';
  }

  @override
  String get floorTrainingYourTraining => 'Your training';

  @override
  String get floorTrainingDone => 'Done';

  @override
  String get floorTrainingShowMyTraining => 'Show my training';

  @override
  String get floorTrainingWhoAreYouYourEmployeeNumberAnd =>
      'Who are you? Your Employee number and PIN show the training waiting on you at this device.';

  @override
  String get floorTrainingScanTheBadgeOrTypeTheNumber =>
      'Scan the badge or type the number.';

  @override
  String get floorTrainingNothingIsWaitingOnYouAtThis =>
      'Nothing is waiting on you at this device.';

  @override
  String get jobRoleFormCorrectJobRole => 'Correct job role';

  @override
  String get commonAddJobRole => 'Add job role';

  @override
  String get jobRolesTheJobRoleCatalogueCouldNotBe =>
      'The job role catalogue could not be read';

  @override
  String get jobRolesWhatAnEmployeeDoesDefinedOnceShared =>
      'What an Employee does — defined once, shared by every Site.';

  @override
  String get jobRolesNoJobRolesYet => 'No job roles yet';

  @override
  String get commonNothingHasBeenDefinedInTheCatalogue =>
      'Nothing has been defined in the catalogue.';

  @override
  String get jobRolesFilterJobRoles => 'Filter job roles';

  @override
  String get jobRolesByNameOrCode => 'By name or code.';

  @override
  String get jobRolesNoJobRolesMatch => 'No job roles match';

  @override
  String jobRolesNothingInTheCatalogueMatchesTryA(Object term) {
    return 'Nothing in the catalogue matches \"$term\". Try a different name or code, or clear the filter.';
  }

  @override
  String get leaveRequestCancelCancelLeaveRequest => 'Cancel leave request';

  @override
  String leaveRequestCancelCancelTheRequestFor(
    Object leaveTypeName,
    Object displayName,
    Object periodLabel,
    Object daysLabel,
  ) {
    return 'Cancel the $leaveTypeName request for $displayName, $periodLabel ($daysLabel)?';
  }

  @override
  String get leaveRequestCancelKeepRequest => 'Keep request';

  @override
  String get leaveRequestCancelCancelling => 'Cancelling…';

  @override
  String get commonCancelRequest => 'Cancel request';

  @override
  String get commonRequestLeave => 'Request leave';

  @override
  String get leaveRequestFormRequesting => 'Requesting…';

  @override
  String get leaveRequestFormLeaveTypesCouldNotBeRead =>
      'Leave types could not be read';

  @override
  String get leaveRequestFormLeaveType => 'Leave type';

  @override
  String get leaveRequestFormFirstDay => 'First day';

  @override
  String get leaveRequestFormLastDay => 'Last day';

  @override
  String get leaveRequestsLeaveRequestsCouldNotBeRead =>
      'Leave requests could not be read';

  @override
  String get leaveRequestsAskToBeAwayFromWorkAnd =>
      'Ask to be away from work, and follow what became of it.';

  @override
  String get leaveRequestsMine => 'Mine';

  @override
  String get leaveRequestsToDecide => 'To decide';

  @override
  String get leaveRequestsNoLeaveRequestsYet => 'No leave requests yet';

  @override
  String get leaveRequestsNothingToDecide => 'Nothing to decide';

  @override
  String get leaveRequestsRequestLeaveToAskForTimeAway =>
      'Request leave to ask for time away.';

  @override
  String get leaveRequestsNoPendingLeaveRequestsAreWaitingFor =>
      'No pending leave requests are waiting for you.';

  @override
  String leaveRequestsNote(Object note) {
    return 'Note: $note';
  }

  @override
  String leaveRequestsDecisionNote(Object decisionNote) {
    return 'Decision note: $decisionNote';
  }

  @override
  String get leaveRequestsApprove => 'Approve';

  @override
  String get mySignatureYourSignatureCouldNotBeRead =>
      'Your Signature could not be read';

  @override
  String get mySignatureNoSignatureKept => 'No Signature kept';

  @override
  String get mySignatureYouHaveNotKeptASignatureYet =>
      'You have not kept a Signature yet. Upload a picture of it, or draw it here.';

  @override
  String get mySignatureYourSignature => 'Your Signature';

  @override
  String get mySignatureYourOwnMarkKeptOnceAndApplied =>
      'Your own mark, kept once and applied wherever you would otherwise sign a sheet by hand. Replacing it never changes a sheet you have already signed.';

  @override
  String get mySignatureDrawYourSignature => 'Draw your Signature';

  @override
  String get commonAddRootOrgUnit => 'Add root Org Unit';

  @override
  String get orgUnitFormAddOrgUnit => 'Add Org Unit';

  @override
  String get orgUnitFormUnitType => 'Unit type';

  @override
  String get orgUnitFormSortOrderOptional => 'Sort order (optional)';

  @override
  String get commonImportABranch => 'Import a branch';

  @override
  String get orgUnitImportImporting => 'Importing…';

  @override
  String get orgUnitImportImport => 'Import';

  @override
  String get orgUnitImportAJsonArrayOfRowsEachRow =>
      'A JSON array of rows. Each row references its own parent by \"parentCode\" — another row in this same array, or an existing code at this Site — never by id.';

  @override
  String orgUnitImportRow(
    String row,
    String code,
    String field,
    String message,
  ) {
    return 'Row $row$code$field: $message';
  }

  @override
  String get orgUnitPickerOrgUnitGrants => 'Org Unit Grants';

  @override
  String get orgUnitPickerEverythingOnTheRightIsWhatThis =>
      'Everything on the right is what this Account will hold. Nothing is added to what it has now — this is the whole set.';

  @override
  String get orgUnitPickerQualityAuthorityAndSafetyAuthorityAreEach =>
      'Quality authority and Safety authority are each separate from the level and from each other — a view-only Grant may carry either, and an edit Grant need not — and each reaches everything beneath the Org Unit it is given on.';

  @override
  String get orgUnitPickerBrowse => 'Browse';

  @override
  String get orgUnitPickerGranted => 'Granted';

  @override
  String get orgUnitPickerGrantThisOrgUnit => 'Grant this Org Unit';

  @override
  String get orgUnitPickerNothingBeneathThis => 'Nothing beneath this';

  @override
  String orgUnitPickerGranted2(Object length) {
    return 'Granted ($length)';
  }

  @override
  String get orgUnitPickerNoOrgUnitsGrantedThisAccountWill =>
      'No Org Units granted. This Account will be able to sign in but not act anywhere.';

  @override
  String get orgUnitPickerQualityAuthority => 'Quality authority';

  @override
  String get orgUnitPickerSafetyAuthority => 'Safety authority';

  @override
  String get orgUnitPickerRemoveThisGrant => 'Remove this Grant';

  @override
  String get orgUnitsASiteSOwnShapeWhereA =>
      'A Site\'s own shape — where a KPI is measured, an Account is granted, and an Asset sits.';

  @override
  String get commonAddSite => 'Add Site';

  @override
  String get commonEditSite => 'Edit Site';

  @override
  String get orgUnitsTheSitesCouldNotBeRead => 'The Sites could not be read';

  @override
  String get orgUnitsThereAreNoSitesYet => 'There are no Sites yet.';

  @override
  String get orgUnitsAnAdministratorAddsTheFirstSiteEvery =>
      'An administrator adds the first Site; every Org Unit sits beneath one.';

  @override
  String get orgUnitsFindAnOrgUnitByName => 'Find an Org Unit by name';

  @override
  String get orgUnitsPickingOneRevealsAndSelectsItIn =>
      'Picking one reveals and selects it in the tree below.';

  @override
  String get orgUnitsRetired => 'Retired';

  @override
  String get orgUnitsTheOrgUnitTreeCouldNotBe =>
      'The Org Unit tree could not be read';

  @override
  String get orgUnitsNothingToBrowseInThisSiteYet =>
      'Nothing to browse in this Site yet.';

  @override
  String get orgUnitsAnAdministratorAddsTheFirstOrgUnit =>
      'An administrator adds the first Org Unit, or imports a branch.';

  @override
  String orgUnitsBelow(Object childCount) {
    return '$childCount below';
  }

  @override
  String get orgUnitsAddAnOrgUnitHere => 'Add an Org Unit here';

  @override
  String get orgUnitsRetire => 'Retire';

  @override
  String get orgUnitsRetireThisOrgUnit => 'Retire this Org Unit?';

  @override
  String orgUnitsWillReadAsRetiredRatherThanDeleted(Object name) {
    return '$name will read as retired rather than deleted, and can be reinstated at any time.';
  }

  @override
  String get productCostFormTheCostBelowIsClosedOnThe =>
      'The cost below is closed on the day the new one takes effect. It stays readable, and scrap already costed at it keeps that figure.';

  @override
  String productCostFormTheProductListCouldNotBeRead(Object productsFailure) {
    return 'The Product list could not be read, so a Product cannot be chosen: $productsFailure';
  }

  @override
  String get productCostFormTheProductAStandardCostBelongsTo =>
      'The Product a standard cost belongs to cannot be corrected — record a cost against the other Product instead';

  @override
  String get productCostFormStandardCostPerUnit => 'Standard cost, per unit';

  @override
  String get productCostFormTheNewCostFromTheDateBelow =>
      'The new cost, from the date below';

  @override
  String get productCostFormNewCostTakesEffectOn => 'New cost takes effect on';

  @override
  String get productCostFormTheOldCostIsClosedOnThis =>
      'The old cost is closed on this day, and the new one starts';

  @override
  String get productCostFormLeftBlankThisCostIsTheCurrent =>
      'Left blank, this cost is the current one. Setting it closes the cost on that day, which is the exclusive end of the period.';

  @override
  String get productCostsTheStandardCostCatalogueCouldNotBe =>
      'The standard cost catalogue could not be read';

  @override
  String get productCostsWhatAUnitIsCostedAtOne =>
      'What a unit is costed at — one catalogue shared by every Site, and what scrap and rework are priced with. A cost is never overwritten: it is closed, and a new one opened, so a cost reported for an earlier month stays what it was.';

  @override
  String get productCostsAddStandardCost => 'Add standard cost';

  @override
  String get productCostsNoStandardCostsYet => 'No standard costs yet';

  @override
  String get productCostsUntilACostIsSetScrapAnd =>
      'Until a cost is set, scrap and rework are priced at nothing.';

  @override
  String get roleFormCorrectRole => 'Correct role';

  @override
  String get commonAddRole => 'Add role';

  @override
  String get roleForm330CharactersAZ09 =>
      '3–30 characters: A–Z, 0–9 and underscore, e.g. ROLE_STORE_ROOM';

  @override
  String get roleFormWhatItIsFor => 'What it is for';

  @override
  String get roleFormInActiveUse => 'In active use';

  @override
  String get roleFormARetiredRoleKeepsItsHistoryAnd =>
      'A retired role keeps its history and can be assigned to nobody.';

  @override
  String rolePermissionsWhatCarries(Object code) {
    return 'What $code carries';
  }

  @override
  String rolePermissionsOfPermissions(Object length, Object total) {
    return '$length of $total permissions';
  }

  @override
  String get rolesTheRolesCouldNotBeRead => 'The roles could not be read';

  @override
  String get rolesWhatAnAccountMayDoEachRole =>
      'What an Account may do. Each role is a group of permissions; every Account holds the default group, and a role marked automatic is earned by the Account\'s own role.';

  @override
  String get rolesNoRoles => 'No roles';

  @override
  String get rolesNothingIsCarryingAPermissionThatShould =>
      'Nothing is carrying a permission. That should not happen: the seed creates the default group, so this means the deployment is incomplete.';

  @override
  String get rolesDefaultGroup => 'Default group';

  @override
  String rolesAutomatic(Object legacyRole) {
    return 'Automatic: $legacyRole';
  }

  @override
  String rolesReaches(int length, int holderCount) {
    String _temp0 = intl.Intl.pluralLogic(
      length,
      locale: localeName,
      other: '$length permissions',
      one: '1 permission',
    );
    String _temp1 = intl.Intl.pluralLogic(
      holderCount,
      locale: localeName,
      other: '$holderCount Accounts',
      one: '1 Account',
    );
    return '$_temp0 · reaches $_temp1';
  }

  @override
  String get rolesPermissions => 'Permissions';

  @override
  String get siteFormTimezonesUnavailable => 'Timezones unavailable';

  @override
  String get siteFormTheTimezoneListCouldNotBeLoaded =>
      'The timezone list could not be loaded.';

  @override
  String get siteFormTimezone => 'Timezone';

  @override
  String get siteFormCountryCodeOptional => 'Country code (optional)';

  @override
  String get skillCoverageOrgUnitAndSkill => 'Org Unit and skill';

  @override
  String get skillCoverageRequired => 'Required';

  @override
  String get skillCoverageQualified => 'Qualified';

  @override
  String get skillCoverageLapsed => 'Lapsed';

  @override
  String get skillCoverageShortfall => 'Shortfall';

  @override
  String get skillCoverageSkillCoverageCouldNotBeRead =>
      'Skill coverage could not be read';

  @override
  String get skillCoverageWhereThisSiteFallsShortOfIts =>
      'Where this Site falls short of its own skill requirements.';

  @override
  String get skillCoverageEveryRequirementIsMet => 'Every requirement is met';

  @override
  String get skillCoverageThisSiteHasNoShortfallAgainstThe =>
      'This Site has no shortfall against the skill requirements it has set for itself.';

  @override
  String get skillCoverageFilterSkillCoverage => 'Filter skill coverage';

  @override
  String get skillCoverageByOrgUnitOrSkill => 'By Org Unit or skill.';

  @override
  String get skillCoverageNoShortfallsMatch => 'No shortfalls match';

  @override
  String skillCoverageThisSiteIsShortSomewhereButNothing(Object term) {
    return 'This Site is short somewhere, but nothing matches \"$term\". Try a different Org Unit or skill, or clear the filter.';
  }

  @override
  String skillCoverageNeedsAtLevel(
    Object minimumQualifiedHeadcount,
    Object minimumLevel,
  ) {
    return 'Needs $minimumQualifiedHeadcount at level $minimumLevel+';
  }

  @override
  String skillCoverageNeedsAtLevelQualifiedLapsed(
    Object minimumQualifiedHeadcount,
    Object minimumLevel,
    Object qualifiedHeadcount,
    Object expiredHeadcount,
  ) {
    return 'Needs $minimumQualifiedHeadcount at level $minimumLevel+, $qualifiedHeadcount qualified, $expiredHeadcount lapsed';
  }

  @override
  String skillCoverageShort(Object shortfall) {
    return 'Short $shortfall';
  }

  @override
  String get skillFormCorrectSkill => 'Correct skill';

  @override
  String get commonAddSkill => 'Add skill';

  @override
  String get skillFormRequiresCertification => 'Requires certification';

  @override
  String get skillFormRevalidationPeriodInMonthsOptional =>
      'Revalidation period, in months (optional)';

  @override
  String get skillFormLeftBlankThisSkillNeverNeedsRevalidating =>
      'Left blank, this skill never needs revalidating.';

  @override
  String skillQualifiedEmployeesWhoHolds(Object name) {
    return 'Who holds $name';
  }

  @override
  String get skillQualifiedEmployeesScopedTo => 'Scoped to';

  @override
  String get skillQualifiedEmployeesMinimumProficiency => 'Minimum proficiency';

  @override
  String get skillQualifiedEmployeesSearch => 'Search';

  @override
  String get skillQualifiedEmployeesChooseAnOrgUnitThenSearch =>
      'Choose an Org Unit, then search.';

  @override
  String get skillQualifiedEmployeesNobodyCurrentlyQualifiesAtThisOrgUnit =>
      'Nobody currently qualifies at this Org Unit.';

  @override
  String skillQualifiedEmployeesLevel(Object proficiencyLevel) {
    return 'Level $proficiencyLevel';
  }

  @override
  String get skillsTheSkillCatalogueCouldNotBeRead =>
      'The skill catalogue could not be read';

  @override
  String get skillsWhatThePlantQualifiesAnEmployeeTo =>
      'What the plant qualifies an Employee to do — defined once, shared by every Site.';

  @override
  String get skillsNoSkillsYet => 'No skills yet';

  @override
  String get skillsFilterSkills => 'Filter skills';

  @override
  String get skillsByNameCodeOrCategory => 'By name, code or category.';

  @override
  String get skillsNoSkillsMatch => 'No skills match';

  @override
  String skillsNothingInTheCatalogueMatchesTryA(Object term) {
    return 'Nothing in the catalogue matches \"$term\". Try a different name, code or category, or clear the filter.';
  }

  @override
  String get skillsWhoHoldsThis => 'Who holds this';

  @override
  String get trainingAnswerSignYourConfirmation => 'Sign your confirmation';

  @override
  String get trainingAnswerChooseWhatYourAnswerIsSignedWith =>
      'Choose what your answer is signed with. You can also confirm without a Signature.';

  @override
  String get trainingAnswerYouKeepNoSignatureDrawOneNow =>
      'You keep no Signature. Draw one now for this answer, or confirm without a Signature.';

  @override
  String get trainingAnswerYourSignatureWhichUseMySignatureApplies =>
      'Your Signature, which \"Use my Signature\" applies:';

  @override
  String get trainingAnswerUseMySignature => 'Use my Signature';

  @override
  String get trainingAnswerDrawOneNow => 'Draw one now';

  @override
  String get trainingAnswerNoSignature => 'No Signature';

  @override
  String get trainingAnswerConfirmWithThisSignature =>
      'Confirm with this Signature';

  @override
  String get commonNoSuchTrainingRecord => 'No such Training record';

  @override
  String get commonBackToTrainingRecords => 'Back to Training records';

  @override
  String get trainingDetailTheTrainingRecordCouldNotBeRead =>
      'The Training record could not be read';

  @override
  String get trainingDetailTheForm => 'The form';

  @override
  String get trainingDetailTheTraining => 'The training';

  @override
  String get commonTrainedOn => 'Trained on';

  @override
  String get trainingDetailDuration => 'Duration';

  @override
  String get trainingDetailTrainer => 'Trainer';

  @override
  String get trainingDetailObjective => 'Objective';

  @override
  String trainingDetailTrainees(Object traineeCount) {
    return 'Trainees ($traineeCount)';
  }

  @override
  String get commonAddTrainee => 'Add Trainee';

  @override
  String get trainingDetailNoTraineesAreOnThisTrainingRecord =>
      'No Trainees are on this Training record yet.';

  @override
  String get trainingDetailSendToTrainees => 'Send to Trainees';

  @override
  String get trainingDetailDiscardDraft => 'Discard draft';

  @override
  String trainingDetailEvaluated(Object value) {
    return 'Evaluated: $value';
  }

  @override
  String trainingDetailRemove(Object employeeName) {
    return 'Remove $employeeName';
  }

  @override
  String get trainingDetailDiscardThisDraft => 'Discard this draft?';

  @override
  String get trainingDetailTheDraftAndTheTraineesListedOn =>
      'The draft and the Trainees listed on it will be deleted, and it cannot be brought back. Nobody has been asked about it yet.';

  @override
  String get trainingDetailDiscard => 'Discard';

  @override
  String get commonEvaluation => 'Evaluation';

  @override
  String get trainingFormThatTrainingFormCouldNotBeRead =>
      'That training form could not be read';

  @override
  String get trainingFormTrainingRecord => 'Training Record';

  @override
  String get trainingFormBiNBNGhiNhN => 'Biên bản ghi nhận đào tạo';

  @override
  String get trainingFormAttendanceListDanhSChThamGia =>
      'Attendance list/ danh sách tham gia :';

  @override
  String get trainingRaiseCorrectTrainingRecord => 'Correct training record';

  @override
  String get commonRaiseTrainingRecord => 'Raise training record';

  @override
  String get trainingRaiseCorrecting => 'Correcting…';

  @override
  String get trainingRaiseRaising => 'Raising…';

  @override
  String get trainingRaiseTitle => 'Title';

  @override
  String get trainingRaiseWhatTheTrainingWas => 'What the training was.';

  @override
  String get trainingRaiseTheDayItWasGiven => 'The day it was given.';

  @override
  String get trainingRaiseDurationHours => 'Duration (hours)';

  @override
  String get trainingRaiseHowLongItLastedEG1 => 'How long it lasted, e.g. 1.5.';

  @override
  String get trainingRaiseTrainerOptional => 'Trainer (optional)';

  @override
  String get trainingRaiseWhoGaveItFoundInTheDirectory =>
      'Who gave it, found in the Directory.';

  @override
  String get trainingRaiseObjectiveOptional => 'Objective (optional)';

  @override
  String get trainingRaiseWhatTheTrainingSetOutToTeach =>
      'What the training set out to teach.';

  @override
  String get trainingRecord => 'Record';

  @override
  String get trainingTrainees => 'Trainees';

  @override
  String get trainingAnswers => 'Answers';

  @override
  String get trainingTrainingRecordsCouldNotBeRead =>
      'Training records could not be read';

  @override
  String get trainingNoTrainingRecordsMatch => 'No Training records match';

  @override
  String get trainingNothingWasTrainedUnderThatOrgUnit =>
      'Nothing was trained under that Org Unit in those days.';

  @override
  String get trainingNoTrainingRecordsYet => 'No Training records yet';

  @override
  String get trainingRaiseATrainingRecordToStartThe =>
      'Raise a Training record to start the register.';

  @override
  String get trainingNothingHasBeenRecordedAsTrainedYet =>
      'Nothing has been recorded as trained yet.';

  @override
  String get trainingWhatThePlantHasTrainedPeopleOn =>
      'What the plant has trained people on, and when.';

  @override
  String get trainingThereAreMoreTrainingRecordsThanThis =>
      'There are more Training records than this list shows. Narrow it by Org Unit or by dates to see the rest.';

  @override
  String trainingTheFormFor(Object number) {
    return 'The form for $number';
  }

  @override
  String get trainingToConfirmYourTrainingToConfirmCouldNotBe =>
      'Your Training to confirm could not be read';

  @override
  String get trainingToConfirmNothingWaitingOnYou => 'Nothing waiting on you';

  @override
  String get trainingToConfirmNoTrainingRecordHasBeenSentTo =>
      'No Training record has been sent to you that you have not answered.';

  @override
  String get trainingToConfirmTrainingRecordsSentToYouThatYou =>
      'Training records sent to you that you have not answered yet, oldest first. Confirm that you attended, or decline because the record is wrong.';

  @override
  String get trainingToConfirmYourAnswer => 'Your answer';

  @override
  String trainingTraineeEmployeesOf(Object orgUnitName) {
    return 'Employees of $orgUnitName';
  }

  @override
  String get trainingTraineeWholeDirectory => 'Whole Directory';

  @override
  String get trainingTraineeAnyoneInTheDirectoryFoundByName =>
      'Anyone in the Directory, found by name or number.';

  @override
  String trainingTraineeAnEmployeeOfFoundByNameOr(Object orgUnitName) {
    return 'An Employee of $orgUnitName, found by name or number.';
  }

  @override
  String get workedHoursDay => 'Day';

  @override
  String get workedHoursWorked => 'Worked';

  @override
  String get workedHoursBackToEmployee => 'Back to Employee';

  @override
  String get workedHoursTheConfirmedHoursThisEmployeeActuallyWorked =>
      'The confirmed hours this Employee actually worked, day by day. Only confirmed attendance counts — an unconfirmed sheet is a draft.';

  @override
  String get workedHoursTheWorkedHoursSummaryCouldNotBe =>
      'The worked-hours summary could not be read';

  @override
  String get workedHoursNoConfirmedWorkedHoursInThisWindow =>
      'No confirmed worked hours in this window.';

  @override
  String get workedHoursWidenTheWindowOrConfirmTheShift =>
      'Widen the window, or confirm the shift sheets for the days this Employee worked.';

  @override
  String get workedHoursTotals => 'Totals';

  @override
  String workedHoursOfScheduled(Object value) {
    return 'of $value scheduled';
  }

  @override
  String get leaveRequestDecisionApproveLeaveRequest => 'Approve leave request';

  @override
  String get leaveRequestDecisionRejectLeaveRequest => 'Reject leave request';

  @override
  String get commonTo => 'To';

  @override
  String get commonEmployeeNumber => 'Employee number';

  @override
  String get commonPin => 'PIN';

  @override
  String get commonInactive => 'Inactive';

  @override
  String get commonDeactivate => 'Deactivate';

  @override
  String get commonReactivate => 'Reactivate';

  @override
  String get commonClose => 'Close';

  @override
  String get commonReason => 'Reason';

  @override
  String get commonAssign => 'Assign';

  @override
  String get commonDecline => 'Decline';

  @override
  String get commonOvertime => 'Overtime';

  @override
  String get commonSessionEnded =>
      'This session has ended. Sign in again to continue.';

  @override
  String get attendanceRecordChooseAReasonForThisAbsence =>
      'Choose a reason for this absence.';

  @override
  String get commonThatActionCouldNotBeRead => 'That Action could not be read';

  @override
  String get commonThatActionHasEnded => 'That Action has ended';

  @override
  String get commonDone => 'done';

  @override
  String get actionCancelItIsClosedSoThereIsNothing =>
      'It is closed, so there is nothing left to call off.';

  @override
  String get actionCancelItWasAlreadyCancelled => 'It was already cancelled.';

  @override
  String actionCancelCallOff(Object actionNo) {
    return 'Call off $actionNo?';
  }

  @override
  String get actionCancelLeaveItAlone => 'Leave it alone';

  @override
  String get actionCancelCallItOff => 'Call it off';

  @override
  String get actionCancelCallingItOffEndsTheRecordWithout =>
      'Calling it off ends the record without claiming anything was done about it. The row stays, with the reason you give it.';

  @override
  String get actionCancelWhyOptional => 'Why (optional)';

  @override
  String get actionCancelRaisedInErrorADuplicateOvertakenBy =>
      'Raised in error, a duplicate, overtaken by events.';

  @override
  String get commonBackToTheActionLog => 'Back to the action log';

  @override
  String get actionDetailHandItUp => 'Hand it up…';

  @override
  String get actionDetailCallItOff => 'Call it off…';

  @override
  String get actionDetailWhereItStands => 'Where it stands';

  @override
  String get commonOwner => 'Owner';

  @override
  String get actionDetailEscalatedTo => 'Escalated to';

  @override
  String get actionDetailClosingNote => 'Closing note';

  @override
  String actionDetailPillar(Object pillarCode) {
    return 'Pillar $pillarCode';
  }

  @override
  String commonOverdueByDays(Object daysOverdue) {
    return 'Overdue by $daysOverdue days';
  }

  @override
  String actionDetailCycle(Object currentCycle) {
    return 'Cycle $currentCycle';
  }

  @override
  String actionDetailCompleteThe(Object phaseLabel) {
    return 'Complete the $phaseLabel';
  }

  @override
  String get actionDetailThisActionHasNoPhasesLeft =>
      'This Action has no phases left.';

  @override
  String get actionDetailEarlierRounds => 'Earlier rounds';

  @override
  String get actionDetailOpenWaitingOnThis => 'Open — waiting on this';

  @override
  String get actionDetailNoNoteRecorded => 'No note recorded';

  @override
  String actionDetailDue(Object dueDate) {
    return 'due $dueDate';
  }

  @override
  String actionDetailDone(Object value) {
    return 'done $value';
  }

  @override
  String actionDetailAnswers(Object actionNo) {
    return 'Answers $actionNo';
  }

  @override
  String get commonCapa => 'CAPA';

  @override
  String get actionDetailAFormal8dInvestigationOpenedOnThis =>
      'A formal 8D investigation opened on this Concern: its team, its problem description and — as those slices land — its root causes and its effectiveness check. Its actions are the ones below, recorded once in the action log and read there.';

  @override
  String actionDetailUnderInvestigation(Object capaNo) {
    return 'Under investigation: $capaNo';
  }

  @override
  String get actionDetailOpenACapa => 'Open a CAPA…';

  @override
  String get actionDetailNobodyHasOpenedACapaOnThis =>
      'Nobody has opened a CAPA on this Concern. Opening one needs Quality authority at this Concern\'s Org Unit.';

  @override
  String get actionDetailMeasures => 'Measures';

  @override
  String actionDetailMeasuresOfThemCountermeasures(
    Object length,
    Object countermeasureCount,
  ) {
    return 'Measures ($length, $countermeasureCount of them countermeasures)';
  }

  @override
  String get actionDetailAddAMeasure => 'Add a measure';

  @override
  String actionDetailAddA(Object value) {
    return 'Add a $value…';
  }

  @override
  String get actionDetailEachMeasureIsAnActionOfIts =>
      'Each measure is an Action of its own: open one and run its own cycle to its Act, and it counts as closed.';

  @override
  String get actionDetailThisActionAnswersNoConcernOfIts =>
      'This Action answers no Concern of its own.';

  @override
  String get actionDetailNothingAnswersThisYetAContainmentStops =>
      'Nothing answers this yet. A containment stops the effect now; a countermeasure removes the cause.';

  @override
  String get commonNobodyYet => 'Nobody yet';

  @override
  String actionDetailOverdueByDays(Object daysOverdue) {
    return 'overdue by $daysOverdue days';
  }

  @override
  String commonWaitingOnIts(Object value) {
    return 'waiting on its $value';
  }

  @override
  String actionDetailCompleteThe2(Object value) {
    return 'Complete the $value…';
  }

  @override
  String actionDetailNonConformances(Object length) {
    return 'Non-conformances ($length)';
  }

  @override
  String get actionDetailTheOccurrencesThisConcernAnswersOneProblem =>
      'The occurrences this Concern answers. One problem that shows up several times stays one Concern, so a further occurrence is linked here rather than raised as another.';

  @override
  String get actionDetailNoNonConformanceIsLinkedToThis =>
      'No Non-conformance is linked to this Concern.';

  @override
  String get actionDetailRaisedFromThis => 'Raised from this';

  @override
  String get actionDetailUnlink => 'Unlink…';

  @override
  String get actionDetailTheObservationThisActionWasRaisedFrom =>
      'The observation this Action was raised from — what was seen, and how bad it could have been.';

  @override
  String get actionDetailTheIncidentThisConcernWasRaisedFrom =>
      'The incident this Concern was raised from — its number and its severity, never who was hurt or their diagnosis.';

  @override
  String get actionEscalateItIsClosedWhoeverNeededToKnow =>
      'It is closed. Whoever needed to know about it was told before it was.';

  @override
  String get actionEscalateItWasCalledOffSoThereIs =>
      'It was called off, so there is nothing to hand up.';

  @override
  String get actionEscalateNowhereToHandItUpTo => 'Nowhere to hand it up to';

  @override
  String get actionEscalateThereIsNobodyAboveThis =>
      'There is nobody above this';

  @override
  String actionEscalateSitsAtWhichIsAlreadyTheTop(
    Object actionNo,
    Object orgUnitName,
  ) {
    return '$actionNo sits at $orgUnitName, which is already the top of this Site. Nothing above it can be told.';
  }

  @override
  String actionEscalateHandUp(Object actionNo) {
    return 'Hand $actionNo up';
  }

  @override
  String get actionEscalateHandItUp => 'Hand it up';

  @override
  String get actionEscalateRaisingThisTellsTheOrgUnitYou =>
      'Raising this tells the Org Unit you choose. It stays where it is and keeps its owner and its cycle — this asks somebody above to know about it, not to take it over.';

  @override
  String actionEscalateNearestAboveIt(Object code) {
    return '$code · nearest above it';
  }

  @override
  String get actionEscalatedToFilterFilterByWhatWasHandedUp =>
      'Filter by what was handed up';

  @override
  String get actionEscalatedToFilterAnyone => 'Anyone';

  @override
  String get actionEscalatedToFilterWhoseQueue => 'Whose queue';

  @override
  String get actionEscalatedToFilterChooseTheOrgUnitThatConcernsWere =>
      'Choose the Org Unit that concerns were handed up to — what is waiting on the area, not what sits at the line — or clear back to everything.';

  @override
  String get commonRaiseAConcern => 'Raise a concern';

  @override
  String get actionFormRaiseIt => 'Raise it';

  @override
  String get actionFormOneLineTheCauseGoesInThe =>
      'One line. The cause goes in the Plan phase, not here.';

  @override
  String get commonKindOfAction => 'Kind of Action';

  @override
  String get actionFormThePillarCatalogueCouldNotBeRead =>
      'The Pillar catalogue could not be read, so no Pillar can be chosen.';

  @override
  String get actionFormPillarOptional => 'Pillar (optional)';

  @override
  String get actionFormWhichSqdcpNumberDoesThisThreaten =>
      'Which SQDCP number does this threaten?';

  @override
  String get actionFormNoPillar => 'No Pillar';

  @override
  String get commonOwnerOptional => 'Owner (optional)';

  @override
  String get actionFormWhoWillDoItAnActionNobody =>
      'Who will do it. An Action nobody owns is visibly nobody\'s.';

  @override
  String get commonDueOptional => 'Due (optional)';

  @override
  String get actionFormChooseTheOrgUnitThisConcernIs =>
      'Choose the Org Unit this concern is about. This is what decides who may act on it.';

  @override
  String actionFormThisConcernWillBeRecordedAt(Object value) {
    return 'This concern will be recorded at $value.';
  }

  @override
  String actionMeasureAddA(Object value) {
    return 'Add a $value';
  }

  @override
  String actionMeasureAddThe(Object value) {
    return 'Add the $value';
  }

  @override
  String actionMeasureAnswering(Object actionNo, Object title) {
    return 'Answering $actionNo: $title';
  }

  @override
  String get actionMeasureWhatWillBeDone => 'What will be done';

  @override
  String get actionMeasureWhoWillDoIt => 'Who will do it.';

  @override
  String get actionMeasureWhereThisWorkHappens => 'Where this work happens';

  @override
  String actionMeasureLeaveItAloneToRecordTheMeasure(Object orgUnitName) {
    return 'Leave it alone to record the measure at $orgUnitName, where the concern sits. A fix that belongs somewhere else — a store, a supplier — can name that instead.';
  }

  @override
  String get actionOrgUnitFilterNarrowTheLog => 'Narrow the log';

  @override
  String get actionOrgUnitFilterChooseTheOrgUnitWhoseActionsAnd =>
      'Choose the Org Unit whose Actions and everything beneath it you want to read, or clear back to the whole Site.';

  @override
  String get actionPhaseCompleteThatIsNotTheOpenPhase =>
      'That is not the open phase';

  @override
  String get actionPhaseCompleteThisActionHasNoOpenPhaseLeft =>
      'This Action has no open phase left.';

  @override
  String actionPhaseCompleteThisActionIsWaitingOnItsPhase(
    Object value,
    Object value2,
  ) {
    return 'This Action is waiting on its $value phase, not its $value2.';
  }

  @override
  String get actionPhaseCompletePlanProse =>
      'What will be different, and how you will know. The target belongs here, in the plant\'s own words.';

  @override
  String get actionPhaseCompleteDoProse => 'What was actually done.';

  @override
  String get actionPhaseCompleteCheckProse =>
      'What was measured, against what the Plan named.';

  @override
  String get actionPhaseCompleteActProse =>
      'Which standard now holds it, so the fix outlives the person who made it.';

  @override
  String actionPhaseCompleteCompleteThe(Object label) {
    return 'Complete the $label';
  }

  @override
  String get actionPhaseCompleteWhatWasMeasured => 'What was measured';

  @override
  String get actionPhaseCompleteWhatWasDone => 'What was done';

  @override
  String get actionPhaseCompleteDidItHold => 'Did it hold?';

  @override
  String get actionPhaseCompleteAnsweringThatItDidNotOpensThe =>
      'Answering that it did not opens the next cycle rather than closing the Action, and keeps this round on the record.';

  @override
  String get actionUnlinkNonconformanceThatConcernCouldNotBeRead =>
      'That Concern could not be read';

  @override
  String get actionUnlinkNonconformanceThatNonConformanceIsNotLinkedHere =>
      'That Non-conformance is not linked here';

  @override
  String get actionUnlinkNonconformanceThisConcernAnswersNothingByThatId =>
      'This Concern answers nothing by that id. It may have been unlinked already, or the address may be wrong.';

  @override
  String get actionUnlinkNonconformanceBackToTheConcern =>
      'Back to the Concern';

  @override
  String get actionUnlinkNonconformanceUnlinkThisNonConformance =>
      'Unlink this Non-conformance';

  @override
  String get actionUnlinkNonconformanceKeepItLinked => 'Keep it linked';

  @override
  String get actionUnlinkNonconformanceUnlinkIt => 'Unlink it';

  @override
  String get actionUnlinkNonconformanceItStopsBeingOneOfTheOccurrences =>
      'It stops being one of the occurrences this Concern answers. The Non-conformance itself is untouched — it keeps its number, its Dispositions and its quantity.';

  @override
  String get actionsTheActionLogCouldNotBeRead =>
      'The action log could not be read';

  @override
  String get actionsWhatThePlantOwesAtThisSite =>
      'What the plant owes at this Site: what was found, who owns it, and when it is due. Overdue first.';

  @override
  String get actionsEscalatedToAnyone => 'Escalated to anyone';

  @override
  String actionsEscalatedTo(Object escalatedToOrgUnitFilterName) {
    return 'Escalated to $escalatedToOrgUnitFilterName';
  }

  @override
  String get actionsEveryKind => 'Every kind';

  @override
  String get actionsShowClosed => 'Show closed';

  @override
  String get actionsThereAreMoreActionsThanThisList =>
      'There are more Actions than this list shows. Narrow it by Org Unit, by status or by kind to see the rest.';

  @override
  String get actionsTheLogHasActionsButNoneOf =>
      'The log has Actions, but none of them is in the Org Unit, status or kind you picked.';

  @override
  String get actionsNothingOnTheLog => 'Nothing on the log';

  @override
  String get actionsNoActionHasBeenRaisedAtThis =>
      'No Action has been raised at this Site yet.';

  @override
  String get actionsSourceRaisedHere => 'Raised here';

  @override
  String get actionsSource => 'Source';

  @override
  String actionsOfThemCountermeasures(
    int measureCount,
    int countermeasureCount,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      measureCount,
      locale: localeName,
      other: '$measureCount measures',
      one: '1 measure',
    );
    return '$_temp0, $countermeasureCount of them countermeasures';
  }

  @override
  String actionsEscalatedTo2(Object escalatedToOrgUnitName) {
    return 'Escalated to $escalatedToOrgUnitName';
  }

  @override
  String get actionsNoDueDate => 'No due date';

  @override
  String actionsDue(Object dueDate) {
    return 'Due $dueDate';
  }

  @override
  String get commonBackToTheCapa => 'Back to the CAPA';

  @override
  String get commonThatCapaCouldNotBeRead => 'That CAPA could not be read';

  @override
  String get capaCauseThatIsNotA6mCategory => 'That is not a 6M category';

  @override
  String get capaCauseAFishboneHasSixBonesManMachine =>
      'A fishbone has six bones: Man, Machine, Method, Material, Measurement and Environment.';

  @override
  String get commonThisInvestigationIsOver => 'This investigation is over';

  @override
  String capaCauseIsSoItsFishboneIsARecord(Object capaNo, Object value) {
    return '$capaNo is $value, so its fishbone is a record rather than a worklist.';
  }

  @override
  String get commonNotYoursToWrite => 'Not yours to write';

  @override
  String get commonWritingACapaSRootCausesNeeds =>
      'Writing a CAPA\'s root causes needs edit access at its Org Unit, or a place on its team.';

  @override
  String get capaCauseThatCauseIsNotOnThisBone =>
      'That cause is not on this bone';

  @override
  String get commonItMayHaveBeenRemovedAMoment =>
      'It may have been removed a moment ago by somebody else.';

  @override
  String capaCauseSomethingThatCouldBeBehind(Object categoryLabel) {
    return '$categoryLabel — something that could be behind the problem.';
  }

  @override
  String get capaCauseRecordIt => 'Record it';

  @override
  String get capaCauseWhatItSaysAndWhichOfTheSix =>
      'What it says, and which of the six it is filed under.';

  @override
  String get capaCauseSaveIt => 'Save it';

  @override
  String get capaCauseRecordACandidateCause => 'Record a candidate cause';

  @override
  String get capaCauseReviseTheCause => 'Revise the cause';

  @override
  String get capaCauseRemoveThisCause => 'Remove this cause?';

  @override
  String get commonRemoveIt => 'Remove it';

  @override
  String capaCauseItIsTakenOffTheBoneFor(Object categoryLabel, Object value) {
    return 'It is taken off the $categoryLabel bone for good$value. A chain started from it keeps the Why it began with.';
  }

  @override
  String get capaCauseBothChainsHaveBeenStarted =>
      'Both chains have been started';

  @override
  String capaCauseAlreadyReasonsBothWhyTheProblemHappened(Object capaNo) {
    return '$capaNo already reasons both why the problem happened and why it was not detected, so the Why for this cause belongs in one of them rather than at the head of a chain.';
  }

  @override
  String get capaCauseTheBoneItHangsFrom => 'The bone it hangs from';

  @override
  String get capaCauseTheCandidateCause => 'The candidate cause';

  @override
  String get capaCauseWhatYouSuspectSaidSoTheNext =>
      'What you suspect, said so the next person can check it.';

  @override
  String get capaCauseDecideThisCause => 'Decide this cause';

  @override
  String get capaCauseRecordTheVerdict => 'Record the verdict';

  @override
  String get capaCauseAVerdictIsADecisionTheReport =>
      'A verdict is a decision the report reads back, so it is recorded with the evidence for it.';

  @override
  String get capaCauseTheEvidence => 'The evidence';

  @override
  String get capaCauseWhatYouLookedAtAndWhatIt =>
      'What you looked at, and what it showed.';

  @override
  String get capaCauseStartAChainFromThisCause =>
      'Start a chain from this cause';

  @override
  String get capaCauseStartTheChain => 'Start the chain';

  @override
  String get capaCauseTheEvidenceConfirmedThisCauseSoA =>
      'The evidence confirmed this cause, so a chain may begin with it. What it says is the first Why.';

  @override
  String get capaCauseWhichChainItBegins => 'Which chain it begins';

  @override
  String get capaCauseTheFirstWhy => 'The first Why';

  @override
  String get capaCauseTheConfirmedCauseSaidTheWayThe =>
      'The confirmed cause, said the way the chain should read.';

  @override
  String capaDetailBackTo(Object actionNo) {
    return 'Back to $actionNo';
  }

  @override
  String get capaDetailTheReport => 'The report';

  @override
  String capaDetailInvestigation(Object methodLabel) {
    return '$methodLabel investigation';
  }

  @override
  String capaDetailDue(Object dueDate) {
    return 'due $dueDate';
  }

  @override
  String get capaDetailEffectiveness => 'Effectiveness';

  @override
  String get commonACapaClosesOnlyWhenBothChains =>
      'A CAPA closes only when both chains have a confirmed root cause, its Concern is closed, and somebody holding Quality authority other than its team lead has verified, some time later, that the problem has not come back.';

  @override
  String capaDetailRecordedByOn(Object value, Object value2) {
    return 'recorded by $value on $value2';
  }

  @override
  String get capaDetailTheCheckDidNotHoldSoThe =>
      'The check did not hold, so the Concern is open again in its next cycle: the work is on its Screen, in the Concern this investigation answers.';

  @override
  String commonTheConcernHasClosedSoTheEffectiveness(Object dueAt) {
    return 'The Concern has closed, so the effectiveness check is due on $dueAt.';
  }

  @override
  String get commonOverdue => 'Overdue';

  @override
  String get commonRecordTheEffectivenessCheck =>
      'Record the effectiveness check';

  @override
  String get capaDetailYouLeadThisInvestigationSoSomebodyElse =>
      'You lead this investigation, so somebody else records the check: a holder of Quality authority who is not on the team lead\'s Account.';

  @override
  String get capaDetailRecordingTheCheckNeedsQualityAuthorityAt =>
      'Recording the check needs Quality authority at this Org Unit.';

  @override
  String capaDetailTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  ) {
    return 'The check falls due $effectivenessCheckDelayDays days after the Concern closes, and the Concern has not closed yet.';
  }

  @override
  String get capaDetailTeam => 'Team';

  @override
  String get commonNobodyIsOnThisInvestigationYet =>
      'Nobody is on this investigation yet.';

  @override
  String commonTeamLead(Object name) {
    return '$name · team lead';
  }

  @override
  String get capaDetailTheProblem => 'The problem';

  @override
  String get commonNobodyHasWrittenTheProblemDescriptionYet =>
      'Nobody has written the problem description yet.';

  @override
  String get capaDetailCandidateCauses => 'Candidate causes';

  @override
  String get capaDetailTheFishboneWhatTheTeamSuspectedBy =>
      'The fishbone: what the team suspected, by 6M category, and what the evidence said about each one. The chain that follows begins with the cause it confirmed.';

  @override
  String get capaDetailThisInvestigationIsOverSoItsFishbone =>
      'This investigation is over, so its fishbone is a record rather than a worklist.';

  @override
  String get capaDetailRecordACause => 'Record a cause';

  @override
  String capaDetailNothingIsRecordedUnder(Object value) {
    return 'Nothing is recorded under $value.';
  }

  @override
  String capaDetailCause(Object sequence) {
    return 'Cause $sequence';
  }

  @override
  String commonEvidence(Object evidenceNote) {
    return 'Evidence: $evidenceNote';
  }

  @override
  String get capaDetailChangeTheVerdict => 'Change the verdict';

  @override
  String get capaDetailDecideIt => 'Decide it';

  @override
  String get capaDetailStartAChainFromIt => 'Start a chain from it';

  @override
  String get capaDetailRootCause => 'Root cause';

  @override
  String get capaDetailTwoChainsEachEndingAtOneConfirmed =>
      'Two chains, each ending at one confirmed root cause: why the problem happened, and why it was not detected.';

  @override
  String get capaDetailThisInvestigationIsOverSoItsChains =>
      'This investigation is over, so its chains are a record rather than a worklist.';

  @override
  String get commonAddAWhy => 'Add a Why';

  @override
  String get capaDetailWhyTheProblemHappenedOneStepAt =>
      'Why the problem happened, one step at a time.';

  @override
  String get capaDetailWhyItWasNotDetectedOneStep =>
      'Why it was not detected, one step at a time.';

  @override
  String get commonNobodyHasStartedThisChainYet =>
      'Nobody has started this chain yet.';

  @override
  String get commonThisChainHasNoConfirmedRootCause =>
      'This chain has no confirmed root cause yet.';

  @override
  String commonConfirmedRootCause(Object statement) {
    return 'Confirmed root cause: $statement';
  }

  @override
  String capaDetailWhy(Object sequence) {
    return 'Why $sequence';
  }

  @override
  String get capaDetailConfirmedRootCause => 'Confirmed root cause';

  @override
  String get capaDetailClearTheRootCause => 'Clear the root cause';

  @override
  String get capaDetailThisIsTheRootCause => 'This is the root cause';

  @override
  String get capaDetailMoveItEarlierInTheChain =>
      'Move it earlier in the chain';

  @override
  String get capaDetailMoveItLaterInTheChain => 'Move it later in the chain';

  @override
  String get capaDetailTheConcern => 'The Concern';

  @override
  String capaDetailTheConcern2(Object actionNo) {
    return 'The Concern: $actionNo';
  }

  @override
  String get capaDetailWhatTheConcernHasDone => 'What the Concern has done';

  @override
  String capaDetailWhatTheConcernHasDone2(Object length) {
    return 'What the Concern has done ($length)';
  }

  @override
  String get capaDetailTheContainmentD3TheCountermeasuresD5D6 =>
      'The containment (D3), the countermeasures (D5-D6) and the preventive actions (D7) are the Concern\'s own, recorded once in the action log — this is where they are read, not where they are recorded again.';

  @override
  String get capaDetailNothingAnswersThisConcernYetSoThere =>
      'Nothing answers this Concern yet, so there is no work to show.';

  @override
  String commonCycle(Object cycle, Object phaseLabel) {
    return 'Cycle $cycle · $phaseLabel';
  }

  @override
  String get commonOpen2 => 'open';

  @override
  String capaEffectivenessIsSoItsEffectivenessIsRecordedAnd(
    Object capaNo,
    Object value,
  ) {
    return '$capaNo is $value, so its effectiveness is recorded and the record is read rather than changed.';
  }

  @override
  String get capaEffectivenessNotYoursToDecide => 'Not yours to decide';

  @override
  String get capaEffectivenessRecordingACapaSEffectivenessCheckNeeds =>
      'Recording a CAPA\'s effectiveness check needs Quality authority at its Org Unit.';

  @override
  String get capaEffectivenessSomebodyElseHasToCheckThis =>
      'Somebody else has to check this';

  @override
  String capaEffectivenessYouLeadTheInvestigationOnSoYou(Object capaNo) {
    return 'You lead the investigation on $capaNo, so you are the one person whose judgement about this fix is not evidence. A holder of Quality authority who is not on the team lead\'s Account records the check.';
  }

  @override
  String capaEffectivenessTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  ) {
    return 'The check falls due $effectivenessCheckDelayDays days after the Concern closes.';
  }

  @override
  String capaEffectivenessTheConcernClosedAndTheCheckFell(
    Object effectivenessCheckDueAt,
  ) {
    return 'The Concern closed, and the check fell due on $effectivenessCheckDueAt.';
  }

  @override
  String get capaEffectivenessWhatTheCheckFound => 'What the check found';

  @override
  String capaEffectivenessAChainOfThisInvestigationHasNo(Object value) {
    return 'A chain of this investigation has no confirmed root cause yet, so \"$value\" cannot close it: the investigation has to have finished before the fix is judged to have held.';
  }

  @override
  String get capaEffectivenessWhatYouCheckedAndWhatYouFound =>
      'What you checked, and what you found';

  @override
  String get capaEffectivenessTheEvidenceForTheVerdictSoThe =>
      'The evidence for the verdict, so the next reader can weigh it.';

  @override
  String get capaOrgUnitFilterChooseTheOrgUnitWhoseInvestigationsAnd =>
      'Choose the Org Unit whose investigations and everything beneath it you want to read, or clear back to every one of them.';

  @override
  String get capaReportThatCapaReportCouldNotBeRead =>
      'That CAPA report could not be read';

  @override
  String get capaReportThe8dRecordOfThisInvestigationIts =>
      'The 8D record of this investigation: its team, the problem it answers, what was done about it, and whether the fix held.';

  @override
  String capaReportAnswersTheConcern(Object actionNo, Object title) {
    return 'Answers the Concern $actionNo · $title';
  }

  @override
  String get capaReportTheTeamHasNotBeenNamed => 'The team has not been named.';

  @override
  String get capaReportTheProblemDescriptionHasNotBeenWritten =>
      'The problem description has not been written.';

  @override
  String get capaReportNoContainmentActionIsRecorded =>
      'No containment action is recorded on the Concern.';

  @override
  String capaReportChainHasNotBeenStarted(Object chain) {
    return '$chain has not been started.';
  }

  @override
  String capaReportChainHasNoConfirmedRootCause(Object chain) {
    return '$chain has no confirmed root cause.';
  }

  @override
  String get capaReportNoCountermeasureIsRecorded =>
      'No countermeasure is recorded on the Concern.';

  @override
  String get capaReportNoPreventiveActionIsRecorded =>
      'No preventive action is recorded on the Concern.';

  @override
  String get capaReportTheEffectivenessCheckHasNotBeenRecorded =>
      'The effectiveness check has not been recorded.';

  @override
  String get capaReportNoContainmentActionIsRecordedYet =>
      'No containment action is recorded on the Concern yet.';

  @override
  String get capaReportNoCountermeasureIsRecordedYet =>
      'No countermeasure is recorded on the Concern yet.';

  @override
  String get capaReportNoPreventiveActionIsRecordedYet =>
      'No preventive action is recorded on the Concern yet.';

  @override
  String get capaReportNotYetDone => 'Not yet done';

  @override
  String get capaReportWhatThisReportIsStillWaitingFor =>
      'What this report is still waiting for.';

  @override
  String get capaReportD1Team => 'D1 · Team';

  @override
  String get capaReportWhoInvestigatedThisProblemAndWhoLed =>
      'Who investigated this problem, and who led it.';

  @override
  String get capaReportD2TheProblem => 'D2 · The problem';

  @override
  String get capaReportWhatTheTeamIsInvestigatingInThe =>
      'What the team is investigating, in the investigation\'s own words.';

  @override
  String get capaReportD3Containment => 'D3 · Containment';

  @override
  String get capaReportWhatWasDoneToStopTheBad =>
      'What was done to stop the bad product going any further.';

  @override
  String get capaReportD4RootCause => 'D4 · Root cause';

  @override
  String get capaReportTheCandidateCausesTheTeamConsideredAnd =>
      'The candidate causes the team considered and the verdict on each, then two chains ending at one confirmed root cause: why the problem happened, and why it was not detected.';

  @override
  String get capaReportD5D6Countermeasures => 'D5–D6 · Countermeasures';

  @override
  String get capaReportWhatWasDoneAboutTheCauseAnd =>
      'What was done about the cause, and whether its Check held.';

  @override
  String get capaReportD7PreventiveActions => 'D7 · Preventive actions';

  @override
  String get capaReportWhatStopsItHappeningOnThisLine =>
      'What stops it happening on this line again, with the outcome of every round.';

  @override
  String get capaReportTheSafetyIncidentThisInvestigationAnswers =>
      'The Safety incident this investigation answers';

  @override
  String get capaReportTheIncidentTheConcernWasRaisedFrom =>
      'The incident the Concern was raised from, with its number and severity — never the injury details, which the incident\'s own record restricts.';

  @override
  String get capaReportTheNonConformancesThisInvestigationAnswers =>
      'The Non-conformances this investigation answers';

  @override
  String get capaReportTheOccurrencesTheConcernAnswersWithThe =>
      'The occurrences the Concern answers, with the number, the Product, the Defect code, the quantity and what was decided about the product.';

  @override
  String get capaReportNoNonConformanceIsLinkedToThis =>
      'No Non-conformance is linked to this Concern, so the report has no evidence to list.';

  @override
  String get capaReportNoPhaseOfThisActionHasBeen =>
      'No phase of this Action has been completed yet.';

  @override
  String get capaReportTheCandidateCausesConsidered =>
      'The candidate causes considered';

  @override
  String get capaReportNoCandidateCauseIsRecordedSoNo =>
      'No candidate cause is recorded, so no fishbone was worked.';

  @override
  String capaReportWhy(Object sequence, Object statement) {
    return 'Why $sequence · $statement';
  }

  @override
  String get capaReportD8Effectiveness => 'D8 · Effectiveness';

  @override
  String capaReportVerifiedByOn(Object value, Object value2) {
    return 'verified by $value on $value2';
  }

  @override
  String capaReportTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  ) {
    return 'The check falls due $effectivenessCheckDelayDays days after the Concern closes, and the Concern has not closed yet, so nothing has been verified.';
  }

  @override
  String get capaReportRaisedFromThis => 'raised from this';

  @override
  String get capaReportLinkedToThisConcern => 'linked to this Concern';

  @override
  String get capaReportNoProductFromThisOccurrenceHasA =>
      'No product from this occurrence has a Disposition yet.';

  @override
  String capaReportMinRework(Object value) {
    return '$value min rework';
  }

  @override
  String capaReportDecidedBy(Object decidedBy) {
    return 'decided by $decidedBy';
  }

  @override
  String get capaWhyThatIsNotAChain => 'That is not a chain';

  @override
  String get capaWhyACapaReasonsWithTwoChainsWhy =>
      'A CAPA reasons with two chains: why the problem happened, and why it was not detected.';

  @override
  String capaWhyIsSoItsChainsAreARecord(Object capaNo, Object value) {
    return '$capaNo is $value, so its chains are a record rather than a worklist.';
  }

  @override
  String get capaWhyThatWhyIsNotInThisChain => 'That Why is not in this chain';

  @override
  String capaWhyReviseWhy(Object sequence) {
    return 'Revise Why $sequence';
  }

  @override
  String capaWhyRemoveWhy(Object sequence) {
    return 'Remove Why $sequence?';
  }

  @override
  String get capaWhyItIsTakenOutOfTheChain =>
      'It is taken out of the chain for good, and the Whys after it move up one. The rest of the investigation is not touched.';

  @override
  String capaWhyOneStepOfTheReasoningInYour(Object value) {
    return '$value — one step of the reasoning, in your own words.';
  }

  @override
  String get capaWhyTheWhy => 'The Why';

  @override
  String get capaWhyWhatYouFoundSaidSoTheNext =>
      'What you found, said so the next person can follow it.';

  @override
  String get capasTheCapaListCouldNotBeRead =>
      'The CAPA list could not be read';

  @override
  String get capasTheInvestigationsOpenedOnAConcernAnd =>
      'The investigations opened on a Concern, and the effectiveness check each one is waiting on.';

  @override
  String get capasOverdueChecks => 'Overdue checks';

  @override
  String get capasThereAreMoreInvestigationsThanThisList =>
      'There are more investigations than this list shows. Narrow it by Org Unit or status.';

  @override
  String get capasNoInvestigationMatchesTheOrgUnitStatus =>
      'No investigation matches the Org Unit, status or overdue check you asked for.';

  @override
  String get capasNoInvestigationsYet => 'No investigations yet';

  @override
  String get capasACapaIsOpenedFromAConcern =>
      'A CAPA is opened from a Concern, when somebody decides that the problem needs a root cause and a fix that holds.';

  @override
  String get capasInvestigation => 'Investigation';

  @override
  String get capasEffectivenessCheck => 'Effectiveness check';

  @override
  String get capasOverdueCheck => 'Overdue check';

  @override
  String capasRecordedBy(Object value, Object value2) {
    return '$value, recorded by $value2.';
  }

  @override
  String capasTheEffectivenessCheckWasDueOn(Object effectivenessCheckDueAt) {
    return 'The effectiveness check was due on $effectivenessCheckDueAt.';
  }

  @override
  String capasTheEffectivenessCheckIsDueOn(Object effectivenessCheckDueAt) {
    return 'The effectiveness check is due on $effectivenessCheckDueAt.';
  }

  @override
  String capasTheEffectivenessCheckFallsDueDaysAfter(
    Object effectivenessCheckDelayDays,
  ) {
    return 'The effectiveness check falls due $effectivenessCheckDelayDays days after the Concern closes.';
  }

  @override
  String capasOnTheTeam(Object length) {
    return '$length on the team';
  }

  @override
  String get openCapaOpeningACapaNeedsAuthority =>
      'Opening a CAPA needs authority';

  @override
  String get openCapaOpeningACapaNeedsQualityAuthorityAt =>
      'Opening a CAPA needs Quality authority at this Concern\'s Org Unit.';

  @override
  String openCapaTakeOffTheTeam(Object displayName) {
    return 'Take $displayName off the team';
  }

  @override
  String openCapaOpenACapaOn(Object actionNo) {
    return 'Open a CAPA on $actionNo';
  }

  @override
  String get openCapaOpenTheCapa => 'Open the CAPA';

  @override
  String openCapaAn8dInvestigationInTheActionLog(Object title) {
    return '$title — an 8D investigation, in the action log, on this Concern. Its containments, countermeasures and preventive actions are the Concern\\u2019s own and are read on the CAPA rather than recorded again.';
  }

  @override
  String get openCapaTheProblemOptional => 'The problem (optional)';

  @override
  String get openCapaD2WhatTheInvestigationIsAboutIn =>
      'D2 — what the investigation is about, in the words a team will work from.';

  @override
  String get openCapaTheTeam => 'The team';

  @override
  String get openCapaChosenFromTheEmployeeDirectoryLeaveIt =>
      'Chosen from the Employee directory. Leave it empty to decide the team later — the investigation is what is being opened here.';

  @override
  String get openCapaTeamLeadOptional => 'Team lead (optional)';

  @override
  String get openCapaWhoIsAnswerableForTheInvestigation =>
      'Who is answerable for the investigation.';

  @override
  String get openCapaAddATeamMemberOptional => 'Add a team member (optional)';

  @override
  String get openCapaNobodyElseIsOnThisInvestigationYet =>
      'Nobody else is on this investigation yet.';

  @override
  String awaitingApprovalYouReSignedInAsButAn(Object email) {
    return 'You\'re signed in as $email, but an administrator hasn\'t admitted you to the Platform yet. Check back once they have.';
  }

  @override
  String get awaitingApprovalCheckAgain => 'Check again';

  @override
  String get signInPassword => 'Password';

  @override
  String get signInOr => 'or';

  @override
  String get signInCreateAnAccount => 'Create an account';

  @override
  String get signInContinueWithGoogle => 'Continue with Google';

  @override
  String get signInOneApplicationForRunningSeveralManufacturingPlants =>
      'One application for running several manufacturing plants.';

  @override
  String get accessDeniedNotAvailableToYou => 'Not available to you';

  @override
  String get accessDeniedThisPartOfThePlatformIsFor =>
      'This part of the Platform is for administrators. Ask one if you need what is here.';

  @override
  String get commonBackToHome => 'Back to Home';

  @override
  String get changePasswordAnAdministratorResetYourPasswordSoThe =>
      'An administrator reset your password, so the one you were given is temporary. Choose your own to continue.';

  @override
  String get notFoundScreenNotFound => 'Screen not found';

  @override
  String notFoundThereIsNothingAt(Object location) {
    return 'There is nothing at $location.';
  }

  @override
  String get sessionErrorTheSessionCouldNotBeChecked =>
      'The session could not be checked';

  @override
  String sessionErrorCouldNotCheckThisAccountSStatus(Object message) {
    return 'Could not check this Account\'s status: $message';
  }

  @override
  String get appDateFieldChooseADate => 'Choose a date';

  @override
  String get appDateTimeFieldChooseADateAndTime => 'Choose a date and time';

  @override
  String get appSearchFieldNoMatches => 'No matches';

  @override
  String appSearchFieldNothingMatchedTryADifferentTerm(Object lastQueriedTerm) {
    return 'Nothing matched \"$lastQueriedTerm\" — try a different term.';
  }

  @override
  String get appSearchFieldSearchFailed => 'Search failed';

  @override
  String get appSearchFieldThereAreMoreMatchesThanAreShown =>
      'There are more matches than are shown — keep typing to narrow the list.';

  @override
  String failureStateNotVisibleToYou(Object message) {
    return 'Not visible to you. $message';
  }

  @override
  String get failureStateNotVisibleToYou2 => 'Not visible to you';

  @override
  String get signaturePadSignatureDrawingArea => 'Signature drawing area';

  @override
  String get complaintDetailThatComplaintCouldNotBeRead =>
      'That complaint could not be read';

  @override
  String get complaintDetailBackToCustomerComplaints =>
      'Back to Customer complaints';

  @override
  String get commonPastDue => 'Past due';

  @override
  String get commonWarrantyClaim => 'Warranty claim';

  @override
  String get complaintDetailTheProductThisIsAbout =>
      'The product this is about';

  @override
  String get complaintDetailNothingControlsTheProductThisCustomerComplained =>
      'Nothing controls the product this customer complained about yet. Record a Non-conformance from this complaint, or link one that already exists for the same Product.';

  @override
  String get commonLinkOneThatExists => 'Link one that exists';

  @override
  String get commonOpenRecord => 'Open record';

  @override
  String get complaintDetailFoundByTheCustomerSoThisComplaint =>
      'Found by the customer, so this complaint is where it started.';

  @override
  String complaintDetailRecordedAtAndLinkedToThisComplaint(Object value) {
    return 'Recorded at $value, and linked to this complaint.';
  }

  @override
  String get commonOpenTheNonConformance => 'Open the Non-conformance';

  @override
  String get commonTheResponse => 'The response';

  @override
  String complaintDetailClosed(Object closedAt) {
    return 'Closed $closedAt';
  }

  @override
  String get complaintDetailNothingHasBeenSaidBackToThis =>
      'Nothing has been said back to this customer yet.';

  @override
  String get complaintDetailCloseWithTheResponse => 'Close with the response';

  @override
  String get complaintFormRecordACustomerComplaint =>
      'Record a customer complaint';

  @override
  String get complaintFormCustomer => 'Customer';

  @override
  String get commonDefectCodeOptional => 'Defect code (optional)';

  @override
  String get complaintFormWhatTheCustomerSaysIsWrongA =>
      'What the customer says is wrong. A Non-conformance recorded from this complaint carries it.';

  @override
  String get complaintFormQuantityOptional => 'Quantity (optional)';

  @override
  String get complaintFormInTheProductSOwnUnitOf =>
      'In the Product\'s own unit of measure.';

  @override
  String get complaintFormResponseDueOptional => 'Response due (optional)';

  @override
  String get complaintFormTheDayTheCustomerWasPromisedAn =>
      'The day the customer was promised an answer.';

  @override
  String get complaintFormWhatTheCustomerSaid => 'What the customer said';

  @override
  String get complaintFormWhoAnswersIt => 'Who answers it';

  @override
  String get complaintFormChooseTheOrgUnitThatWillAnswer =>
      'Choose the Org Unit that will answer this complaint. This is what decides who may act on it.';

  @override
  String complaintFormThisComplaintWillBeFiledAt(Object value) {
    return 'This complaint will be filed at $value.';
  }

  @override
  String get commonLinkANonConformance => 'Link a Non-conformance';

  @override
  String get commonLinking => 'Linking…';

  @override
  String get commonLinkIt => 'Link it';

  @override
  String complaintLinkANonConformanceThatAlreadyExistsFor(Object productName) {
    return 'A Non-conformance that already exists for $productName can be linked to this complaint, instead of recording a second one for the same problem.';
  }

  @override
  String get commonTheNonConformancesCouldNotBeRead =>
      'The Non-conformances could not be read';

  @override
  String get complaintLinkNoNonConformanceHasBeenRecordedFor =>
      'No Non-conformance has been recorded for this Product yet, so there is nothing to link. Record one from this complaint instead.';

  @override
  String get commonTheNonConformanceThatControlsIt =>
      'The Non-conformance that controls it';

  @override
  String get complaintNonconformanceControlTheProduct => 'Control the product';

  @override
  String complaintNonconformanceANonConformanceIsRecordedAtFor(
    Object orgUnitName,
    Object productName,
  ) {
    return 'A Non-conformance is recorded at $orgUnitName for $productName, found by the customer.';
  }

  @override
  String get complaintNonconformanceHowMuchProductIsInQuestionIn =>
      'How much product is in question, in the Product\'s own unit.';

  @override
  String get complaintNonconformanceTheComplaintSOwnDefectCodeIs =>
      'The complaint\'s own Defect code is carried onto the record.';

  @override
  String get commonTheDefectCodesCouldNotBeRead =>
      'The Defect codes could not be read';

  @override
  String get complaintNonconformanceThisComplaintCarriesNoneSoChooseThe =>
      'This complaint carries none, so choose the one to record it against.';

  @override
  String get commonWhatWasDoneAtOnceRecordingIt =>
      'What was done at once. Recording it makes the record contained.';

  @override
  String get commonNarrowTheRegister => 'Narrow the register';

  @override
  String get complaintOrgUnitFilterChooseTheOrgUnitWhoseComplaintsAnd =>
      'Choose the Org Unit whose complaints, and everything beneath it, you want to read — or clear back to the whole Site.';

  @override
  String get complaintRespondAnswerTheCustomer => 'Answer the customer';

  @override
  String get complaintRespondClosing => 'Closing…';

  @override
  String get complaintRespondCloseTheComplaint => 'Close the complaint';

  @override
  String complaintRespondWhatWasSaidBackToAboutThis(
    Object customerName,
    Object complaintNo,
  ) {
    return 'What was said back to $customerName about $complaintNo. This closes the complaint.';
  }

  @override
  String get complaintsTheComplaintRegisterCouldNotBeRead =>
      'The complaint register could not be read';

  @override
  String get complaintsWhatCustomersHaveComplainedAboutAtThis =>
      'What customers have complained about at this Site, and whether the product they complained about is under control.';

  @override
  String get complaintsRecordAComplaint => 'Record a complaint';

  @override
  String get complaintsThereAreMoreComplaintsThanThisList =>
      'There are more complaints than this list shows. Narrow it by Org Unit or by status to see the rest.';

  @override
  String get complaintsTheRegisterHasComplaintsButNoneOf =>
      'The register has complaints, but none of them is in the area or state you picked.';

  @override
  String get complaintsNoComplaints => 'No complaints';

  @override
  String get complaintsNoCustomerHasComplainedAboutAnythingFrom =>
      'No customer has complained about anything from this Site.';

  @override
  String get complaintsComplaint => 'Complaint';

  @override
  String get complaintsCustomerAndProduct => 'Customer and product';

  @override
  String get complaintsResponseDue => 'Response due';

  @override
  String get commonControl => 'Control';

  @override
  String get complaintsWarranty => 'Warranty';

  @override
  String get customerFormCorrectCustomer => 'Correct Customer';

  @override
  String get commonAddCustomer => 'Add Customer';

  @override
  String get customerFormACustomerSCodeCannotBeCorrected =>
      'A Customer\'s code cannot be corrected';

  @override
  String get commonContactEmailOptional => 'Contact email (optional)';

  @override
  String get customersTheCustomerListCouldNotBeRead =>
      'The Customer list could not be read';

  @override
  String get customersWhoThePlantSCustomersAreSo =>
      'Who the plant\'s customers are, so a complaint has someone to belong to and a response has somewhere to go.';

  @override
  String get customersNoCustomersYet => 'No Customers yet';

  @override
  String get commonNothingHasBeenDefinedInTheList =>
      'Nothing has been defined in the list.';

  @override
  String get customersFilterCustomers => 'Filter Customers';

  @override
  String get customersNoCustomersMatch => 'No Customers match';

  @override
  String commonNothingInTheListMatchesTryA(Object term) {
    return 'Nothing in the list matches \"$term\". Try a different name or code, or clear the filter.';
  }

  @override
  String get defectCodeFormCorrectDefectCode => 'Correct Defect code';

  @override
  String get commonAddDefectCode => 'Add Defect code';

  @override
  String get defectCodeFormADefectCodeCannotBeCorrected =>
      'A Defect code cannot be corrected';

  @override
  String get defectCodeFormDefaultSeverity => 'Default severity';

  @override
  String get defectCodeFormWhatANonConformanceRecordedAgainstThis =>
      'What a Non-conformance recorded against this code starts at';

  @override
  String get defectCodeFormParent => 'Parent';

  @override
  String get defectCodeFormNoParentTopLevel => 'No parent — top level';

  @override
  String get defectCodesTheDefectCodeCatalogueCouldNotBe =>
      'The Defect code catalogue could not be read';

  @override
  String get defectCodesTheKindsOfThingFoundWrongOne =>
      'The kinds of thing found wrong — one list shared by every Site, and the severity each starts a Non-conformance at.';

  @override
  String get defectCodesTopLevel => 'Top level';

  @override
  String defectCodesUnder(Object parentName) {
    return 'Under $parentName';
  }

  @override
  String defectCodesStartsAt(Object severity) {
    return 'starts at $severity';
  }

  @override
  String get defectCodesNoDefectCodesYet => 'No Defect codes yet';

  @override
  String get issueImagesKeepIt => 'Keep it';

  @override
  String get issueImagesRemoveThisPicture => 'Remove this picture?';

  @override
  String get issueImagesThePictureIsTakenOffTheRecord =>
      'The picture is taken off the record. A slide needs one, so the issue may leave the show until another is added.';

  @override
  String get issueImagesAddPicture => 'Add picture';

  @override
  String get issueImagesPictures => 'Pictures';

  @override
  String get issueImagesThePicturesCouldNotBeRead =>
      'The pictures could not be read';

  @override
  String get issueImagesNoPictureYetASlideNeedsAt =>
      'No picture yet. A slide needs at least one: add the photo that shows the problem.';

  @override
  String get commonThePictureCouldNotBeLoaded =>
      'The picture could not be loaded';

  @override
  String get issueImagesAPictureOfTheIssue => 'A picture of the issue';

  @override
  String get issueImagesRemoveThisPicture2 => 'Remove this picture';

  @override
  String get issueImagesAddThisPicture => 'Add this picture';

  @override
  String get issueImagesTheCaptionIsWhatTheSlideSays =>
      'The caption is what the slide says under it. It is optional.';

  @override
  String get issueImagesAddIt => 'Add it';

  @override
  String get issueImagesCaptionOptional => 'Caption (optional)';

  @override
  String get issueImagesBurrOnTheFlangeNearTheLocating =>
      'Burr on the flange, near the locating lug';

  @override
  String get nonconformanceCancelCannotCancelIt => 'Cannot cancel it';

  @override
  String
  get nonconformanceCancelCancellingANonConformanceNeedsQualityAuthority =>
      'Cancelling a Non-conformance needs Quality authority at its Org Unit.';

  @override
  String get nonconformanceCancelANonConformanceThatIsClosedOr =>
      'A Non-conformance that is closed or already cancelled cannot be cancelled.';

  @override
  String get nonconformanceCancelCancelThisNonConformance =>
      'Cancel this Non-conformance';

  @override
  String get nonconformanceCancelCancelIt => 'Cancel it';

  @override
  String nonconformanceCancelWillBeCancelledRatherThanDealtWith(
    Object issueNo,
  ) {
    return '$issueNo will be cancelled rather than dealt with. A cancelled Non-conformance accepts no further Dispositions or quantity changes.';
  }

  @override
  String get commonNote => 'Note';

  @override
  String get nonconformanceCancelWhyItShouldNeverHaveBeenRecorded =>
      'Why it should never have been recorded.';

  @override
  String get nonconformanceConcessionCannotGrantIt => 'Cannot grant it';

  @override
  String
  get nonconformanceConcessionGrantingAConcessionNeedsQualityAuthorityAt =>
      'Granting a Concession needs Quality authority at this Non-conformance\'s Org Unit.';

  @override
  String get nonconformanceConcessionGrantIt => 'Grant it';

  @override
  String nonconformanceConcessionAcceptingTheProductAsItIsNeeds(
    Object issueNo,
  ) {
    return 'Accepting the product as it is needs Quality authority, and your name stays on $issueNo.';
  }

  @override
  String get nonconformanceConcessionQuantityAcceptedAsItIs =>
      'Quantity accepted as it is';

  @override
  String nonconformanceConcessionAtMost(Object value, Object unit) {
    return 'At most $value $unit.';
  }

  @override
  String get nonconformanceConcessionReference => 'Reference';

  @override
  String get nonconformanceConcessionTheDeviationOrApprovalNumberItIs =>
      'The deviation or approval number it is granted under.';

  @override
  String get nonconformanceConcessionWhyTheProductIsAcceptableAsIt =>
      'Why the product is acceptable as it is.';

  @override
  String nonconformanceDispositionHasStillUndecidedDealWithSomeOf(
    Object issueNo,
    Object value,
    Object unit,
  ) {
    return '$issueNo has $value $unit still undecided. Deal with some of it here.';
  }

  @override
  String get commonDisposition => 'Disposition';

  @override
  String get nonconformanceDispositionScrapReworkOrBackToTheSupplier =>
      'Scrap, rework, or back to the supplier.';

  @override
  String nonconformanceDispositionAtMost(Object value, Object unit) {
    return 'At most $value $unit.';
  }

  @override
  String get nonconformanceDispositionReworkMinutes => 'Rework minutes';

  @override
  String get nonconformanceDispositionHowLongTheReworkTookForCost =>
      'How long the rework took, for cost of poor quality.';

  @override
  String get nonconformanceDispositionWhatWasDoneWithIt =>
      'What was done with it.';

  @override
  String nonconformanceLinkConcernBecomesOneOfTheOccurrencesThisConcern(
    Object issueNo,
  ) {
    return '$issueNo becomes one of the occurrences this Concern answers. The Concern keeps the Non-conformance it was raised from.';
  }

  @override
  String get nonconformanceLinkConcernThisSiteHasNoOpenConcernTo =>
      'This Site has no open Concern to link it to. Raise one instead.';

  @override
  String get nonconformanceLinkConcernConcern => 'Concern';

  @override
  String get nonconformanceLinkConcernByItsNumberOrItsTitle =>
      'By its number or its title.';

  @override
  String get nonconformanceLowerSeverityCannotLowerIt => 'Cannot lower it';

  @override
  String
  get nonconformanceLowerSeverityLoweringASeverityNeedsQualityAuthorityAt =>
      'Lowering a severity needs Quality authority at this Non-conformance\'s Org Unit.';

  @override
  String get nonconformanceLowerSeverityLowerIt => 'Lower it';

  @override
  String nonconformanceLowerSeverityIsSeverityAndItsDefectCodeStarts(
    Object issueNo,
    Object value,
    Object value2,
  ) {
    return '$issueNo is $value severity, and its Defect code starts at $value2.';
  }

  @override
  String get nonconformanceLowerSeverityThisNonConformanceIsAlreadyAtThe =>
      'This Non-conformance is already at the lightest severity.';

  @override
  String get nonconformanceLowerSeverityLowerTheSeverityTo =>
      'Lower the severity to';

  @override
  String get nonconformanceLowerSeverityLoweringWhatTheDefectCodeSaysNeeds =>
      'Lowering what the Defect code says needs Quality authority.';

  @override
  String get commonLeaveTheSeverityAlone => 'Leave the severity alone';

  @override
  String get nonconformanceLowerSeverityWhyItIsLessBadThanThe =>
      'Why it is less bad than the Defect code says.';

  @override
  String get nonconformanceOrgUnitFilterChooseTheOrgUnitWhoseNonConformances =>
      'Choose the Org Unit whose Non-conformances and everything beneath it you want to read, or clear back to the whole Site.';

  @override
  String get nonconformanceQuantityIncreaseTheAffectedQuantity =>
      'Increase the affected quantity';

  @override
  String get nonconformanceQuantityIncreaseIt => 'Increase it';

  @override
  String nonconformanceQuantityCurrentlyCoversItCanOnlyGrow(
    Object issueNo,
    Object value,
    Object unit,
  ) {
    return '$issueNo currently covers $value $unit. It can only grow.';
  }

  @override
  String get nonconformanceQuantityNewAffectedQuantity =>
      'New affected quantity';

  @override
  String nonconformanceQuantityMoreThanOrNothingAtAll(
    Object value,
    Object unit,
  ) {
    return 'More than $value $unit, or nothing at all.';
  }

  @override
  String get nonconformanceQuantityWhyItChangedSortingTheBinFound =>
      'Why it changed — \"sorting the bin found eight more\".';

  @override
  String nonconformanceRaiseConcernIsRecordedAtAndTheConcernIs(
    Object issueNo,
    Object orgUnitName,
  ) {
    return '$issueNo is recorded at $orgUnitName, and the Concern is raised there — a problem is solved where it happened.';
  }

  @override
  String get nonconformanceRaiseConcernWhatIsTheProblemToSolve =>
      'What is the problem to solve?';

  @override
  String get nonconformanceRaiseConcernTheConcernIsReadInTheAction =>
      'The Concern is read in the action log, so say the problem, not the product.';

  @override
  String get commonAnythingKnownYet => 'Anything known yet';

  @override
  String
  get nonconformanceRaiseConcernOptionalTheNonConformanceItselfIsAlready =>
      'Optional. The Non-conformance itself is already linked as evidence.';

  @override
  String get common1IsWorst => '1 is worst.';

  @override
  String get nonconformanceReopenCannotReopenIt => 'Cannot reopen it';

  @override
  String
  get nonconformanceReopenReopeningANonConformanceNeedsQualityAuthority =>
      'Reopening a Non-conformance needs Quality authority at its Org Unit.';

  @override
  String get nonconformanceReopenOnlyAClosedNonConformanceCanBe =>
      'Only a closed Non-conformance can be reopened.';

  @override
  String get nonconformanceReopenReopenThisNonConformance =>
      'Reopen this Non-conformance';

  @override
  String nonconformanceReopenIsClosedReopeningItPutsItBack(Object issueNo) {
    return '$issueNo is closed. Reopening it puts it back to dispositioned, and its closing time goes with it.';
  }

  @override
  String get nonconformanceReopenWhyItIsBeingReopened =>
      'Why it is being reopened.';

  @override
  String nonconformanceUpdateIsSeverityAnd(
    Object issueNo,
    Object value,
    Object value2,
  ) {
    return '$issueNo is $value severity and $value2.';
  }

  @override
  String get nonconformanceUpdateThisNonConformanceIsAlreadyAtThe =>
      'This Non-conformance is already at the worst severity, so there is nothing to raise it to.';

  @override
  String get nonconformanceUpdateRaiseTheSeverityTo => 'Raise the severity to';

  @override
  String get nonconformanceUpdateSeverityCanBeRaisedHereLoweringIt =>
      'Severity can be raised here; lowering it is a later decision.';

  @override
  String get nonconformanceUpdateRecordContainment => 'Record containment';

  @override
  String get nonconformancesNcHcm202600001 => 'NC-HCM-2026-00001';

  @override
  String get productFormCorrectProduct => 'Correct Product';

  @override
  String get commonAddProduct => 'Add Product';

  @override
  String get productFormAProductSCodeCannotBeCorrected =>
      'A Product\'s code cannot be corrected';

  @override
  String get productFormAProductSUnitOfMeasureCannot =>
      'A Product\'s unit of measure cannot be corrected';

  @override
  String get productFormTheUnitsOfMeasureCouldNotBe =>
      'The units of measure could not be read';

  @override
  String get productsTheProductCatalogueCouldNotBeRead =>
      'The Product catalogue could not be read';

  @override
  String get productsWhatThePlantMakesOneCatalogueShared =>
      'What the plant makes — one catalogue shared by every Site, and what each Product is measured in.';

  @override
  String get productsNoProductsYet => 'No Products yet';

  @override
  String get slideShowTheSlideShowCouldNotBeRead =>
      'The slide show could not be read';

  @override
  String get slideShowTheQualityIssuesChosenForThisSite =>
      'The Quality issues chosen for this Site, one picture at a time. Choose an issue from its register or its own Screen, and set the order here.';

  @override
  String get slideShowPauseTheShow => 'Pause the show';

  @override
  String get slideShowPlayTheShow => 'Play the show';

  @override
  String get slideShowChooseTheOrder => 'Choose the order';

  @override
  String get slideShowNothingIsOnTheWallYet => 'Nothing is on the wall yet';

  @override
  String get slideShowChooseACustomerComplaintOrANon =>
      'Choose a Customer complaint or a Non-conformance in its register, and add at least one picture to it. The chosen issues appear here.';

  @override
  String slideShowChosenNoneWithAPicture(Object length) {
    return '$length chosen, none with a picture';
  }

  @override
  String slideShowASlideNeedsAPictureOpenAnd(Object value, Object value2) {
    return 'A slide needs a picture. Open $value and add one, and $value2 will appear here.';
  }

  @override
  String slideShowAPictureOf(Object value) {
    return 'A picture of $value';
  }

  @override
  String get slideShowPreviousSlide => 'Previous slide';

  @override
  String get slideShowNoSlides => 'No slides';

  @override
  String get slideShowNextSlide => 'Next slide';

  @override
  String slideShowChosenWithoutAPicture(Object length) {
    return '$length chosen without a picture';
  }

  @override
  String get slideShowTheOrderTheShowPlaysIn => 'The order the show plays in';

  @override
  String get slideShowNothingIsChosenYet => 'Nothing is chosen yet.';

  @override
  String slideShowPicture(Object value, Object value2) {
    return '$value picture$value2';
  }

  @override
  String get slideShowNoPictureYetItWillNotAppear =>
      'No picture yet — it will not appear until one is added';

  @override
  String get slideShowMoveEarlier => 'Move earlier';

  @override
  String get slideShowMoveLater => 'Move later';

  @override
  String get slideShowTakeOffTheWall => 'Take off the wall';

  @override
  String get slideShowToggleOnTheSlideShow => 'On the slide show';

  @override
  String get slideShowToggleNotOnTheSlideShow => 'Not on the slide show';

  @override
  String get slideShowToggleChosenIssuesPlayInTheQualitySlide =>
      'Chosen issues play in the Quality slide show, one picture at a time.';

  @override
  String get supplierFormCorrectSupplier => 'Correct Supplier';

  @override
  String get commonAddSupplier => 'Add Supplier';

  @override
  String get supplierFormASupplierSCodeCannotBeCorrected =>
      'A Supplier\'s code cannot be corrected';

  @override
  String get supplierNcrDetailThatSupplierNcrCouldNotBeRead =>
      'That supplier NCR could not be read';

  @override
  String get supplierNcrDetailBackToSupplierNcrs => 'Back to Supplier NCRs';

  @override
  String get supplierNcrDetailNothingWasWrittenDownAboutIt =>
      'Nothing was written down about it.';

  @override
  String get supplierNcrDetailTheMaterialThisIsAbout =>
      'The material this is about';

  @override
  String get supplierNcrDetailNothingControlsTheMaterialThisNcrIs =>
      'Nothing controls the material this NCR is about yet. Record a Non-conformance from this NCR, or link one that already exists for the same lot.';

  @override
  String get supplierNcrDetailFoundAtGoodsInSoThisNcr =>
      'Found at goods-in, so this NCR is where it started.';

  @override
  String supplierNcrDetailRecordedAtAndLinkedToThisNcr(Object value) {
    return 'Recorded at $value, and linked to this NCR.';
  }

  @override
  String get supplierNcrDetailTheSupplierSDisposition =>
      'The Supplier\'s disposition';

  @override
  String get supplierNcrDetailNothingHasBeenRecoveredFromThisSupplier =>
      'Nothing has been recovered from this Supplier.';

  @override
  String supplierNcrDetailRecovered(Object costRecoveredLabel) {
    return 'Recovered $costRecoveredLabel.';
  }

  @override
  String supplierNcrDetailClosed(Object closedAt) {
    return 'Closed $closedAt';
  }

  @override
  String get commonRecordTheDisposition => 'Record the disposition';

  @override
  String get supplierNcrDetailCorrectTheDisposition =>
      'Correct the disposition';

  @override
  String get supplierNcrDetailCloseTheNcr => 'Close the NCR';

  @override
  String get supplierNcrDispositionDecideTheMaterial => 'Decide the material';

  @override
  String supplierNcrDispositionWhatHappensToThatCameFromOn(
    Object quantityLabel,
    Object supplierName,
    Object ncrNo,
  ) {
    return 'What happens to $quantityLabel that came from $supplierName on $ncrNo.';
  }

  @override
  String get supplierNcrDispositionWhatThePlantDecidedHappensToThe =>
      'What the plant decided happens to the received material.';

  @override
  String get supplierNcrDispositionCostRecoveredOptional =>
      'Cost recovered (optional)';

  @override
  String get supplierNcrDispositionWhatWasClawedBackFromTheSupplier =>
      'What was clawed back from the Supplier. Leave it blank when nothing was claimed.';

  @override
  String get supplierNcrDispositionThreeLettersTheCurrencyTheCostRecovered =>
      'Three letters, the currency the cost recovered is in.';

  @override
  String get commonRecordASupplierNcr => 'Record a supplier NCR';

  @override
  String get commonSupplier => 'Supplier';

  @override
  String get supplierNcrFormProductOptional => 'Product (optional)';

  @override
  String get supplierNcrFormWhatTheLotIsWhenThatIs =>
      'What the lot is, when that is known. A Non-conformance recorded from this NCR needs one.';

  @override
  String get supplierNcrFormNotNamedYet => 'Not named yet';

  @override
  String get supplierNcrFormWhatIsWrongWithItANon =>
      'What is wrong with it. A Non-conformance recorded from this NCR carries it.';

  @override
  String get supplierNcrFormHowMuchCameInWrong => 'How much came in wrong.';

  @override
  String get supplierNcrFormWhatTheQuantityIsCountedInTaken =>
      'What the quantity is counted in. Taken from the Product when one is named.';

  @override
  String get supplierNcrFormIncomingLotReferenceOptional =>
      'Incoming lot reference (optional)';

  @override
  String get supplierNcrFormTheLotTheDeliveryNoteSays =>
      'The lot the delivery note says.';

  @override
  String get supplierNcrFormPurchaseReferenceOptional =>
      'Purchase reference (optional)';

  @override
  String get supplierNcrFormTheOrderItArrivedAgainst =>
      'The order it arrived against.';

  @override
  String get supplierNcrFormAnswerDueOptional => 'Answer due (optional)';

  @override
  String get supplierNcrFormTheDayTheSupplierWasGivenTo =>
      'The day the Supplier was given to answer.';

  @override
  String get supplierNcrFormWhatIsWrongWithItOptional =>
      'What is wrong with it (optional)';

  @override
  String get supplierNcrFormWhoWorksIt => 'Who works it';

  @override
  String get supplierNcrFormChooseTheOrgUnitThatWillWork =>
      'Choose the Org Unit that will work this supplier NCR. This is what decides who may act on it.';

  @override
  String supplierNcrFormThisSupplierNcrWillBeFiledAt(Object value) {
    return 'This supplier NCR will be filed at $value.';
  }

  @override
  String supplierNcrLinkANonConformanceThatAlreadyExistsCan(Object value) {
    return 'A Non-conformance that already exists$value can be linked to this supplier NCR, instead of recording a second one for the same problem.';
  }

  @override
  String get supplierNcrLinkNoNonConformanceHasBeenRecordedFor =>
      'No Non-conformance has been recorded for this Product yet, so there is nothing to link. Record one from this supplier NCR instead.';

  @override
  String get supplierNcrNonconformanceControlTheMaterial =>
      'Control the material';

  @override
  String supplierNcrNonconformanceANonConformanceIsRecordedAtFound(
    Object orgUnitName,
    Object value,
  ) {
    return 'A Non-conformance is recorded at $orgUnitName$value, found at goods-in.';
  }

  @override
  String get supplierNcrNonconformanceHowMuchMaterialIsInQuestionIn =>
      'How much material is in question, in the unit it came in.';

  @override
  String get supplierNcrNonconformanceTheSupplierNcrSOwnProductIs =>
      'The supplier NCR\'s own Product is carried onto the record.';

  @override
  String get supplierNcrNonconformanceTheProductsCouldNotBeRead =>
      'The Products could not be read';

  @override
  String get supplierNcrNonconformanceThisSupplierNcrNamesNoneSoChoose =>
      'This supplier NCR names none, so choose what the lot was for.';

  @override
  String get supplierNcrNonconformanceTheSupplierNcrSOwnDefectCode =>
      'The supplier NCR\'s own Defect code is carried onto the record.';

  @override
  String get supplierNcrNonconformanceThisSupplierNcrCarriesNoneSoChoose =>
      'This supplier NCR carries none, so choose the one to record it against.';

  @override
  String get supplierNcrOrgUnitFilterChooseTheOrgUnitWhoseSupplierNcrs =>
      'Choose the Org Unit whose supplier NCRs, and everything beneath it, you want to read — or clear back to the whole Site.';

  @override
  String get supplierNcrSupplierFilterFilterBySupplier => 'Filter by Supplier';

  @override
  String get commonAllSuppliers => 'All Suppliers';

  @override
  String get supplierNcrSupplierFilterChooseTheSupplierWhoseSupplierNcrsYou =>
      'Choose the Supplier whose supplier NCRs you want to read, or clear back to every Supplier.';

  @override
  String get supplierNcrsTheSupplierNcrRegisterCouldNotBe =>
      'The supplier NCR register could not be read';

  @override
  String get supplierNcrsWhatArrivedWrongFromASupplierAt =>
      'What arrived wrong from a Supplier at this Site, and whether the material it came in with is under control.';

  @override
  String get supplierNcrsThereAreMoreSupplierNcrsThanThis =>
      'There are more supplier NCRs than this list shows. Narrow it by Supplier or by status to see the rest.';

  @override
  String get supplierNcrsTheRegisterHasSupplierNcrsButNone =>
      'The register has supplier NCRs, but none of them is in the area, the Supplier or the state you picked.';

  @override
  String get supplierNcrsNoSupplierNcrs => 'No supplier NCRs';

  @override
  String get supplierNcrsNothingHasComeInWrongFromA =>
      'Nothing has come in wrong from a Supplier at this Site.';

  @override
  String get supplierNcrsNcr => 'NCR';

  @override
  String get supplierNcrsSupplierAndProduct => 'Supplier and product';

  @override
  String get supplierNcrsAnswerDue => 'Answer due';

  @override
  String get suppliersTheSupplierListCouldNotBeRead =>
      'The Supplier list could not be read';

  @override
  String get suppliersWhoThePlantBuysFromSoAn =>
      'Who the plant buys from, so an incoming lot that is wrong has someone to belong to and a claim has somewhere to go.';

  @override
  String get suppliersNoSuppliersYet => 'No Suppliers yet';

  @override
  String get suppliersFilterSuppliers => 'Filter Suppliers';

  @override
  String get suppliersNoSuppliersMatch => 'No Suppliers match';

  @override
  String get bodyPartFormCorrectBodyPart => 'Correct Body part';

  @override
  String get commonAddBodyPart => 'Add Body part';

  @override
  String get bodyPartFormABodyPartSCodeCannotBe =>
      'A Body part\'s code cannot be corrected';

  @override
  String get bodyPartFormRegion => 'Region';

  @override
  String get bodyPartFormARetiredBodyPartIsNoLonger =>
      'A retired Body part is no longer offered while classifying, and stays on every incident that already names it.';

  @override
  String get bodyPartsTheBodyPartCatalogueCouldNotBe =>
      'The Body part catalogue could not be read';

  @override
  String get bodyPartsWhereOnTheBodyAnInjuryWas =>
      'Where on the body an injury was — one catalogue shared by every Site, filed under the region each part belongs to.';

  @override
  String get bodyPartsNoBodyPartsYet => 'No Body parts yet';

  @override
  String get commonClassifyTheInjury => 'Classify the injury';

  @override
  String get incidentClassifyClassifyingTheInjuryNeedsSafetyAuthorityAt =>
      'Classifying the injury needs Safety authority at this Safety incident\'s Org Unit.';

  @override
  String incidentClassifySitsOnTheNoInjuryRungNobody(Object incidentNo) {
    return '$incidentNo sits on the no-injury rung. Nobody was hurt, so there is nothing to classify — correct the severity first if that is wrong.';
  }

  @override
  String get incidentClassifyWhoWasHurtWhatTheInjuryWas =>
      'Who was hurt, what the injury was and where on the body. These three are read only by a holder of Safety authority for this area and by the injured person\'s own Account.';

  @override
  String get incidentClassifySaveTheClassification => 'Save the classification';

  @override
  String get commonInjuredEmployee => 'Injured Employee';

  @override
  String get incidentClassifyWhoWasHurt => 'Who was hurt.';

  @override
  String get incidentClassifyClearTheInjuredEmployee =>
      'Clear the injured Employee';

  @override
  String get incidentClassifyTheInjuryTypeAndBodyPartCatalogues =>
      'The Injury type and Body part catalogues could not be read';

  @override
  String get commonInjuryType => 'Injury type';

  @override
  String get incidentClassifyWhatTheInjuryWas => 'What the injury was.';

  @override
  String get incidentClassifyClearTheInjuryType => 'Clear the Injury type';

  @override
  String get commonBodyPart => 'Body part';

  @override
  String get incidentClassifyWhereOnTheBody => 'Where on the body.';

  @override
  String get incidentClassifyClearTheBodyPart => 'Clear the Body part';

  @override
  String get incidentCloseCloseThisSafetyIncident =>
      'Close this Safety incident';

  @override
  String get incidentCloseClosingASafetyIncidentNeedsSafetyAuthority =>
      'Closing a Safety incident needs Safety authority at its Org Unit.';

  @override
  String get incidentCloseThisSafetyIncidentIsAlreadyClosed =>
      'This Safety incident is already closed.';

  @override
  String incidentCloseWillBeClosedAConcernRaisedFrom(Object incidentNo) {
    return '$incidentNo will be closed. A Concern raised from it, if any, keeps working the cause on its own.';
  }

  @override
  String get incidentCloseLeaveItOpen => 'Leave it open';

  @override
  String get commonCloseIt => 'Close it';

  @override
  String get incidentCloseWhyThisIncidentIsBeingClosed =>
      'Why this incident is being closed.';

  @override
  String get commonRecordTheDays => 'Record the days';

  @override
  String get incidentDaysRecordingTheDaysNeedsSafetyAuthorityAt =>
      'Recording the days needs Safety authority at this Safety incident\'s Org Unit.';

  @override
  String get incidentDaysThisSafetyIncidentIsClosedItsDays =>
      'This Safety incident is closed; its days cannot be changed.';

  @override
  String incidentDaysWhatCostZeroIsARealAnswer(Object incidentNo) {
    return 'What $incidentNo cost — zero is a real answer, and settles it.';
  }

  @override
  String get commonLostTimeDays => 'Lost-time days';

  @override
  String get commonRestrictedDays => 'Restricted days';

  @override
  String get incidentDetailNoSuchSafetyIncident => 'No such Safety incident';

  @override
  String get incidentDetailBackToSafetyIncidents => 'Back to Safety incidents';

  @override
  String get incidentDetailTheSafetyIncidentCouldNotBeRead =>
      'The Safety incident could not be read';

  @override
  String get incidentDetailReportedAt => 'Reported at';

  @override
  String get incidentDetailImmediateAction => 'Immediate action';

  @override
  String get commonInvestigationDueDate => 'Investigation due date';

  @override
  String incidentDetailMoveTo(Object value) {
    return 'Move to $value';
  }

  @override
  String get commonCorrectTheSeverity => 'Correct the severity';

  @override
  String incidentDetailClosed(Object closedAt) {
    return 'Closed $closedAt';
  }

  @override
  String get commonInvestigationDueAt => 'Investigation due at';

  @override
  String get incidentDetailTheInjury => 'The injury';

  @override
  String get incidentDetailRestrictedVisibleToSafetyAuthorityForThis =>
      'Restricted — visible to Safety authority for this area.';

  @override
  String get incidentDetailNotClassifiedYetWhoWasHurtWhat =>
      'Not classified yet. Who was hurt, what the injury was and where on the body have not been recorded.';

  @override
  String get incidentDetailTheIncidentItselfIsRecordedHereThe =>
      'The incident itself is recorded here; the cause behind it is solved in the action log, as a Concern.';

  @override
  String get incidentDetailEventHistory => 'Event history';

  @override
  String get incidentDetailEverySeverityChangeStatusMoveDaysChange =>
      'Every severity change, status move, days change, closure and classification change, kept with who and when.';

  @override
  String get incidentDetailNothingHasChangedAboutThisRecordSince =>
      'Nothing has changed about this record since it was recorded.';

  @override
  String get incidentDueDateThisSafetyIncidentIsClosedItsInvestigation =>
      'This Safety incident is closed; its investigation due date cannot be changed.';

  @override
  String incidentDueDateSInvestigationDeadline(Object incidentNo) {
    return '$incidentNo\'s investigation deadline.';
  }

  @override
  String get incidentFormWhatKindOfEventThisWas =>
      'What kind of event this was.';

  @override
  String get incidentFormTheWorstActualOutcomeToAPerson =>
      'The worst actual outcome to a person. Ladder order.';

  @override
  String get incidentFormWhatHappened => 'What happened.';

  @override
  String get incidentFormWhatWasDoneAtOnce => 'What was done at once.';

  @override
  String get incidentFormInjuredEmployeeOptional =>
      'Injured Employee (optional)';

  @override
  String get incidentFormWhoWasHurtIfAnyoneReadOnly =>
      'Who was hurt, if anyone. Read only by Safety authority for this area and by the injured person\'s own Account.';

  @override
  String get incidentFormWhenItHappenedThisIsWhatDecides =>
      'When it happened. This is what decides the production day and shift it is filed against.';

  @override
  String get incidentFormReportedAtOptional => 'Reported at (optional)';

  @override
  String get incidentFormWhenItWasReportedIfThatIs =>
      'When it was reported, if that is not now.';

  @override
  String get incidentFormWhereItHappened => 'Where it happened';

  @override
  String get incidentFormChooseTheOrgUnitTheIncidentOccurred =>
      'Choose the Org Unit the incident occurred at. This is what decides who may act on it.';

  @override
  String incidentFormThisSafetyIncidentWillBeRecordedAt(Object value) {
    return 'This Safety incident will be recorded at $value.';
  }

  @override
  String get incidentFormWhichMachineIfTheIncidentWasOn =>
      'Which machine, if the incident was on one. It must sit at that Org Unit.';

  @override
  String incidentRaiseConcernIsRecordedAtAndTheConcernIs(
    Object incidentNo,
    Object orgUnitName,
  ) {
    return '$incidentNo is recorded at $orgUnitName, and the Concern is raised there — a problem is solved where it happened.';
  }

  @override
  String get incidentRaiseConcernWhatIsTheCauseToSolve =>
      'What is the cause to solve?';

  @override
  String get incidentRaiseConcernTheConcernIsReadInTheAction =>
      'The Concern is read in the action log, so say the problem, not the injury.';

  @override
  String get incidentRaiseConcernOptionalTheSafetyIncidentItselfIsAlready =>
      'Optional. The Safety incident itself is already linked as evidence.';

  @override
  String get incidentSeverityCorrectingTheSeverityNeedsSafetyAuthorityAt =>
      'Correcting the severity needs Safety authority at this Safety incident\'s Org Unit.';

  @override
  String incidentSeverityIsCorrectingItRestatesThePeriodIt(
    Object incidentNo,
    Object value,
  ) {
    return '$incidentNo is $value. Correcting it restates the period it occurred in.';
  }

  @override
  String get incidentSeverityCorrectIt => 'Correct it';

  @override
  String get incidentSeverityCorrectTheSeverityTo => 'Correct the severity to';

  @override
  String get incidentSeverityWhyTheSeverityIsBeingCorrected =>
      'Why the severity is being corrected.';

  @override
  String get incidentStatusMoveTheStatus => 'Move the status';

  @override
  String get incidentStatusThisSafetyIncidentIsClosedItsStatus =>
      'This Safety incident is closed; its status cannot be moved.';

  @override
  String incidentStatusThisSafetyIncidentIsAlreadyOnlyClosing(Object value) {
    return 'This Safety incident is already $value; only closing moves it further.';
  }

  @override
  String incidentStatusMovesFromTo(
    Object incidentNo,
    Object statusLabel,
    Object value,
  ) {
    return '$incidentNo moves from $statusLabel to $value.';
  }

  @override
  String incidentStatusMoveTo(Object value) {
    return 'Move to $value';
  }

  @override
  String get incidents1SafetyIncident => '1 Safety incident';

  @override
  String incidentsSafetyIncidents(Object length) {
    return '$length Safety incidents';
  }

  @override
  String get incidentsSiHcm202600001 => 'SI-HCM-2026-00001';

  @override
  String get injuryTypeFormCorrectInjuryType => 'Correct Injury type';

  @override
  String get commonAddInjuryType => 'Add Injury type';

  @override
  String get injuryTypeFormAnInjuryTypeSCodeCannotBe =>
      'An Injury type\'s code cannot be corrected';

  @override
  String get injuryTypeFormARetiredInjuryTypeIsNoLonger =>
      'A retired Injury type is no longer offered while classifying, and stays on every incident that already names it.';

  @override
  String get injuryTypesTheInjuryTypeCatalogueCouldNotBe =>
      'The Injury type catalogue could not be read';

  @override
  String get injuryTypesWhatAnInjuryWasOneCatalogueShared =>
      'What an injury was — one catalogue shared by every Site, and what a Safety incident is classified against.';

  @override
  String get injuryTypesNoInjuryTypesYet => 'No Injury types yet';

  @override
  String get observationDetailNoSuchSafetyObservation =>
      'No such Safety observation';

  @override
  String get observationDetailBackToSafetyObservations =>
      'Back to Safety observations';

  @override
  String get observationDetailTheSafetyObservationCouldNotBeRead =>
      'The Safety observation could not be read';

  @override
  String get observationDetailActionTaken => 'Action taken';

  @override
  String get observationDetailRecordedBy => 'Recorded by';

  @override
  String get observationDetailObservedAt => 'Observed at';

  @override
  String get observationDetailClosingTheLoop => 'Closing the loop';

  @override
  String get observationDetailTheObservationItselfIsRecordedHereWhat =>
      'The observation itself is recorded here; what somebody does about it is owned in the action log, as an Action.';

  @override
  String get observationDetailNothingIsBeingDoneAboutThisYet =>
      'Nothing is being done about this yet.';

  @override
  String get commonRaiseAnAction => 'Raise an Action';

  @override
  String get observationFormASafeActAnUnsafeActOr =>
      'A safe act, an unsafe act, or an unsafe condition.';

  @override
  String get observationFormTheWorstCredibleOutcomeNotWhatActually =>
      'The worst credible outcome, not what actually happened.';

  @override
  String get observationFormWhatWasSeen => 'What was seen.';

  @override
  String get observationFormWhatWasDoneOnTheSpot =>
      'What was done on the spot.';

  @override
  String get observationFormRareAndTheSingleStrongestSignalThat =>
      'Rare, and the single strongest signal that the safety culture is real.';

  @override
  String get observationFormObservedAtOptional => 'Observed at (optional)';

  @override
  String get observationFormWhenItWasSeenIfNotNow =>
      'When it was seen, if not now. This is what decides the production day and shift it is filed against.';

  @override
  String get observationFormWhereItWasSeen => 'Where it was seen';

  @override
  String get observationFormChooseTheOrgUnitTheObservationWas =>
      'Choose the Org Unit the observation was made at. This is what decides who may act on it.';

  @override
  String observationFormThisSafetyObservationWillBeRecordedAt(Object value) {
    return 'This Safety observation will be recorded at $value.';
  }

  @override
  String observationRaiseActionThisObservationIsRecordedAtAndThe(
    Object orgUnitName,
  ) {
    return 'This observation is recorded at $orgUnitName, and the Action is raised there — a problem is owned where it was seen.';
  }

  @override
  String get observationRaiseActionChooseWhatThisIs => 'Choose what this is.';

  @override
  String get observationRaiseActionChooseAKind => 'Choose a kind';

  @override
  String get observationRaiseActionWhatNeedsDoing => 'What needs doing?';

  @override
  String get observationRaiseActionTheActionIsReadInTheAction =>
      'The Action is read in the action log, so say the work, not the observation.';

  @override
  String
  get observationRaiseActionOptionalTheSafetyObservationItselfIsAlready =>
      'Optional. The Safety observation itself is already linked as evidence.';

  @override
  String get observations1SafetyObservation => '1 Safety observation';

  @override
  String observationsSafetyObservations(Object length) {
    return '$length Safety observations';
  }

  @override
  String safetyIncidentRecordable(Object value) {
    return '$value · recordable';
  }

  @override
  String
  get safetyObservationOrgUnitFilterChooseTheOrgUnitWhoseSafetyObservations =>
      'Choose the Org Unit whose Safety observations and everything beneath it you want to read, or clear back to the whole Site.';

  @override
  String get safetyOrgUnitFilterChooseTheOrgUnitWhoseSafetyIncidents =>
      'Choose the Org Unit whose Safety incidents and everything beneath it you want to read, or clear back to the whole Site.';

  @override
  String handoverAcknowledgeYouAreAcceptingAndTheShift(
    Object value,
    Object value2,
  ) {
    return 'You are accepting $value and the shift$value2.';
  }

  @override
  String get handoverAcknowledgeTheOutgoingShiftDeclaredNoChangePoints =>
      'The outgoing shift declared no change points.';

  @override
  String get handoverAcknowledgeThereAreNoChangePointsToWatch =>
      'There are no change points to watch.';

  @override
  String get handoverAcknowledgeWhatEachWatchShowed => 'What each watch showed';

  @override
  String handoverAcknowledgeWatch(Object watchNote) {
    return 'Watch: $watchNote';
  }

  @override
  String get handoverAcknowledgeFound => 'Found';

  @override
  String get handoverAcknowledgeNotAnswered => 'Not answered';

  @override
  String get handoverAcknowledgeNoteOnTheHandoverOptional =>
      'Note on the handover (optional)';

  @override
  String get handoverAcknowledgeAcknowledgeTheHandover =>
      'Acknowledge the handover';

  @override
  String get handoverAcknowledgeAcknowledging => 'Acknowledging…';

  @override
  String get commonAcknowledge => 'Acknowledge';

  @override
  String get sectionThatSectionSDayCouldNotBe =>
      'That Section\'s day could not be read';

  @override
  String get sectionChooseAnotherSection => 'Choose another Section';

  @override
  String get sectionEveryShiftOfTheProductionDayWith =>
      'Every shift of the production day, with its handover and what is still open at each shift boundary.';

  @override
  String get sectionNoShiftsScheduled => 'No shifts scheduled';

  @override
  String get sectionNoShiftsAreScheduledAtThisSection =>
      'No shifts are scheduled at this Section on that day.';

  @override
  String sectionShift(Object value, Object value2) {
    return 'Shift $value–$value2';
  }

  @override
  String get commonLate => 'Late';

  @override
  String sectionHandedOverBy(Object value) {
    return 'Handed over by $value';
  }

  @override
  String sectionAcknowledgedAfterTheShiftBegan(Object value) {
    return 'acknowledged $value after the shift began';
  }

  @override
  String get sectionThatSectionTreeCouldNotBeRead =>
      'That Section tree could not be read';

  @override
  String get sectionNothingToOpenHere => 'Nothing to open here';

  @override
  String get sectionChooseASectionToOpenItsBoard =>
      'Choose a Section to open its board: the day\'s shifts and the handover at each.';

  @override
  String get shiftHandoverThatHandoverCouldNotBeOpened =>
      'That handover could not be opened';

  @override
  String get shiftHandoverSubmitTheHandover => 'Submit the handover';

  @override
  String get shiftHandoverBackToTheSectionBoard => 'Back to the Section board';

  @override
  String get shiftHandoverSection => 'Section';

  @override
  String shiftHandoverHandedOverBy(Object authorDisplayName) {
    return 'handed over by $authorDisplayName';
  }

  @override
  String shiftHandoverShiftHandover(Object value) {
    return 'Shift handover · $value';
  }

  @override
  String shiftHandoverVersion(Object version) {
    return 'Version $version';
  }

  @override
  String get shiftHandoverTheNumbersTheShiftClosedOn =>
      'The numbers the shift closed on';

  @override
  String get shiftHandoverFrozenWhenTheHandoverIsSubmitted =>
      'Frozen when the handover is submitted.';

  @override
  String get shiftHandoverFrozenAtSubmit => 'Frozen at submit.';

  @override
  String get shiftHandoverMachines => 'Machines';

  @override
  String get shiftHandoverOneLinePerAssetInTheSection =>
      'One line per Asset in the Section.';

  @override
  String get shiftHandoverThisSectionHasNoActiveAssets =>
      'This Section has no active Assets.';

  @override
  String get shiftHandoverChangePoints => 'Change points';

  @override
  String get shiftHandoverWhatTheIncomingShiftWillMeetThat =>
      'What the incoming shift will meet that differs, and what to watch.';

  @override
  String get shiftHandoverCarriedActions => 'Carried actions';

  @override
  String get shiftHandoverEveryOpenActionOfTheSectionIs =>
      'Every open Action of the Section is carried, reassigned or closed.';

  @override
  String get shiftHandoverHandoverEvidence => 'Handover evidence';

  @override
  String shiftHandoverAcknowledged(Object value, Object value2) {
    return 'Acknowledged $value$value2';
  }

  @override
  String get shiftHandoverThisHandoverCannotBeSubmittedYet =>
      'This handover cannot be submitted yet';

  @override
  String get shiftHandoverNoLineYet => 'No line yet';

  @override
  String get shiftHandoverAbnormality => 'Abnormality';

  @override
  String get shiftHandoverNoneFound => 'None found';

  @override
  String get shiftHandoverRequiredSayWhyItIsNotRunning =>
      'Required: say why it is not running normally';

  @override
  String get shiftHandoverWhatTheIncomingShiftMustWatch =>
      'What the incoming shift must watch';

  @override
  String get shiftHandoverWalked => 'Walked';

  @override
  String get shiftHandoverSaveLine => 'Save line';

  @override
  String get shiftHandoverRecordLine => 'Record line';

  @override
  String get shiftHandoverNoChangePointsThisShift =>
      'No change points this shift';

  @override
  String get shiftHandoverNoneRecorded => 'None recorded';

  @override
  String shiftHandoverWatch(Object watchNote, Object value) {
    return 'Watch: $watchNote$value';
  }

  @override
  String get shiftHandoverAddAChangePoint => 'Add a change point';

  @override
  String get shiftHandoverDimension => 'Dimension';

  @override
  String get shiftHandoverWhatIsDifferent => 'What is different';

  @override
  String get shiftHandoverWhatTheIncomingShiftMustWatchFor =>
      'What the incoming shift must watch for';

  @override
  String get shiftHandoverAddChangePoint => 'Add change point';

  @override
  String get shiftHandoverTheSectionHasNoOpenActionsTo =>
      'The Section has no open Actions to hand over.';

  @override
  String shiftHandoverOld(Object value, Object value2) {
    return '$value $value2 old';
  }

  @override
  String shiftHandoverOwner(Object ownerName) {
    return 'Owner $ownerName';
  }

  @override
  String get shiftHandoverNoDispositionYet => 'no disposition yet';

  @override
  String get shiftHandoverNewOwner => 'New owner';

  @override
  String get shiftHandoverWhatClosedIt => 'What closed it';

  @override
  String get shiftHandoverRecordDisposition => 'Record disposition';

  @override
  String get shiftHandoverJointWalkDone => 'Joint walk done';

  @override
  String get shiftHandoverCriticalItems => 'Critical items';

  @override
  String get shiftHandoverDeviationFromTheStandardHandover =>
      'Deviation from the standard handover';

  @override
  String get shiftHandoverSaveEvidence => 'Save evidence';

  @override
  String get commonAddKpi => 'Add KPI';

  @override
  String get addKpiAdd => 'Add';

  @override
  String get addKpiKpi => 'KPI';

  @override
  String get addKpiTheCodeEGOee => 'The code, e.g. OEE';

  @override
  String get addKpiUnitOptional => 'Unit (optional)';

  @override
  String get addKpiDirection => 'Direction';

  @override
  String get addKpiIsMetAtOrAboveTheTarget =>
      '>= is met at or above the Target, <= at or below it';

  @override
  String get addKpiDecimals => 'Decimals';

  @override
  String get addKpiAWholeNumberFrom0To6 => 'A whole number from 0 to 6';

  @override
  String get addKpiDecimalsMustBeAWholeNumberFrom =>
      'Decimals must be a whole number from 0 to 6';

  @override
  String get addKpiValueMeasureOptional => 'Value measure (optional)';

  @override
  String get commonChangeTarget => 'Change Target';

  @override
  String get changeTargetGrain => 'Grain';

  @override
  String get changeTargetValidFrom => 'Valid from';

  @override
  String changeTargetTodayAtThisSiteIsATarget(Object siteToday) {
    return 'Today at this Site is $siteToday; a Target starts today or later.';
  }

  @override
  String get changeTargetTarget => 'Target';

  @override
  String get changeTargetLeaveBlankForNoTargetFromThat =>
      'Leave blank for no target from that date on.';

  @override
  String get changeTargetTheTargetMustBeANumberOr =>
      'The Target must be a number, or blank for no target';

  @override
  String get kpiCatalogueTheKpiCatalogueCouldNotBeRead =>
      'The KPI catalogue could not be read';

  @override
  String get kpiCatalogueTheKpisOfTheMtuLineWith =>
      'The KPIs of the MTU line, with the Target in force per grain.';

  @override
  String kpiCatalogueTheKpisOfTheMtuLineWith2(Object reviewDate) {
    return 'The KPIs of the MTU line, with the Target in force per grain and the review state for today, $reviewDate.';
  }

  @override
  String get kpiCatalogueNoKpisInTheCatalogueYet =>
      'No KPIs in the catalogue yet';

  @override
  String get kpiCatalogueNothingHasBeenAddedToTheKpi =>
      'Nothing has been added to the KPI catalogue.';

  @override
  String get commonFilterKpis => 'Filter KPIs';

  @override
  String get kpiCatalogueByCodeOrTitle => 'By code or title.';

  @override
  String get commonNoKpisMatch => 'No KPIs match';

  @override
  String kpiCatalogueNothingInTheCatalogueMatchesTryA(Object term) {
    return 'Nothing in the catalogue matches \"$term\". Try a different code or title, or clear the filter.';
  }

  @override
  String kpiCatalogueValueMeasure(Object measure) {
    return 'Value measure: $measure';
  }

  @override
  String get kpiReviewTheKpiReviewCouldNotBeRead =>
      'The KPI Review could not be read';

  @override
  String get kpiReviewKpiReview => 'KPI Review';

  @override
  String kpiReviewKpiReviewFor(Object reviewDate) {
    return 'KPI Review for $reviewDate';
  }

  @override
  String get kpiReviewJudgeEachKpiOfTheMtuLine =>
      'Judge each KPI of the MTU line against its Daily Target: met, missed or not measured.';

  @override
  String get kpiReviewNoKpisToReview => 'No KPIs to review';

  @override
  String get kpiReviewTheKpiCatalogueHasNoKpiYet =>
      'The KPI catalogue has no KPI yet.';

  @override
  String get kpiReviewByTitle => 'By title.';

  @override
  String kpiReviewNoKpiOfTheReviewMatchesTry(Object term) {
    return 'No KPI of the review matches \"$term\". Try a different title, or clear the filter.';
  }

  @override
  String get kpiReview1ChangedKpiIsHiddenByThe =>
      '1 changed KPI is hidden by the search.';

  @override
  String kpiReviewChangedKpisAreHiddenByTheSearch(Object hiddenChanges) {
    return '$hiddenChanges changed KPIs are hidden by the search.';
  }

  @override
  String kpiReviewSavedFor(Object savedCount, Object value, Object reviewDate) {
    return 'Saved $savedCount $value for $reviewDate.';
  }

  @override
  String get kpiReviewNoTarget => 'No target';

  @override
  String kpiReviewDailyTarget(Object targetText) {
    return 'Daily target: $targetText';
  }

  @override
  String get kpiReviewReadTheNote => 'Read the note';

  @override
  String get kpiReviewWhyWasItMissed => 'Why was it missed?';

  @override
  String kpiReviewWhyWasTheTargetMissed(Object targetText) {
    return 'Why was the Target ($targetText) missed?';
  }

  @override
  String kpiReviewANoteOfAtLeastCharactersIs(
    Object minNoteLength,
    Object length,
  ) {
    return 'A note of at least $minNoteLength characters is required when a KPI is missed ($length so far).';
  }

  @override
  String get kpiReviewEdit => 'Edit';

  @override
  String get kpiTargetsTheTargetsCouldNotBeRead =>
      'The Targets could not be read';

  @override
  String kpiTargetsKpiTargets(Object direction, Object unit) {
    return 'KPI Targets, $direction $unit';
  }

  @override
  String get kpiTargetsCurrentlyInForce => 'Currently in force';

  @override
  String get kpiTargetsWhatEachGrainIsJudgedAgainstToday =>
      'What each grain is judged against today, and from when.';

  @override
  String get kpiTargetsNoTargetIsInForceToday => 'No Target is in force today.';

  @override
  String kpiTargetsFrom(Object grain, Object value, Object validFrom) {
    return '$grain: $value (from $validFrom)';
  }

  @override
  String get kpiTargetsHistory => 'History';

  @override
  String get kpiTargetsNewestFirstAnEntryIsNeverEdited =>
      'Newest first. An entry is never edited — a later one supersedes it.';

  @override
  String get kpiTargetsNoTargetHasBeenSet => 'No Target has been set';

  @override
  String get kpiTargetsEveryEntryMadeForThisKpiWill =>
      'Every entry made for this KPI will be listed here.';

  @override
  String get assetFormCorrectDetails => 'Correct details';

  @override
  String get commonAddAnAsset => 'Add an Asset';

  @override
  String get assetFormAddAsset => 'Add Asset';

  @override
  String get assetFormUniqueAcrossTheWholePlatformNotJust =>
      'Unique across the whole Platform, not just this Site.';

  @override
  String get assetFormKind => 'Kind';

  @override
  String get commonCriticality => 'Criticality';

  @override
  String get assetFormWhereThisAssetSitsIsChangedWith =>
      'Where this Asset sits is changed with its own \"Change Org Unit…\" action.';

  @override
  String assetFormThisAssetWillSitAt(Object value) {
    return 'This Asset will sit at $value.';
  }

  @override
  String get assetMoveChangeWhereThisAssetSits =>
      'Change where this Asset sits';

  @override
  String get assetMoveChangeOrgUnit => 'Change Org Unit';

  @override
  String assetMoveSitsAtNow(Object name, Object code, Object orgUnitName) {
    return '$name ($code) sits at $orgUnitName now.';
  }

  @override
  String get assetMoveMoveItTo => 'Move it to';

  @override
  String get assetMoveWhereThisAssetWillSitItDecides =>
      'Where this Asset will sit. It decides who may raise and close work against it; work already recorded against it stays where it happened.';

  @override
  String assetMoveThisAssetWillSitAt(Object value) {
    return 'This Asset will sit at $value.';
  }

  @override
  String get assetsTheRegisterCouldNotBeRead =>
      'The register could not be read';

  @override
  String get assetsNoAssetsOnTheRegisterYet => 'No Assets on the register yet';

  @override
  String get assetsNothingHasBeenRecordedAtThisSite =>
      'Nothing has been recorded at this Site. Add a machine and it can be worked on the same day.';

  @override
  String get assetsEveryMachineOnTheRegisterAtThis =>
      'Every machine on the register at this Site, and the Org Unit each one sits at.';

  @override
  String get assetsShowRetired => 'Show retired';

  @override
  String get assetsFilterAssets => 'Filter Assets';

  @override
  String get assetsNoAssetsMatch => 'No Assets match';

  @override
  String assetsThisSiteHasAssetsOnTheRegister(Object term) {
    return 'This Site has Assets on the register, but none matches \"$term\". Try a different name or code, or clear the filter.';
  }

  @override
  String get assetsCodeType => 'Code · Type';

  @override
  String get assetsCorrectDetails => 'Correct details…';

  @override
  String get assetsChangeOrgUnit => 'Change Org Unit…';

  @override
  String get assetsDetach => 'Detach';

  @override
  String get assetsNestUnder => 'Nest under…';

  @override
  String get assetsRetireThisAsset => 'Retire this Asset?';

  @override
  String assetsWillNoLongerAppearOnTheActive(Object name) {
    return '$name will no longer appear on the active register. Nothing is deleted, and it can be reinstated at any time.';
  }

  @override
  String get assetsThereIsNothingElseOnThisRegister =>
      'There is nothing else on this register it could sit beneath.';

  @override
  String get breakdownReportReportABreakdown => 'Report a Breakdown';

  @override
  String get breakdownReportReport => 'Report';

  @override
  String get breakdownReportStartedAtOptional => 'Started at (optional)';

  @override
  String get commonLeaveBlankToRecordNow => 'Leave blank to record now.';

  @override
  String downtimeClassifyClassifyTheStopFor(Object assetName) {
    return 'Classify the stop for $assetName';
  }

  @override
  String get downtimeClassifyKeepItUnclassified => 'Keep it unclassified';

  @override
  String get downtimeClassifyDescriptionRequired => 'Description (required)';

  @override
  String get downtimeClassifyTheDowntimeReasonsCouldNotBeRead =>
      'The Downtime reasons could not be read.';

  @override
  String downtimeCloseCloseTheStopFor(Object assetName) {
    return 'Close the stop for $assetName?';
  }

  @override
  String get commonKeepItOpen => 'Keep it open';

  @override
  String get downtimeCloseCloseThisStop => 'Close this stop';

  @override
  String get downtimeCloseTheMachineIsRunningAgainTheServer =>
      'The machine is running again. The server records how long it was down.';

  @override
  String get downtimeCloseEndedAtOptional => 'Ended at (optional)';

  @override
  String get floorTheFloorWorkCouldNotBeLoaded =>
      'The floor work could not be loaded';

  @override
  String get floorNoOpenWork => 'No open work';

  @override
  String floorThereIsNoOpenWorkForRight(Object orgUnitName) {
    return 'There is no open work for $orgUnitName right now.';
  }

  @override
  String get floorRefresh => 'Refresh';

  @override
  String get floorFloorWork => 'Floor work';

  @override
  String get floorObservation => 'Observation';

  @override
  String get floorMyTraining => 'My training';

  @override
  String floorTechnicianComplete(Object workOrderNo) {
    return 'Complete $workOrderNo';
  }

  @override
  String floorTechnicianStart(Object workOrderNo) {
    return 'Start $workOrderNo';
  }

  @override
  String get floorTechnicianWhoIsRecordingThisYourEmployeeNumber =>
      'Who is recording this? Your Employee number and PIN identify you for this action only.';

  @override
  String get commonWhatWasFound => 'What was found?';

  @override
  String get myRequestsYourRequestsCouldNotBeRead =>
      'Your requests could not be read';

  @override
  String get myRequestsWhatYouRaisedAndWhatBecameOf =>
      'What you raised, and what became of each.';

  @override
  String get commonRaiseARequest => 'Raise a Request';

  @override
  String myRequestsYouHaveRequestsAtThisSiteBut(Object term) {
    return 'You have Requests at this Site, but none matches \"$term\". Try a different description or Asset.';
  }

  @override
  String get myRequestsOutcome => 'Outcome';

  @override
  String myRequestsBecameWorkOrder(Object workOrderNo) {
    return 'Became Work order $workOrderNo';
  }

  @override
  String myRequestsDeclined(Object rejectionReason) {
    return 'Declined: $rejectionReason';
  }

  @override
  String get myRequestsNothingRaisedYet => 'Nothing raised yet';

  @override
  String get myRequestsYouHaveNotRaisedAnyRequestsAt =>
      'You have not raised any Requests at this Site. Raise one and it will show up here with whatever becomes of it.';

  @override
  String get commonAddPart => 'Add part';

  @override
  String get commonPartNumber => 'Part number';

  @override
  String get partsThePartsCatalogueCouldNotBeRead =>
      'The parts catalogue could not be read';

  @override
  String get partsTheSharedCatalogueDefinedOnceReusedAt =>
      'The shared catalogue — defined once, reused at every Site.';

  @override
  String get partsNoPartsYet => 'No parts yet';

  @override
  String get partsFilterParts => 'Filter parts';

  @override
  String get commonByPartNumberOrDescription =>
      'By part number or description.';

  @override
  String get commonNoPartsMatch => 'No parts match';

  @override
  String partsNothingInTheCatalogueMatchesTryA(Object term) {
    return 'Nothing in the catalogue matches \"$term\". Try a different part number or description, or clear the filter.';
  }

  @override
  String get commonReceiveStock => 'Receive stock';

  @override
  String get receiveReceiving => 'Receiving…';

  @override
  String get receiveReceive => 'Receive';

  @override
  String get receiveReasonOptional => 'Reason (optional)';

  @override
  String get commonRaise => 'Raise';

  @override
  String get requestFormProductionIsStoppedRightNow =>
      'Production is stopped right now';

  @override
  String get storeStockThisStoreCouldNotBeRead =>
      'This store could not be read';

  @override
  String get storeStockBackToStores => 'Back to Stores';

  @override
  String get storeStockNothingOnTheShelf => 'Nothing on the shelf';

  @override
  String get storeStockNoPartHasMovedInOrOut =>
      'No part has moved in or out of this store yet.';

  @override
  String get storeStockFilterStock => 'Filter stock';

  @override
  String storeStockThisStoreHoldsStockButNothingOn(Object term) {
    return 'This store holds stock, but nothing on its shelf matches \"$term\". Try a different part number or description.';
  }

  @override
  String get storesTheStoresCouldNotBeRead => 'The stores could not be read';

  @override
  String get storesTheShelvesThatHoldPartsAtThis =>
      'The shelves that hold parts at this Site.';

  @override
  String get storesNoStoresYet => 'No stores yet';

  @override
  String get storesNothingHereHoldsParts => 'Nothing here holds parts.';

  @override
  String get storesFilterStores => 'Filter stores';

  @override
  String get storesNoStoresMatch => 'No stores match';

  @override
  String storesThisSiteHasStoresButNoneMatches(Object term) {
    return 'This Site has stores, but none matches \"$term\". Try a different name or code, or clear the filter.';
  }

  @override
  String get storesTappingAStoreShowsWhatIsOn =>
      'Tapping a store shows what is on its shelf.';

  @override
  String get storesCodeOrgUnit => 'Code · Org Unit';

  @override
  String taskReadingRecordAReadingOn(Object value) {
    return 'Record a reading on $value';
  }

  @override
  String get taskReadingWhatTheMeterReads => 'What the meter reads';

  @override
  String get tierBoardOrgUnitFilterNarrowTheBoard => 'Narrow the board';

  @override
  String get tierBoardOrgUnitFilterChooseTheOrgUnitWhoseNumbersAnd =>
      'Choose the Org Unit whose numbers and everything beneath it you want to read, or clear back to the whole Site.';

  @override
  String get tierTheTierBoardCouldNotBeRead =>
      'The tier board could not be read';

  @override
  String get tierTheNumbersThisSiteSWorkProduces =>
      'The numbers this Site\'s work produces, reported under the five Pillars. Every Pillar is shown whether or not anything reports under it yet.';

  @override
  String get tierDate => 'Date';

  @override
  String get tierNoPillarsToShow => 'No Pillars to show';

  @override
  String get tierThisSiteHasNoPillarsToReport =>
      'This Site has no Pillars to report against yet.';

  @override
  String get tierNoDataYet => 'No data yet';

  @override
  String get tierNoKpiIsDefinedUnderThisPillar =>
      'No KPI is defined under this Pillar yet.';

  @override
  String get tierValue => 'Value';

  @override
  String get workOrderAssignFindAPerson => 'Find a person';

  @override
  String get workOrderAssignByNameEmployeeNumberOrTheQualification =>
      'By name, employee number, or the qualification they hold.';

  @override
  String get workOrderAssignTheCandidatesCouldNotBeRead =>
      'The candidates could not be read.';

  @override
  String workOrderAssignNobodyMatchesTryADifferentNameNumber(Object term) {
    return 'Nobody matches \"$term\" — try a different name, number, or skill.';
  }

  @override
  String get workOrderAssignThereIsNobodyThisWorkOrderCould =>
      'There is nobody this Work order could be given to.';

  @override
  String get workOrderAssignNoQualificationsRecorded =>
      'No qualifications recorded';

  @override
  String get workOrderCancelCancelThisWorkOrder => 'Cancel this Work order?';

  @override
  String get workOrderCancelCancelThisWorkOrder2 => 'Cancel this Work order';

  @override
  String get workOrderCancelWhyIsThisBeingCancelledOptional =>
      'Why is this being cancelled? (optional)';

  @override
  String get workOrderCompleteCompleteThisWorkOrder =>
      'Complete this Work order';

  @override
  String get workOrderDialogYouDoNotHoldAWriteGrant =>
      'You do not hold a write Grant that reaches this Work order.';

  @override
  String get workOrderDialogLoadingThisWorkOrder => 'Loading this Work order';

  @override
  String get workOrderDialogThatIsNoLongerAvailable =>
      'That is no longer available';

  @override
  String workOrderDialogThisWorkOrderIsNowWhichNo(Object statusLabel) {
    return 'This Work order is now $statusLabel, which no longer offers this action.';
  }

  @override
  String get workOrderDialogThatWorkOrderIsNotInThis =>
      'That Work order is not in this list';

  @override
  String get workOrderDialogItMayHaveBeenCompletedCancelledOr =>
      'It may have been completed, cancelled, or it is outside the Site or Org Unit the list is currently showing.';

  @override
  String get workOrdersWoBuc202600001 => 'WO-BUC-2026-00001';

  @override
  String get workOrderStatusDraft => 'Draft';

  @override
  String get workOrderStatusApproved => 'Approved';

  @override
  String get workOrderStatusScheduled => 'Scheduled';

  @override
  String get workOrderStatusInProgress => 'In progress';

  @override
  String get workOrderStatusOnHold => 'On hold';

  @override
  String get workOrderStatusCompleted => 'Completed';

  @override
  String get workOrderStatusClosed => 'Closed';

  @override
  String get workOrderStatusCancelled => 'Cancelled';

  @override
  String get workOrderTaskStatusPending => 'Pending';

  @override
  String get workOrderTaskStatusDone => 'Done';

  @override
  String get workOrderTaskStatusSkipped => 'Skipped';

  @override
  String get workOrderTaskStatusFailed => 'Failed';

  @override
  String get workOrderWorkTypeCorrective => 'Corrective';

  @override
  String get workOrderWorkTypePreventive => 'Preventive';

  @override
  String get workOrderWorkTypePredictive => 'Predictive';

  @override
  String get workOrderWorkTypeInspection => 'Inspection';

  @override
  String get workOrderWorkTypeImprovement => 'Improvement';

  @override
  String get workOrderWorkTypeCalibration => 'Calibration';

  @override
  String get partSourceStores => 'Stores';

  @override
  String get partSourcePurchased => 'Purchased';

  @override
  String get partSourceRefurbished => 'Refurbished';

  @override
  String get partSourceCannibalised => 'Cannibalised';

  @override
  String get requestUrgencyLow => 'Low';

  @override
  String get requestUrgencyNormal => 'Normal';

  @override
  String get requestUrgencyHigh => 'High';

  @override
  String get requestUrgencyImmediate => 'Immediate';

  @override
  String get requestStatusNew => 'New';

  @override
  String get requestStatusTriaged => 'Triaged';

  @override
  String get requestStatusAccepted => 'Accepted';

  @override
  String get requestStatusRejected => 'Rejected';

  @override
  String get requestStatusDuplicate => 'Duplicate';

  @override
  String get labourActivityWork => 'Work';

  @override
  String get labourActivityTravel => 'Travel';

  @override
  String get labourActivityWaiting => 'Waiting';

  @override
  String get labourActivityDiagnosis => 'Diagnosis';

  @override
  String get labourActivityDocumentation => 'Documentation';

  @override
  String get meterTypeCumulative => 'Cumulative';

  @override
  String get meterTypeGauge => 'Gauge';

  @override
  String get meterTypeCumulativeExplanation =>
      'Only ever goes up — an hour counter or a cycle count. Only a cumulative meter can drive a PM schedule.';

  @override
  String get meterTypeGaugeExplanation =>
      'May go either way — a temperature, a pressure, an oil level. Recorded, but never scheduled against.';

  @override
  String get pmAnchorDueDate => 'Due date';

  @override
  String get pmAnchorCompletion => 'Completion';

  @override
  String get pmAnchorDueDateExplanation =>
      'The next date is fixed to the calendar: doing the work late does not push the following one back.';

  @override
  String get pmAnchorCompletionExplanation =>
      'The clock starts when the work was actually done, so a service done late simply slides.';

  @override
  String get actionStatusOpen => 'Open';

  @override
  String get actionStatusInProgress => 'In progress';

  @override
  String get actionStatusBlocked => 'Blocked';

  @override
  String get actionStatusDone => 'Done';

  @override
  String get actionStatusCancelled => 'Cancelled';

  @override
  String get actionTypeConcern => 'Concern';

  @override
  String get actionTypeContainment => 'Containment';

  @override
  String get actionTypeCountermeasure => 'Countermeasure';

  @override
  String get actionTypePreventive => 'Preventive action';

  @override
  String get actionTypeImprovement => 'Improvement';

  @override
  String get actionTypeRoutine => 'Routine action';

  @override
  String get actionPhasePlan => 'Plan';

  @override
  String get actionPhaseDo => 'Do';

  @override
  String get actionPhaseCheck => 'Check';

  @override
  String get actionPhaseAct => 'Act';

  @override
  String get actionCheckOutcomeHeld => 'It held';

  @override
  String get actionCheckOutcomeDidNotHold => 'It did not hold';

  @override
  String get actionPriorityWorst => 'P1 — worst';

  @override
  String get actionPriority2 => 'P2';

  @override
  String get actionPriorityNormal => 'P3 — normal';

  @override
  String get actionPriority4 => 'P4';

  @override
  String get actionPriorityLeast => 'P5 — least';

  @override
  String get capaStatusOpen => 'Open';

  @override
  String get capaStatusContainment => 'Contained';

  @override
  String get capaStatusRootCause => 'Root cause';

  @override
  String get capaStatusActions => 'Actions';

  @override
  String get capaStatusVerifying => 'Verifying';

  @override
  String get capaStatusClosed => 'Closed';

  @override
  String get capaStatusCancelled => 'Cancelled';

  @override
  String get capaMethod8d => '8D';

  @override
  String get capaMethodFiveWhy => '5 Why';

  @override
  String get capaMethodA3 => 'A3';

  @override
  String get capaMethodSimple => 'Simple';

  @override
  String get capaChainOccurrence => 'Why it happened';

  @override
  String get capaChainEscape => 'Why it was not detected';

  @override
  String get capaCauseCategoryMan => 'Man';

  @override
  String get capaCauseCategoryMachine => 'Machine';

  @override
  String get capaCauseCategoryMethod => 'Method';

  @override
  String get capaCauseCategoryMaterial => 'Material';

  @override
  String get capaCauseCategoryMeasurement => 'Measurement';

  @override
  String get capaCauseCategoryEnvironment => 'Environment';

  @override
  String get capaCauseVerdictCandidate => 'Candidate';

  @override
  String get capaCauseVerdictConfirmed => 'Confirmed';

  @override
  String get capaCauseVerdictRuledOut => 'Ruled out';

  @override
  String get capaEffectivenessHeld => 'The fix held';

  @override
  String get capaEffectivenessDidNotHold => 'The fix did not hold';

  @override
  String get safetyIncidentStatusOpen => 'Open';

  @override
  String get safetyIncidentStatusInvestigating => 'Investigating';

  @override
  String get safetyIncidentStatusActionsPending => 'Actions pending';

  @override
  String get safetyIncidentStatusClosed => 'Closed';

  @override
  String get safetyIncidentTypeInjury => 'Injury';

  @override
  String get safetyIncidentTypeNearMiss => 'Near miss';

  @override
  String get safetyIncidentTypePropertyDamage => 'Property damage';

  @override
  String get safetyIncidentTypeEnvironmental => 'Environmental';

  @override
  String get safetyIncidentTypeFire => 'Fire';

  @override
  String get safetyIncidentTypeErgonomic => 'Ergonomic';

  @override
  String get safetyIncidentTypeSecurity => 'Security';

  @override
  String get safetySeverityNoInjury => 'No injury';

  @override
  String get safetySeverityFirstAid => 'First aid';

  @override
  String get safetySeverityMedicalTreatment => 'Medical treatment';

  @override
  String get safetySeverityRestrictedWork => 'Restricted work';

  @override
  String get safetySeverityLostTime => 'Lost time';

  @override
  String get safetySeverityFatality => 'Fatality';

  @override
  String get safetyObservationTypeSafeAct => 'Safe act';

  @override
  String get safetyObservationTypeUnsafeAct => 'Unsafe act';

  @override
  String get safetyObservationTypeUnsafeCondition => 'Unsafe condition';

  @override
  String get safetyObservationCategoryPpe => 'PPE';

  @override
  String get safetyObservationCategoryMachineGuarding => 'Machine guarding';

  @override
  String get safetyObservationCategoryHousekeeping => 'Housekeeping';

  @override
  String get safetyObservationCategoryErgonomics => 'Ergonomics';

  @override
  String get safetyObservationCategoryChemical => 'Chemical';

  @override
  String get safetyObservationCategoryWorkingAtHeight => 'Working at height';

  @override
  String get safetyObservationCategoryTraffic => 'Traffic';

  @override
  String get safetyObservationCategoryEnergyIsolation => 'Energy isolation';

  @override
  String get safetyObservationCategoryProcedure => 'Procedure';

  @override
  String get safetyObservationCategoryOther => 'Other';

  @override
  String get safetyPotentialLow => 'Low';

  @override
  String get safetyPotentialMedium => 'Medium';

  @override
  String get safetyPotentialHigh => 'High';

  @override
  String get safetyPotentialFatal => 'Fatal';

  @override
  String get bodyPartRegionHead => 'Head';

  @override
  String get bodyPartRegionTrunk => 'Trunk';

  @override
  String get bodyPartRegionUpperLimb => 'Upper limb';

  @override
  String get bodyPartRegionLowerLimb => 'Lower limb';

  @override
  String get bodyPartRegionMultiple => 'Multiple';

  @override
  String get bodyPartRegionOther => 'Other';

  @override
  String get roleOperator => 'Operator';

  @override
  String get roleSupervisor => 'Supervisor';

  @override
  String get roleEngineer => 'Engineer';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleAdministrator => 'Administrator';

  @override
  String get roleOperatorDescription =>
      'Works in the Org Units this Account is granted.';

  @override
  String get roleSupervisorDescription =>
      'Runs the Org Units this Account is granted, and the people in them.';

  @override
  String get roleEngineerDescription =>
      'Improves the Org Units this Account is granted.';

  @override
  String get roleManagerDescription =>
      'Oversees the Org Units this Account is granted.';

  @override
  String get roleAdministratorDescription =>
      'Acts everywhere, in every Site, with no Org Unit Grants at all.';

  @override
  String get employmentTypePermanent => 'Permanent';

  @override
  String get employmentTypeTemporary => 'Temporary';

  @override
  String get employmentTypeAgency => 'Agency';

  @override
  String get employmentTypeContractor => 'Contractor';

  @override
  String get employmentTypeApprentice => 'Apprentice';

  @override
  String get trainingEvaluationPaper => 'Paper';

  @override
  String get trainingEvaluationJobTraining => 'Job-training';

  @override
  String get trainingStatusDraft => 'Draft';

  @override
  String get trainingStatusSent => 'Sent';

  @override
  String get attendanceStatusPresent => 'Present';

  @override
  String get attendanceStatusLate => 'Late';

  @override
  String get attendanceStatusAbsentPlanned => 'Absent (planned)';

  @override
  String get attendanceStatusAbsentUnplanned => 'Absent (unplanned)';

  @override
  String get attendanceStatusTraining => 'Training';

  @override
  String get attendanceStatusNotScheduled => 'Not scheduled';

  @override
  String get attendanceSheetStateMissing => 'Not opened yet';

  @override
  String get attendanceSheetStateUnconfirmed => 'Started, not yet confirmed';

  @override
  String get leaveRequestStatusPending => 'Pending';

  @override
  String get leaveRequestStatusApproved => 'Approved';

  @override
  String get leaveRequestStatusRejected => 'Rejected';

  @override
  String get leaveRequestStatusCancelled => 'Cancelled';

  @override
  String get costRateScopeSite => 'Site';

  @override
  String get costRateScopeOrgUnit => 'Org Unit';

  @override
  String get costRateScopeAsset => 'Asset';

  @override
  String get costRateScopeCostCentre => 'Cost centre';

  @override
  String get costRateTypeLabourPerHour => 'Labour, per hour';

  @override
  String get costRateTypeOvertimePremium => 'Overtime premium, a multiplier';

  @override
  String get costRateTypeMachineDowntime => 'Machine downtime, per hour';

  @override
  String get costRateTypeOverhead => 'Overhead, per hour';

  @override
  String get costRateTypeReworkLabour => 'Rework labour, per hour';

  @override
  String get nonconformanceStatusOpen => 'Open';

  @override
  String get nonconformanceStatusContained => 'Contained';

  @override
  String get nonconformanceStatusDispositioned => 'Dispositioned';

  @override
  String get nonconformanceStatusClosed => 'Closed';

  @override
  String get nonconformanceStatusCancelled => 'Cancelled';

  @override
  String get dispositionScrap => 'Scrap';

  @override
  String get dispositionRework => 'Rework';

  @override
  String get dispositionReturnToSupplier => 'Return to supplier';

  @override
  String get dispositionUseAsIs => 'Use as is';

  @override
  String get dispositionConcession => 'Concession';

  @override
  String get severityChangeLowered => 'Severity lowered';

  @override
  String get noticeSessionEnded =>
      'This session has ended. Sign in again to continue.';

  @override
  String get noticeActionInFlight =>
      'Another action is already in progress. Try again in a moment.';

  @override
  String get noticeDeviceNotRegistered =>
      'This device is not registered. Ask an administrator to register it against an Org Unit.';

  @override
  String get noticeIdentificationExpired =>
      'Your identification has expired. Identify yourself again.';

  @override
  String get noticeAccountAlreadyMoved =>
      'Another administrator has already changed that Account. The list has been refreshed.';

  @override
  String get noticeAccountAlreadyDecided =>
      'Another administrator has already dealt with that Account. The queue has been refreshed.';

  @override
  String noticeEmployeeLeft(String name) {
    return '$name has left.';
  }

  @override
  String noticeEmployeeBack(String name) {
    return '$name is back.';
  }

  @override
  String noticeAssetBack(String code) {
    return '$code is back on the active register.';
  }

  @override
  String get noticeNoSitesActionLog =>
      'There are no Sites you can see, so there is no action log to show.';

  @override
  String get noticeNoSitesRegister =>
      'There are no Sites you can see, so there is no register to show.';

  @override
  String get noticeNoSitesStores =>
      'There are no Sites you can see, so there are no stores to show.';

  @override
  String get noticeNoSitesCoverage =>
      'There are no Sites you can see, so there is no coverage to show.';

  @override
  String get noticeNoSitesKpiCatalogue =>
      'There are no Sites you can see, so there is no KPI catalogue to show.';

  @override
  String get noticeNoSitesKpiTargets =>
      'There are no Sites you can see, so there are no Targets to show.';

  @override
  String get noticeNoSitesKpiReview =>
      'There are no Sites you can see, so there is no KPI Review to show.';

  @override
  String get noticeNoSitesBoard =>
      'There are no Sites you can see, so there is no board to show.';

  @override
  String get noticeNoSitesWork =>
      'There are no Sites you can see, so there is no work to show.';

  @override
  String get noticeNoSitesWaiting =>
      'There are no Sites you can see, so there is nothing waiting.';

  @override
  String get noticeNoSitesNothing =>
      'There are no Sites you can see, so there is nothing to show.';

  @override
  String noticeAssetRetired(String code) {
    return '$code has been retired.';
  }

  @override
  String noticeMeasureAnswers(String actionNo, String kind) {
    return '$actionNo answers this — a $kind.';
  }

  @override
  String noticeActionClosed(String actionNo) {
    return '$actionNo is closed — its Act named the standard that now holds it.';
  }

  @override
  String noticeActionAwaitingPhase(String actionNo, String phase) {
    return '$actionNo is waiting on its $phase phase.';
  }

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get defectSeverityMinor => 'Minor';

  @override
  String get defectSeverityMajor => 'Major';

  @override
  String get defectSeverityCritical => 'Critical';

  @override
  String get correctionKindReopened => 'Reopened';

  @override
  String get correctionKindCancelled => 'Cancelled';

  @override
  String correctionSummarySeverityLowered(String from, String to) {
    return 'Severity lowered from $from to $to';
  }

  @override
  String correctionSummaryReopened(String status) {
    return 'Reopened from $status';
  }

  @override
  String correctionSummaryCancelled(String status) {
    return 'Cancelled from $status';
  }

  @override
  String incidentEventSeverityChanged(String from, String to) {
    return 'Severity changed from $from to $to';
  }

  @override
  String incidentEventStatusMoved(String from, String to) {
    return 'Status moved from $from to $to';
  }

  @override
  String incidentEventDaysRecorded(String days) {
    return 'Days recorded: $days';
  }

  @override
  String get incidentEventClosed => 'Closed';

  @override
  String get incidentEventClassified => 'Classified';

  @override
  String get detectionPointIncoming => 'Incoming';

  @override
  String get detectionPointInProcess => 'In process';

  @override
  String get detectionPointFinalInspection => 'Final inspection';

  @override
  String get detectionPointAudit => 'Audit';

  @override
  String get detectionPointCustomer => 'Customer';

  @override
  String get safetyAnySeverity => 'Choose a rung';

  @override
  String get safetySeverityRecordableSuffix => ' · recordable';

  @override
  String get complaintStatusOpen => 'Open';

  @override
  String get complaintStatusInvestigating => 'Investigating';

  @override
  String get complaintStatusResponded => 'Responded';

  @override
  String get complaintStatusClosed => 'Closed';

  @override
  String get complaintStatusRejected => 'Rejected';

  @override
  String get complaintTypeQuality => 'Quality';

  @override
  String get complaintTypeDelivery => 'Delivery';

  @override
  String get complaintTypeQuantity => 'Quantity';

  @override
  String get complaintTypeDocumentation => 'Documentation';

  @override
  String get complaintTypePackaging => 'Packaging';

  @override
  String get complaintTypeService => 'Service';

  @override
  String get supplierNcrStatusOpen => 'Open';

  @override
  String get supplierNcrStatusIssued => 'Issued';

  @override
  String get supplierNcrStatusResponded => 'Responded';

  @override
  String get supplierNcrStatusClosed => 'Closed';

  @override
  String get supplierNcrStatusRejected => 'Rejected';

  @override
  String get supplierNcrDispositionReturnToSupplier => 'Return to the Supplier';

  @override
  String get supplierNcrDispositionScrap => 'Scrap';

  @override
  String get supplierNcrDispositionReworkAtCost =>
      'Rework at the Supplier\'s cost';

  @override
  String get supplierNcrDispositionSort => 'Sort';

  @override
  String get supplierNcrDispositionUseAsIs => 'Use as it is';

  @override
  String get downtimeStatusOpen => 'Open';

  @override
  String get downtimeStatusUnclassified => 'Unclassified';

  @override
  String get downtimeStatusClosed => 'Closed';

  @override
  String get assetTypeMachine => 'Machine';

  @override
  String get assetTypeCell => 'Cell';

  @override
  String get assetTypeTool => 'Tool';

  @override
  String get assetTypeUtility => 'Utility';

  @override
  String get assetTypeVehicle => 'Vehicle';

  @override
  String get assetTypeOther => 'Other';

  @override
  String get assetCriticalityLow => 'Low';

  @override
  String get assetCriticalityMedium => 'Medium';

  @override
  String get assetCriticalityHigh => 'High';

  @override
  String get assetCriticalityCritical => 'Critical';

  @override
  String get defectCategoryProduct => 'Product';

  @override
  String get defectCategoryProcess => 'Process';

  @override
  String get defectCategoryMaterial => 'Material';

  @override
  String get defectCategoryDocumentation => 'Documentation';

  @override
  String get defectCategoryPackaging => 'Packaging';

  @override
  String get boardKpiStatusOnTarget => 'On target';

  @override
  String get boardKpiStatusNearTarget => 'Near target';

  @override
  String get boardKpiStatusOffTarget => 'Off target';

  @override
  String get boardKpiStatusNoTarget => 'No target';

  @override
  String get boardKpiStatusNoData => 'No data';

  @override
  String get reviewStatusMet => 'Met';

  @override
  String get reviewStatusMissed => 'Missed';

  @override
  String get reviewStatusNotMeasured => 'Not measured';

  @override
  String get reviewStatusNotReviewed => 'Not reviewed';

  @override
  String get issueKindNonconformance => 'Non-conformance';

  @override
  String get issueKindComplaint => 'Customer complaint';

  @override
  String get issueKindNonconformanceShort => 'NC';

  @override
  String get issueKindComplaintShort => 'Complaint';

  @override
  String get handoverMachineRunning => 'Running';

  @override
  String get handoverMachineRunningManual => 'Running (manual)';

  @override
  String get handoverMachineIdle => 'Idle';

  @override
  String get handoverMachineDown => 'Down';

  @override
  String get handoverMachineMaintenance => 'Maintenance';

  @override
  String get handoverMachineCleaning => 'Cleaning';

  @override
  String get handoverMachineChangeover => 'Changeover';

  @override
  String get handoverMachineIsolated => 'Isolated';

  @override
  String get handoverAbnormalityMinorFlaw => 'Minor flaw';

  @override
  String get handoverAbnormalityUnfulfilledBasicCondition =>
      'Unfulfilled basic condition';

  @override
  String get handoverAbnormalityInaccessiblePlace => 'Inaccessible place';

  @override
  String get handoverAbnormalityContaminationSource => 'Contamination source';

  @override
  String get handoverAbnormalityQualityDefectSource => 'Quality defect source';

  @override
  String get handoverAbnormalityUnnecessaryItem => 'Unnecessary item';

  @override
  String get handoverAbnormalityUnsafePlace => 'Unsafe place';

  @override
  String get handoverDimensionMan => 'Man';

  @override
  String get handoverDimensionMachine => 'Machine';

  @override
  String get handoverDimensionMaterial => 'Material';

  @override
  String get handoverDimensionMethod => 'Method';

  @override
  String get handoverDispositionCarried => 'Carried';

  @override
  String get handoverDispositionReassigned => 'Reassigned';

  @override
  String get handoverDispositionClosed => 'Closed';

  @override
  String get handoverWatchOk => 'OK';

  @override
  String get handoverWatchConcern => 'Concern';

  @override
  String get handoverWatchNotRun => 'Not run';

  @override
  String get handoverDeviationNone => 'None';

  @override
  String get handoverDeviationLate => 'Late';

  @override
  String get handoverDeviationPartial => 'Partial';

  @override
  String get handoverDeviationNoIncomingTeamLeader => 'No incoming Team Leader';

  @override
  String get handoverExceptionNoHandover => 'No handover recorded';

  @override
  String get handoverExceptionUnacknowledged => 'Unacknowledged';

  @override
  String get handoverExceptionAmendedAfterAcknowledgement =>
      'Amended after acknowledgement';

  @override
  String get handoverStatusSubmitted => 'Submitted';

  @override
  String get handoverStatusAcknowledged => 'Acknowledged';

  @override
  String get skillCoverageNobodyQualified => 'Nobody qualified';

  @override
  String get skillCoveragePartlyQualified => 'Partly qualified';

  @override
  String get skillCoverageLegendShort => 'Short';

  @override
  String get accountsStandingRejected => 'Rejected';

  @override
  String get accountsStandingActive => 'Active';

  @override
  String get accountsStandingDeactivated => 'Deactivated';

  @override
  String get accountsStandingAwaitingApproval => 'Awaiting Approval';

  @override
  String get grantLevelView => 'View';

  @override
  String get grantLevelViewAndEdit => 'View and edit';

  @override
  String get boardPeriodShift => 'Shift';

  @override
  String get boardPeriodDay => 'Day';

  @override
  String get boardPeriodWeek => 'Week';

  @override
  String get boardPeriodMonth => 'Month';
}
