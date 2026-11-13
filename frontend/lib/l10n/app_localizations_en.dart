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
}
