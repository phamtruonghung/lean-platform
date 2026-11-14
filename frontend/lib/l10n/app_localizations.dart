import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// The app's own name, drawn in the sidebar's brand row.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get shellBrand;

  /// The skip link that appears at the top of the Shell when it takes keyboard focus.
  ///
  /// In en, this message translates to:
  /// **'Skip to content'**
  String get shellSkipToContent;

  /// Tooltip on the account footer, which opens the account menu.
  ///
  /// In en, this message translates to:
  /// **'Account menu'**
  String get shellAccountMenu;

  /// Account menu item that opens the change-password dialog.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get shellChangePassword;

  /// Account menu item that switches between the light and dark palettes, and the tooltip on the Shell's palette switch when a tap gives the dark palette.
  ///
  /// In en, this message translates to:
  /// **'Dark palette'**
  String get shellDarkPalette;

  /// Tooltip on the Shell's palette switch when a tap gives the light palette.
  ///
  /// In en, this message translates to:
  /// **'Light palette'**
  String get shellLightPalette;

  /// Tooltip on the sign-out button in the Shell's footer.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get shellSignOut;

  /// Title of the Settings Screen, and its Destination in the sidebar.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// One-line description under the Settings title.
  ///
  /// In en, this message translates to:
  /// **'How the Platform looks, and the language it speaks.'**
  String get settingsDescription;

  /// Heading of the Settings row that chooses the interface language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// What the language control does, under its heading.
  ///
  /// In en, this message translates to:
  /// **'Applies across the whole Platform at once, and is remembered on this browser.'**
  String get settingsLanguageHelp;

  /// The English option of the language control. Written in the language it names, so a reader who cannot read the current language can still find their own.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// The Vietnamese option of the language control. Written in the language it names, so a reader who cannot read the current language can still find their own.
  ///
  /// In en, this message translates to:
  /// **'Vietnamese'**
  String get settingsLanguageVietnamese;

  /// Sidebar heading over the People Module's Destinations.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get groupPeople;

  /// Sidebar heading over the Maintenance Module's Destinations.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get groupMaintenance;

  /// Sidebar heading over the Quality Module's Destinations.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get groupQuality;

  /// Sidebar heading over the Actions Module's Destinations.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get groupActions;

  /// Sidebar heading over the Safety Module's Destinations.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get groupSafety;

  /// Sidebar heading over the Production Module's Destinations.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get groupProduction;

  /// Sidebar heading over the KPI Module's Destinations.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get groupInsights;

  /// Sidebar heading over accounts and roles.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get groupAdministration;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navDirectory.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get navDirectory;

  /// No description provided for @navJobRoles.
  ///
  /// In en, this message translates to:
  /// **'Job roles'**
  String get navJobRoles;

  /// No description provided for @navSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get navSkills;

  /// No description provided for @navOrgUnits.
  ///
  /// In en, this message translates to:
  /// **'Org Units'**
  String get navOrgUnits;

  /// No description provided for @navAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get navAttendance;

  /// No description provided for @navTraining.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get navTraining;

  /// No description provided for @navMySignature.
  ///
  /// In en, this message translates to:
  /// **'My signature'**
  String get navMySignature;

  /// No description provided for @navLeaveRequests.
  ///
  /// In en, this message translates to:
  /// **'Leave requests'**
  String get navLeaveRequests;

  /// No description provided for @navCostRates.
  ///
  /// In en, this message translates to:
  /// **'Cost rates'**
  String get navCostRates;

  /// No description provided for @navProductStandardCosts.
  ///
  /// In en, this message translates to:
  /// **'Product standard costs'**
  String get navProductStandardCosts;

  /// No description provided for @navAssets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get navAssets;

  /// No description provided for @navParts.
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get navParts;

  /// No description provided for @navStores.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get navStores;

  /// No description provided for @navWorkOrders.
  ///
  /// In en, this message translates to:
  /// **'Work orders'**
  String get navWorkOrders;

  /// No description provided for @navMyRequests.
  ///
  /// In en, this message translates to:
  /// **'My requests'**
  String get navMyRequests;

  /// No description provided for @navTriageQueue.
  ///
  /// In en, this message translates to:
  /// **'Triage queue'**
  String get navTriageQueue;

  /// No description provided for @navDowntime.
  ///
  /// In en, this message translates to:
  /// **'Downtime'**
  String get navDowntime;

  /// No description provided for @navPmSchedules.
  ///
  /// In en, this message translates to:
  /// **'PM schedules'**
  String get navPmSchedules;

  /// No description provided for @navMeters.
  ///
  /// In en, this message translates to:
  /// **'Meters'**
  String get navMeters;

  /// No description provided for @navJobPlans.
  ///
  /// In en, this message translates to:
  /// **'Job plans'**
  String get navJobPlans;

  /// No description provided for @navTierBoard.
  ///
  /// In en, this message translates to:
  /// **'Tier board'**
  String get navTierBoard;

  /// No description provided for @navSkillCoverage.
  ///
  /// In en, this message translates to:
  /// **'Skill coverage'**
  String get navSkillCoverage;

  /// No description provided for @navKpiCatalogue.
  ///
  /// In en, this message translates to:
  /// **'KPI catalogue'**
  String get navKpiCatalogue;

  /// No description provided for @navKpiReview.
  ///
  /// In en, this message translates to:
  /// **'KPI review'**
  String get navKpiReview;

  /// No description provided for @navActionLog.
  ///
  /// In en, this message translates to:
  /// **'Action log'**
  String get navActionLog;

  /// No description provided for @navProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get navProducts;

  /// No description provided for @navDefectCodes.
  ///
  /// In en, this message translates to:
  /// **'Defect codes'**
  String get navDefectCodes;

  /// No description provided for @navNonConformances.
  ///
  /// In en, this message translates to:
  /// **'Non-conformances'**
  String get navNonConformances;

  /// No description provided for @navCapas.
  ///
  /// In en, this message translates to:
  /// **'CAPAs'**
  String get navCapas;

  /// No description provided for @navCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get navCustomers;

  /// No description provided for @navCustomerComplaints.
  ///
  /// In en, this message translates to:
  /// **'Customer complaints'**
  String get navCustomerComplaints;

  /// No description provided for @navSlideShow.
  ///
  /// In en, this message translates to:
  /// **'Slide show'**
  String get navSlideShow;

  /// No description provided for @navSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get navSuppliers;

  /// No description provided for @navSupplierNcrs.
  ///
  /// In en, this message translates to:
  /// **'Supplier NCRs'**
  String get navSupplierNcrs;

  /// No description provided for @navIncidents.
  ///
  /// In en, this message translates to:
  /// **'Incidents'**
  String get navIncidents;

  /// No description provided for @navObservations.
  ///
  /// In en, this message translates to:
  /// **'Observations'**
  String get navObservations;

  /// No description provided for @navInjuryTypes.
  ///
  /// In en, this message translates to:
  /// **'Injury types'**
  String get navInjuryTypes;

  /// No description provided for @navBodyParts.
  ///
  /// In en, this message translates to:
  /// **'Body parts'**
  String get navBodyParts;

  /// No description provided for @navShiftHandovers.
  ///
  /// In en, this message translates to:
  /// **'Shift handovers'**
  String get navShiftHandovers;

  /// No description provided for @navApprovals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get navApprovals;

  /// No description provided for @navAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get navAccounts;

  /// No description provided for @navRoles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get navRoles;

  /// A dialog's button that abandons it without saving anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// A submit button's label while its request is in flight.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get commonSaving;

  /// Label of the field where the signed-in person types the password they already have.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get accountPasswordCurrent;

  /// Label of the field where the signed-in person types the password they want.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get accountPasswordNew;

  /// Helper text under the new-password field, stating the shortest password the server accepts.
  ///
  /// In en, this message translates to:
  /// **'At least {count} characters.'**
  String accountPasswordMinimum(int count);

  /// Shown in the change-password dialog when the current-password field was left empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password.'**
  String get accountPasswordCurrentRequired;

  /// Shown in the change-password dialog when the new password is shorter than the server's minimum.
  ///
  /// In en, this message translates to:
  /// **'Use at least {count} characters for the new password.'**
  String accountPasswordTooShort(int count);

  /// Confirmation shown on the Shell once the change has landed.
  ///
  /// In en, this message translates to:
  /// **'Your password was changed.'**
  String get accountPasswordChanged;

  /// The Home Screen's title, greeting the signed-in person by their display name.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String homeGreeting(String name);

  /// What Home says when every count it shows is zero.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting on you.'**
  String get homeNothingWaiting;

  /// Home's Actions group when its count could not be read.
  ///
  /// In en, this message translates to:
  /// **'Your Actions are unavailable'**
  String get homeActionsUnavailable;

  /// Home's card counting the open Actions whose owner is the signed-in person.
  ///
  /// In en, this message translates to:
  /// **'Assigned to you'**
  String get homeAssignedToYou;

  /// What the Assigned-to-you card counts, under its figure.
  ///
  /// In en, this message translates to:
  /// **'Open Actions whose owner is you'**
  String get homeAssignedToYouCaption;

  /// Stands in for the Assigned-to-you caption when the signed-in Account is not linked to an Employee.
  ///
  /// In en, this message translates to:
  /// **'Your Account is not linked to an Employee record, so no Action can be assigned to you — link one under Accounts'**
  String get homeAccountNotLinked;

  /// Home's People group when the Training-to-confirm count could not be read.
  ///
  /// In en, this message translates to:
  /// **'Your Training to confirm is unavailable'**
  String get homeTrainingUnavailable;

  /// The count of Training records sent to a person that they have not answered yet; a Home card, and a Screen title in the browser tab.
  ///
  /// In en, this message translates to:
  /// **'Training to confirm'**
  String get trainingToConfirm;

  /// What the Training-to-confirm card counts, under its figure.
  ///
  /// In en, this message translates to:
  /// **'Training records sent to you that you have not answered'**
  String get homeTrainingToConfirmCaption;

  /// Home's Maintenance group when the Work order counts could not be read.
  ///
  /// In en, this message translates to:
  /// **'Work orders are unavailable'**
  String get homeWorkOrdersUnavailable;

  /// Home's card counting the Work orders raised and not yet complete.
  ///
  /// In en, this message translates to:
  /// **'Open work orders'**
  String get homeOpenWorkOrders;

  /// What the Open-work-orders card counts, under its figure.
  ///
  /// In en, this message translates to:
  /// **'Raised and not yet complete'**
  String get homeOpenWorkOrdersCaption;

  /// Home's card counting the open Work orders nobody holds yet.
  ///
  /// In en, this message translates to:
  /// **'Awaiting assignment'**
  String get homeAwaitingAssignment;

  /// What the Awaiting-assignment card counts for a person whose view is narrowed to their own Grants.
  ///
  /// In en, this message translates to:
  /// **'On the Org Units granted to you, and everything beneath them'**
  String get homeAwaitingAssignmentScopedCaption;

  /// What the Awaiting-assignment card counts for a person who sees the whole Site.
  ///
  /// In en, this message translates to:
  /// **'Open, with nobody holding them yet'**
  String get homeAwaitingAssignmentCaption;

  /// Home's People group when the Approvals count could not be read.
  ///
  /// In en, this message translates to:
  /// **'Approvals are unavailable'**
  String get homeApprovalsUnavailable;

  /// Home's card counting the Accounts that are waiting to be admitted to the Platform.
  ///
  /// In en, this message translates to:
  /// **'Accounts awaiting Approval'**
  String get accountsAwaitingApproval;

  /// What the Accounts-awaiting-Approval card counts, under its figure.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be admitted'**
  String get homeAccountsAwaitingApprovalCaption;

  /// A Site's own name in a filter: the plant a list is narrowed to.
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get commonSite;

  /// Column header over a record's one-line description, and the field that holds it.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get commonSummary;

  /// The Asset a record is against. The same word the sidebar's Assets Destination uses.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get commonAsset;

  /// Column header over the Org Unit a record belongs to. The same word the sidebar's own Destination uses.
  ///
  /// In en, this message translates to:
  /// **'Org Unit'**
  String get commonOrgUnit;

  /// Column header over a record's status chip.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get commonStatus;

  /// Column header over the person a record is assigned to.
  ///
  /// In en, this message translates to:
  /// **'Assignee'**
  String get commonAssignee;

  /// Column header over a row's own buttons and overflow menu.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get commonActions;

  /// Stands where an assignee's name would be when nobody holds the record yet.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get commonUnassigned;

  /// Tooltip on a row's overflow trigger, which opens the actions that do not fit as buttons.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get commonMoreActions;

  /// How many Work orders the list is showing, above the register.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Work order} other{{count} Work orders}}'**
  String workOrdersCount(int count);

  /// Appended to the count of Work orders on screen while an Org Unit narrows the list.
  ///
  /// In en, this message translates to:
  /// **', narrowed to {name}'**
  String workOrdersCountNarrowed(String name);

  /// Appended to the count of Work orders on screen while the history toggle is on.
  ///
  /// In en, this message translates to:
  /// **', including completed and cancelled'**
  String get workOrdersCountHistory;

  /// The failure state's heading when the list of Work orders could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Work orders could not be read'**
  String get workOrdersUnavailableTitle;

  /// One-line description under the Work orders title.
  ///
  /// In en, this message translates to:
  /// **'The work raised at this Site, which Asset it is against, and who has it.'**
  String get workOrdersDescription;

  /// The button that opens the form for raising a new Work order, and the empty state's own action.
  ///
  /// In en, this message translates to:
  /// **'Raise a Work order'**
  String get workOrdersRaise;

  /// The button, and the picker's title, that narrow the Work order list to one Org Unit.
  ///
  /// In en, this message translates to:
  /// **'Narrow to an Org Unit'**
  String get workOrdersNarrowToOrgUnit;

  /// The chip naming the Org Unit the list is currently narrowed to.
  ///
  /// In en, this message translates to:
  /// **'Narrowed to {name}'**
  String workOrdersNarrowedTo(String name);

  /// Tooltip on the control that clears the Org Unit narrowing from the Work order list.
  ///
  /// In en, this message translates to:
  /// **'Show the whole Site again'**
  String get workOrdersShowWholeSite;

  /// The toggle that brings completed and cancelled Work orders into the list.
  ///
  /// In en, this message translates to:
  /// **'Show completed and cancelled'**
  String get workOrdersShowHistory;

  /// Title of the Org Unit tree inside the Work order list's narrowing picker.
  ///
  /// In en, this message translates to:
  /// **'Narrow the list'**
  String get workOrdersNarrowTitle;

  /// What the narrowing picker's tree is for, under its title.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit to narrow the list to. Everything beneath it is included too.'**
  String get workOrdersNarrowDescription;

  /// Said above the list when the read was capped, rather than leaving the cap to be inferred.
  ///
  /// In en, this message translates to:
  /// **'There are more Work orders than this list shows. Narrow it by Org Unit, or turn history off, to see the rest.'**
  String get workOrdersTruncated;

  /// Label of the search box above the Work order list.
  ///
  /// In en, this message translates to:
  /// **'Filter Work orders'**
  String get workOrdersFilter;

  /// What the Work order list's search box matches on, under its label.
  ///
  /// In en, this message translates to:
  /// **'By summary, Work order number or Asset.'**
  String get workOrdersFilterHelp;

  /// The empty state the search box shows when its term matches none of the rows on screen.
  ///
  /// In en, this message translates to:
  /// **'No Work orders match'**
  String get workOrdersNoMatch;

  /// What the search box's no-match state says, quoting the term that matched nothing.
  ///
  /// In en, this message translates to:
  /// **'Work is open at this Site, but none of it matches “{term}”. Try a different summary or Asset, or clear the filter.'**
  String workOrdersNoMatchMessage(String term);

  /// The primary action on an approved Work order, which starts it.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get workOrdersStart;

  /// The primary action on a Work order that is in progress, which opens its completion form.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get workOrdersComplete;

  /// Column header over the number a Work order is known by.
  ///
  /// In en, this message translates to:
  /// **'WO#'**
  String get workOrdersNumberColumn;

  /// The menu item that assigns a Work order nobody holds yet.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get workOrdersAssign;

  /// The menu item that changes who a Work order is assigned to.
  ///
  /// In en, this message translates to:
  /// **'Reassign'**
  String get workOrdersReassign;

  /// The empty state shown when the list is narrowed to an Org Unit that has no open work.
  ///
  /// In en, this message translates to:
  /// **'No work orders match'**
  String get workOrdersFilteredEmptyTitle;

  /// What the narrowed-to-an-Org-Unit empty state says, with history shown.
  ///
  /// In en, this message translates to:
  /// **'There is work at this Site, but none of it is raised at {name} or beneath it.'**
  String workOrdersFilteredEmptyMessage(String name);

  /// What the narrowed-to-an-Org-Unit empty state says while the list is still open-work only.
  ///
  /// In en, this message translates to:
  /// **'There is work at this Site, but none of it is raised at {name} or beneath it and still open.'**
  String workOrdersFilteredEmptyMessageOpen(String name);

  /// Stands in for the Org Unit's name in the narrowed empty state when the list was narrowed without a name to show.
  ///
  /// In en, this message translates to:
  /// **'this Org Unit'**
  String get workOrdersThisOrgUnit;

  /// The action the narrowed empty state offers, which clears the Org Unit narrowing.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get workOrdersClearFilters;

  /// The empty state shown when there is no work at all, with completed and cancelled included.
  ///
  /// In en, this message translates to:
  /// **'No work at this Site'**
  String get workOrdersNoneExistTitle;

  /// The empty state shown when no Work order is open, with history hidden.
  ///
  /// In en, this message translates to:
  /// **'No open work at this Site'**
  String get workOrdersNoneOpenTitle;

  /// What the genuinely-empty Work order state says, under its title.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been raised against the Org Units you can act in. Raise a Work order and it will show up right away.'**
  String get workOrdersNoneExistMessage;

  /// Label over a Work order's kind of work (corrective, preventive, and the rest).
  ///
  /// In en, this message translates to:
  /// **'Work type'**
  String get commonWorkType;

  /// Label over a Work order's priority number.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get commonPriority;

  /// A number of booked hours, with its unit. The figure is already formatted without a pointless trailing zero.
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String commonHours(String hours);

  /// Stands where a money figure would be when nothing has priced that line yet.
  ///
  /// In en, this message translates to:
  /// **'No cost recorded'**
  String get commonNoCostRecorded;

  /// The failure state's heading when one Work order's detail could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'This Work order could not be read'**
  String get workOrderUnavailableTitle;

  /// The link at the top of a Work order's detail that returns to the list.
  ///
  /// In en, this message translates to:
  /// **'Back to Work orders'**
  String get workOrderBackToList;

  /// The detail Screen's title, and the browser tab's name for it.
  ///
  /// In en, this message translates to:
  /// **'Work order'**
  String get workOrderTitle;

  /// What a Work order's detail holds, shown under the title while it is still loading.
  ///
  /// In en, this message translates to:
  /// **'The tasks copied from the Job plan that raised it.'**
  String get workOrderTasksDescription;

  /// The action that books hours against a Work order.
  ///
  /// In en, this message translates to:
  /// **'Book labour'**
  String get workOrderBookLabour;

  /// The action that fits a part from a Store against a Work order.
  ///
  /// In en, this message translates to:
  /// **'Book a part'**
  String get workOrderBookPart;

  /// Heading of the section listing the steps copied onto a Work order from its Job plan.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get workOrderTasks;

  /// Shown in the Tasks section when the Job plan behind the Work order had no steps.
  ///
  /// In en, this message translates to:
  /// **'No steps were copied onto this Work order.'**
  String get workOrderNoTasks;

  /// Heading of the section reporting the labour and parts booked against a Work order.
  ///
  /// In en, this message translates to:
  /// **'Cost so far'**
  String get workOrderCostSoFar;

  /// Shown in the cost section when no hours have been booked against the Work order.
  ///
  /// In en, this message translates to:
  /// **'No labour has been booked.'**
  String get workOrderNoLabour;

  /// One activity's booked hours, with how much of them was worked overtime.
  ///
  /// In en, this message translates to:
  /// **'{hours} · {overtime} overtime'**
  String workOrderOvertime(String hours, String overtime);

  /// The warning under the labour figures, which stops them being added to plant labour cost.
  ///
  /// In en, this message translates to:
  /// **'Booked labour is part of the plant labour cost already reported, not new money.'**
  String get workOrderLabourNote;

  /// How much of the booked labour was worked overtime.
  ///
  /// In en, this message translates to:
  /// **'{hours} of it is overtime.'**
  String workOrderOvertimeNote(String hours);

  /// Shown in the cost section when no part has been fitted to the Work order.
  ///
  /// In en, this message translates to:
  /// **'No parts have been fitted.'**
  String get workOrderNoParts;

  /// The note beside the parts total, which explains why it is added rather than reported.
  ///
  /// In en, this message translates to:
  /// **'Parts are new cost — the one maintenance component that adds.'**
  String get workOrderPartsNote;

  /// A Work order task's required Skill, named under its instruction.
  ///
  /// In en, this message translates to:
  /// **'Requires {name}'**
  String workOrderRequiresSkill(String name);

  /// Stands in for a task's required Skill when it names none.
  ///
  /// In en, this message translates to:
  /// **'No skill required'**
  String get workOrderNoSkill;

  /// The meter a Work order task records a reading from, under its instruction.
  ///
  /// In en, this message translates to:
  /// **'Records {name}'**
  String workOrderRecordsMeter(String name);

  /// The reading already recorded against a Work order task.
  ///
  /// In en, this message translates to:
  /// **'Reading {value}'**
  String workOrderReading(String value);

  /// The action on a Work order task that records a meter reading.
  ///
  /// In en, this message translates to:
  /// **'Record a reading'**
  String get workOrderRecordReading;

  /// The failure state's heading when the triage queue could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The requests could not be read'**
  String get requestsUnavailableTitle;

  /// One-line description under the Triage queue title.
  ///
  /// In en, this message translates to:
  /// **'The Requests waiting for a decision at this Site. Accepting one raises a Work order for it.'**
  String get requestsDescription;

  /// Label of the search box above the triage queue.
  ///
  /// In en, this message translates to:
  /// **'Filter requests'**
  String get requestsFilter;

  /// What the triage queue's search box matches on, under its label.
  ///
  /// In en, this message translates to:
  /// **'By description, Request number or Asset.'**
  String get requestsFilterHelp;

  /// The empty state the triage queue's search box shows when its term matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No requests match'**
  String get requestsNoMatch;

  /// What the triage queue's no-match state says, quoting the term that matched nothing.
  ///
  /// In en, this message translates to:
  /// **'Requests are waiting at this Site, but none matches “{term}”. Try a different description or Asset.'**
  String requestsNoMatchMessage(String term);

  /// Column header over the number a Request is known by.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get requestsNumberColumn;

  /// Column header over the person who raised a Request.
  ///
  /// In en, this message translates to:
  /// **'Raised by'**
  String get requestsRaisedBy;

  /// Column header over the date a Request was raised.
  ///
  /// In en, this message translates to:
  /// **'Raised'**
  String get requestsRaisedDate;

  /// Column header over how urgent a Request is.
  ///
  /// In en, this message translates to:
  /// **'Urgency'**
  String get requestsUrgency;

  /// Said beside a Request whose own flag says production is stopped because of it.
  ///
  /// In en, this message translates to:
  /// **'Production is stopped'**
  String get requestsProductionStopped;

  /// The triage action that accepts a Request and raises the Work order for it.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get requestsAccept;

  /// The triage action that declines a Request.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get requestsDecline;

  /// The triage action that files a Request as a duplicate of another.
  ///
  /// In en, this message translates to:
  /// **'Mark duplicate'**
  String get requestsMarkDuplicate;

  /// Who raised a Request, on the narrow card.
  ///
  /// In en, this message translates to:
  /// **'Raised by {name}'**
  String requestsRaisedByPerson(String name);

  /// The triage queue's empty state when no Request is waiting for a decision.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting'**
  String get requestsNoneExistTitle;

  /// What the triage queue's empty state says, under its title.
  ///
  /// In en, this message translates to:
  /// **'No Requests are waiting for a decision at this Site.'**
  String get requestsNoneExistMessage;

  /// One-line description under the Downtime title.
  ///
  /// In en, this message translates to:
  /// **'The machines not running at this Site, the reasons they stopped, and how long they have been down.'**
  String get downtimeDescription;

  /// The failure state's heading when the downtime register could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The downtime events could not be read'**
  String get downtimeUnavailableTitle;

  /// The button that opens the form for reporting a machine that has stopped.
  ///
  /// In en, this message translates to:
  /// **'Report a breakdown'**
  String get downtimeReport;

  /// Said above the register when the read was capped.
  ///
  /// In en, this message translates to:
  /// **'There are more downtime events than this list shows.'**
  String get downtimeTruncated;

  /// Label of the search box above the downtime register.
  ///
  /// In en, this message translates to:
  /// **'Filter downtime'**
  String get downtimeFilter;

  /// What the downtime register's search box matches on, under its label.
  ///
  /// In en, this message translates to:
  /// **'By Asset, reason or description.'**
  String get downtimeFilterHelp;

  /// The empty state the downtime search box shows when its term matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No downtime matches'**
  String get downtimeNoMatch;

  /// What the downtime register's no-match state says, quoting the term that matched nothing.
  ///
  /// In en, this message translates to:
  /// **'This Site has downtime recorded, but none matches “{term}”. Try a different Asset, reason or description.'**
  String downtimeNoMatchMessage(String term);

  /// Column header over the instant a machine stopped.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get downtimeStarted;

  /// Column header over the reason a machine stopped.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get downtimeReason;

  /// Column header over the person who reported a machine stopped.
  ///
  /// In en, this message translates to:
  /// **'Reported by'**
  String get downtimeReportedByColumn;

  /// The action that closes a machine's stop, once it is running again.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get downtimeClose;

  /// The action that records the reason a stop happened, after it has been closed.
  ///
  /// In en, this message translates to:
  /// **'Classify'**
  String get downtimeClassify;

  /// When a machine stopped, on the narrow card.
  ///
  /// In en, this message translates to:
  /// **'Started {instant}'**
  String downtimeStartedAt(String instant);

  /// The reason a machine stopped, on the narrow card.
  ///
  /// In en, this message translates to:
  /// **'Reason: {name}'**
  String downtimeReasonLine(String name);

  /// Who reported a machine stopped, on the narrow card.
  ///
  /// In en, this message translates to:
  /// **'Reported by {name}'**
  String downtimeReportedByPerson(String name);

  /// The downtime register's empty state when no machine is stopped.
  ///
  /// In en, this message translates to:
  /// **'Nothing is down'**
  String get downtimeNoneExistTitle;

  /// What the downtime register's empty state says, under its title.
  ///
  /// In en, this message translates to:
  /// **'No machine is recorded as down at this Site.'**
  String get downtimeNoneExistMessage;

  /// Column header over the toggle that discloses one row's longer text.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get commonDetails;

  /// The label of a longer free-text field on a record, and the toggle that reveals it.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get commonDescription;

  /// Stands in for an instant that could not be read from the wire, so a time is never blank.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get commonNow;

  /// One-line description under the Meters title.
  ///
  /// In en, this message translates to:
  /// **'The running counts a PM schedule can come due on, and the readings taken against them.'**
  String get metersDescription;

  /// The failure state's heading when the meter register could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The meters could not be read'**
  String get metersUnavailableTitle;

  /// The button that opens the form for defining a meter on an Asset.
  ///
  /// In en, this message translates to:
  /// **'Define a meter'**
  String get metersDefine;

  /// Label of the search box above the meter register.
  ///
  /// In en, this message translates to:
  /// **'Filter meters'**
  String get metersFilter;

  /// What the meter register's search box matches on, under its label.
  ///
  /// In en, this message translates to:
  /// **'By meter name, code or Asset.'**
  String get metersFilterHelp;

  /// The empty state the meter search box shows when its term matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No meters match'**
  String get metersNoMatch;

  /// What the meter register's no-match state says, quoting the term that matched nothing.
  ///
  /// In en, this message translates to:
  /// **'This Site has meters, but none matches “{term}”. Try a different name, code or Asset.'**
  String metersNoMatchMessage(String term);

  /// Stands in the latest-reading column for a meter nobody has read yet.
  ///
  /// In en, this message translates to:
  /// **'No reading yet'**
  String get metersNoReading;

  /// Column header over a meter's kind (running total, or reset each cycle).
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get metersType;

  /// Column header over the unit a meter counts in.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get metersUnit;

  /// Column header over the last reading recorded against a meter.
  ///
  /// In en, this message translates to:
  /// **'Latest reading'**
  String get metersLatestReading;

  /// Column header over the total a meter has counted, carried-forward included.
  ///
  /// In en, this message translates to:
  /// **'Accumulated use'**
  String get metersAccumulated;

  /// The amount a replaced meter counted before it was swapped, under a meter's total.
  ///
  /// In en, this message translates to:
  /// **'Carried forward: {value} {unit}'**
  String metersCarriedForward(String value, String unit);

  /// A meter's last reading, on the narrow card.
  ///
  /// In en, this message translates to:
  /// **'Latest: {label}'**
  String metersLatestLine(String label);

  /// A meter's total, on the narrow card.
  ///
  /// In en, this message translates to:
  /// **'Accumulated use: {label}'**
  String metersAccumulatedLine(String label);

  /// The meter register's empty state when the Site has none defined.
  ///
  /// In en, this message translates to:
  /// **'No meters yet'**
  String get metersNoneExistTitle;

  /// What the meter register's empty state says, under its title.
  ///
  /// In en, this message translates to:
  /// **'No meter is defined on this Site\'s Assets yet.'**
  String get metersNoneExistMessage;

  /// Column header over the short code a record is known by.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get commonCode;

  /// Column header over a record's own name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get commonName;

  /// The failure state's heading when the register of Job plans could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Job plans could not be read'**
  String get jobPlansUnavailableTitle;

  /// One-line description under the Job plans title.
  ///
  /// In en, this message translates to:
  /// **'How each recurring job is done — the steps it takes and what each one requires. A Work order follows a plan; it does not change one.'**
  String get jobPlansDescription;

  /// The button that opens the form for adding a reusable Job plan.
  ///
  /// In en, this message translates to:
  /// **'Add a Job plan'**
  String get jobPlansAdd;

  /// Label of the search box above the Job plan register.
  ///
  /// In en, this message translates to:
  /// **'Filter Job plans'**
  String get jobPlansFilter;

  /// What the Job plan register's search box matches on, under its label.
  ///
  /// In en, this message translates to:
  /// **'By name, code or description.'**
  String get jobPlansFilterHelp;

  /// The empty state the Job plan search box shows when its term matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No Job plans match'**
  String get jobPlansNoMatch;

  /// What the Job plan register's no-match state says, quoting the term that matched nothing.
  ///
  /// In en, this message translates to:
  /// **'The plant has Job plans, but none matches “{term}”. Try a different name, code or description.'**
  String jobPlansNoMatchMessage(String term);

  /// Column header over a Job plan's own name, code and kind.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get jobPlansPlanColumn;

  /// Column header over the toggle that discloses a Job plan's steps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get jobPlansSteps;

  /// Column header over the hours a Job plan is estimated to take.
  ///
  /// In en, this message translates to:
  /// **'Estimated hours'**
  String get jobPlansEstimatedHours;

  /// Column header over whether a Job plan needs the machine stopped to be done.
  ///
  /// In en, this message translates to:
  /// **'Shutdown'**
  String get jobPlansShutdown;

  /// How many steps a Job plan has, on its disclosure toggle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 step} other{{count} steps}}'**
  String jobPlansStepCount(int count);

  /// The chip on a Job plan that has been deactivated, so no Work order follows it.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get jobPlansInactive;

  /// Said of a Job plan that cannot be done with the machine running.
  ///
  /// In en, this message translates to:
  /// **'Requires a shutdown'**
  String get jobPlansRequiresShutdown;

  /// A Job plan's estimated hours, on the narrow card.
  ///
  /// In en, this message translates to:
  /// **'About {hours} h'**
  String jobPlansAboutHours(String hours);

  /// Shown when a Job plan has no steps at all.
  ///
  /// In en, this message translates to:
  /// **'No steps recorded.'**
  String get jobPlansNoSteps;

  /// The action that stops a Job plan being followed by new Work orders.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get jobPlansDeactivate;

  /// The action that lets a deactivated Job plan be followed again.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get jobPlansReactivate;

  /// The Job plan register's empty state when nothing reusable has been defined.
  ///
  /// In en, this message translates to:
  /// **'No Job plans yet'**
  String get jobPlansNoneExistTitle;

  /// What the Job plan register's empty state says, under its title.
  ///
  /// In en, this message translates to:
  /// **'No reusable job plan has been defined. Add one and its steps will show here.'**
  String get jobPlansNoneExistMessage;

  /// The failure state's heading when the register of PM schedules could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The PM schedules could not be read'**
  String get pmSchedulesUnavailableTitle;

  /// One-line description under the PM schedules title.
  ///
  /// In en, this message translates to:
  /// **'The Job plans attached to this Site\'s Assets that raise a Work order before something breaks.'**
  String get pmSchedulesDescription;

  /// The button that opens the form for attaching a Job plan to an Asset on an interval.
  ///
  /// In en, this message translates to:
  /// **'Add a PM schedule'**
  String get pmSchedulesAdd;

  /// Label of the search box above the PM schedule register.
  ///
  /// In en, this message translates to:
  /// **'Filter PM schedules'**
  String get pmSchedulesFilter;

  /// What the PM schedule register's search box matches on, under its label.
  ///
  /// In en, this message translates to:
  /// **'By schedule name, Asset or Job plan.'**
  String get pmSchedulesFilterHelp;

  /// The empty state the PM schedule search box shows when its term matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No PM schedules match'**
  String get pmSchedulesNoMatch;

  /// What the PM schedule register's no-match state says, quoting the term that matched nothing.
  ///
  /// In en, this message translates to:
  /// **'This Site has PM schedules, but none matches “{term}”. Try a different name, Asset or Job plan.'**
  String pmSchedulesNoMatchMessage(String term);

  /// Column header over the Job plan a PM schedule follows.
  ///
  /// In en, this message translates to:
  /// **'Job plan'**
  String get pmSchedulesJobPlanColumn;

  /// Column header over how often a PM schedule comes due.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get pmSchedulesInterval;

  /// Column header over when a PM schedule is next due.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get pmSchedulesDue;

  /// Column header over the toggle that discloses a PM schedule's rules in words.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get pmSchedulesRules;

  /// How many rules a PM schedule has, on its disclosure toggle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 rule} other{{count} rules}}'**
  String pmSchedulesRuleCount(int count);

  /// The point a PM schedule's interval counts from.
  ///
  /// In en, this message translates to:
  /// **'Rolls from {anchor}'**
  String pmSchedulesRollsFrom(String anchor);

  /// How many days before the due point a PM schedule raises its Work order.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Raised 1 day early} other{Raised {days} days early}}'**
  String pmSchedulesLeadTime(int days);

  /// How far a meter-driven PM schedule has counted towards its next due point.
  ///
  /// In en, this message translates to:
  /// **'Accumulated {current} of {target}'**
  String pmSchedulesAccumulated(String current, String target);

  /// A PM schedule's interval, counted on a meter.
  ///
  /// In en, this message translates to:
  /// **'Every {interval} of {meter}'**
  String pmSchedulesEveryMeter(String interval, String meter);

  /// A PM schedule's interval, counted in days.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Every day} other{Every {days} days}}'**
  String pmSchedulesEveryDays(int days);

  /// Stands in for a meter's name when neither its name nor its code came through.
  ///
  /// In en, this message translates to:
  /// **'the meter'**
  String get pmSchedulesTheMeter;

  /// The priority a PM schedule's Work orders are raised at, on the narrow card.
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String pmSchedulesPriorityLine(String priority);

  /// A meter-driven PM schedule whose accumulated use has reached its target.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get pmSchedulesDueNow;

  /// A meter-driven PM schedule that has not been given its next target yet.
  ///
  /// In en, this message translates to:
  /// **'No meter target yet'**
  String get pmSchedulesNoMeterTarget;

  /// A meter-driven PM schedule's next due point, as a meter value.
  ///
  /// In en, this message translates to:
  /// **'Due at {value}'**
  String pmSchedulesDueAt(String value);

  /// A date-driven PM schedule that has not been given a first due date yet.
  ///
  /// In en, this message translates to:
  /// **'No due date yet'**
  String get pmSchedulesNoDueDate;

  /// A date-driven PM schedule's next due date, with no day count to report.
  ///
  /// In en, this message translates to:
  /// **'Next due {date}'**
  String pmSchedulesNextDue(String date);

  /// A date-driven PM schedule whose due date has passed.
  ///
  /// In en, this message translates to:
  /// **'Overdue since {date}'**
  String pmSchedulesOverdueSince(String date);

  /// A date-driven PM schedule whose due date is today.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get pmSchedulesDueToday;

  /// A date-driven PM schedule's next due date, with how many days away it is.
  ///
  /// In en, this message translates to:
  /// **'Due {date} (in {days} days)'**
  String pmSchedulesDueIn(String date, int days);

  /// The PM schedule register's empty state when nothing is attached to the Site's Assets.
  ///
  /// In en, this message translates to:
  /// **'Nothing is scheduled'**
  String get pmSchedulesNoneExistTitle;

  /// What the PM schedule register's empty state says, under its title.
  ///
  /// In en, this message translates to:
  /// **'No PM schedule is attached to this Site\'s Assets yet.'**
  String get pmSchedulesNoneExistMessage;

  /// The browser tab's name for the sign-in Screen.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get titleSignIn;

  /// The browser tab's name for the Screen shown to an Account that has not been admitted.
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get titleAwaitingApproval;

  /// The browser tab's name for the Screen that forces a new password at first sign-in.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get titleChooseNewPassword;

  /// The browser tab's name for the Floor Screens a shared device opens on.
  ///
  /// In en, this message translates to:
  /// **'Floor'**
  String get titleFloor;

  /// The browser tab's name for the printable CAPA report.
  ///
  /// In en, this message translates to:
  /// **'CAPA report'**
  String get titleCapaReport;

  /// The browser tab's name for the printable training record form.
  ///
  /// In en, this message translates to:
  /// **'Training record form'**
  String get titleTrainingRecordForm;

  /// The browser tab's name for Home, whose own heading is a greeting.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get titleWelcome;

  /// The browser tab's name for one Employee's detail.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get titleEmployee;

  /// The browser tab's name for one Employee's worked-hours Screen.
  ///
  /// In en, this message translates to:
  /// **'Worked hours'**
  String get titleWorkedHours;

  /// The browser tab's name for the attendance board's to-confirm list.
  ///
  /// In en, this message translates to:
  /// **'Attendance to confirm'**
  String get titleAttendanceToConfirm;

  /// The browser tab's name for one shift's attendance sheet.
  ///
  /// In en, this message translates to:
  /// **'Attendance sheet'**
  String get titleAttendanceSheet;

  /// The browser tab's name for the register of training records.
  ///
  /// In en, this message translates to:
  /// **'Training records'**
  String get titleTrainingRecords;

  /// The browser tab's name for one training record.
  ///
  /// In en, this message translates to:
  /// **'Training record'**
  String get titleTrainingRecord;

  /// The browser tab's name for the Quality slide show.
  ///
  /// In en, this message translates to:
  /// **'Quality slide show'**
  String get titleQualitySlideShow;

  /// The browser tab's name for one customer complaint.
  ///
  /// In en, this message translates to:
  /// **'Customer complaint'**
  String get titleCustomerComplaint;

  /// The browser tab's name for one supplier NCR.
  ///
  /// In en, this message translates to:
  /// **'Supplier NCR'**
  String get titleSupplierNcr;

  /// The browser tab's name for one non-conformance.
  ///
  /// In en, this message translates to:
  /// **'Non-conformance'**
  String get titleNonConformance;

  /// The browser tab's name for one shift handover.
  ///
  /// In en, this message translates to:
  /// **'Shift handover'**
  String get titleShiftHandover;

  /// The browser tab's name for the register of safety incidents.
  ///
  /// In en, this message translates to:
  /// **'Safety incidents'**
  String get titleSafetyIncidents;

  /// The browser tab's name for one safety incident.
  ///
  /// In en, this message translates to:
  /// **'Safety incident'**
  String get titleSafetyIncident;

  /// The browser tab's name for the register of safety observations.
  ///
  /// In en, this message translates to:
  /// **'Safety observations'**
  String get titleSafetyObservations;

  /// The browser tab's name for one safety observation.
  ///
  /// In en, this message translates to:
  /// **'Safety observation'**
  String get titleSafetyObservation;

  /// The browser tab's name for one KPI's targets.
  ///
  /// In en, this message translates to:
  /// **'KPI targets'**
  String get titleKpiTargets;

  /// The browser tab's name for the Action log.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get titleActions;

  /// The browser tab's name for one Action.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get titleAction;

  /// The browser tab's name for the Screen an administrator admits Accounts from.
  ///
  /// In en, this message translates to:
  /// **'Approval queue'**
  String get titleApprovalQueue;

  /// The browser tab's name for one Store's stock, which the Store's own name would otherwise stand in for.
  ///
  /// In en, this message translates to:
  /// **'Store stock'**
  String get titleStoreStock;

  /// The button beside a failed read that asks again for the same list.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Shown in place of an Asset picker when the register could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Assets could not be read.'**
  String get commonAssetsFailed;

  /// Label over a Job plan picker.
  ///
  /// In en, this message translates to:
  /// **'Job plan'**
  String get commonJobPlan;

  /// Label over a meter picker, and the heading of the meter type field.
  ///
  /// In en, this message translates to:
  /// **'Meter'**
  String get commonMeter;

  /// Label over an Employee picker.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get commonEmployee;

  /// Label over the field that chooses the unit a figure is counted in.
  ///
  /// In en, this message translates to:
  /// **'Unit of measure'**
  String get commonUnitOfMeasure;

  /// Label over a field holding how many of something.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get commonQuantity;

  /// Label over a Part picker.
  ///
  /// In en, this message translates to:
  /// **'Part'**
  String get commonPart;

  /// Label over a Store picker.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get commonStore;

  /// Label over a free-text note field that may be left blank.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get commonNoteOptional;

  /// The word beside priority level 1, the CHECK constraint's most urgent end.
  ///
  /// In en, this message translates to:
  /// **'Most urgent'**
  String get commonPriorityMostUrgent;

  /// The word beside priority level 2.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get commonPriorityUrgent;

  /// The word beside priority level 3, the schema's own default.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get commonPriorityNormal;

  /// The word beside priority level 4.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get commonPriorityLow;

  /// The word beside priority level 5, the CHECK constraint's least urgent end.
  ///
  /// In en, this message translates to:
  /// **'Least urgent'**
  String get commonPriorityLeastUrgent;

  /// Title of the dialog that attaches a Job plan to an Asset as a PM schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule preventive maintenance'**
  String get pmScheduleFormTitle;

  /// The submit action of the PM schedule dialog.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get pmScheduleFormSubmit;

  /// Label over the choice of what the schedule's interval counts: elapsed time or accumulated use.
  ///
  /// In en, this message translates to:
  /// **'Comes round on'**
  String get pmScheduleFormBasisField;

  /// The interval counts elapsed time, so the schedule comes round on a number of days.
  ///
  /// In en, this message translates to:
  /// **'Elapsed time'**
  String get pmScheduleFormBasisElapsed;

  /// The interval counts accumulated use, so the schedule comes round on a cumulative meter's count.
  ///
  /// In en, this message translates to:
  /// **'Accumulated use'**
  String get pmScheduleFormBasisAccumulated;

  /// Label over the interval in days.
  ///
  /// In en, this message translates to:
  /// **'Every how many days'**
  String get pmScheduleFormEveryDays;

  /// Label over the interval in accumulated use.
  ///
  /// In en, this message translates to:
  /// **'Every how much accumulated use'**
  String get pmScheduleFormEveryAccumulated;

  /// Help text under the accumulated-use interval while no meter has been chosen yet.
  ///
  /// In en, this message translates to:
  /// **'Choose a cumulative meter first.'**
  String get pmScheduleFormMeterNotChosen;

  /// Help text under the accumulated-use interval once a meter is chosen, naming the meter's unit.
  ///
  /// In en, this message translates to:
  /// **'In {uom}, one interval past where the meter stands now.'**
  String pmScheduleFormMeterIntervalHelp(String uom);

  /// Label over the choice of which date the next due date counts from.
  ///
  /// In en, this message translates to:
  /// **'The interval rolls from'**
  String get pmScheduleFormAnchor;

  /// Label over the lead time, so many days before the due date a Work order is raised.
  ///
  /// In en, this message translates to:
  /// **'Raise this many days early'**
  String get pmScheduleFormLeadTime;

  /// Priority level 1 in the PM schedule dialog, worded for a bare digit whose direction is not obvious.
  ///
  /// In en, this message translates to:
  /// **'1 — most urgent'**
  String get pmScheduleFormPriorityMostUrgent;

  /// Priority level 5 in the PM schedule dialog.
  ///
  /// In en, this message translates to:
  /// **'5 — least urgent'**
  String get pmScheduleFormPriorityLeastUrgent;

  /// Label over the first due date of a day-driven PM schedule.
  ///
  /// In en, this message translates to:
  /// **'First due date (optional)'**
  String get pmScheduleFormFirstDue;

  /// Help text under the first due date.
  ///
  /// In en, this message translates to:
  /// **'Left blank, the first due date is the interval from today.'**
  String get pmScheduleFormFirstDueHelp;

  /// Shown in place of the Job plan picker when the catalogue could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Job plans could not be read.'**
  String get pmScheduleFormJobPlansFailed;

  /// Shown in place of the meter picker when the Asset's meters could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The meters could not be read.'**
  String get pmScheduleFormMetersFailed;

  /// Help text under the meter picker, explaining why gauges are not offered.
  ///
  /// In en, this message translates to:
  /// **'Only cumulative meters can drive a schedule.'**
  String get pmScheduleFormMeterHelp;

  /// The submit action of the Job plan form dialog.
  ///
  /// In en, this message translates to:
  /// **'Add plan'**
  String get jobPlanFormSubmit;

  /// Label over the Job plan's work type choice.
  ///
  /// In en, this message translates to:
  /// **'Kind of work'**
  String get jobPlanFormWorkType;

  /// Label over the Job plan's optional description.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get jobPlanFormDescriptionOptional;

  /// Label over the Job plan's optional estimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated hours (optional)'**
  String get jobPlanFormEstimatedHoursOptional;

  /// The switch on the Job plan form saying the work needs the Asset stopped.
  ///
  /// In en, this message translates to:
  /// **'Requires a shutdown'**
  String get jobPlanFormRequiresShutdown;

  /// Label over the Job plan's optional safety note.
  ///
  /// In en, this message translates to:
  /// **'Safety note (optional)'**
  String get jobPlanFormSafetyNoteOptional;

  /// The button that appends one step to the Job plan being written.
  ///
  /// In en, this message translates to:
  /// **'Add a step'**
  String get jobPlanFormAddStep;

  /// Shown over the steps when the Skill catalogue could not be fetched, so a step's required skill cannot be chosen.
  ///
  /// In en, this message translates to:
  /// **'The skill catalogue could not be read.'**
  String get jobPlanFormSkillsFailed;

  /// Label over one step's number.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get jobPlanFormStep;

  /// Label over one step's instruction text.
  ///
  /// In en, this message translates to:
  /// **'Instruction'**
  String get jobPlanFormInstruction;

  /// Tooltip on the button that drops one step from the Job plan being written.
  ///
  /// In en, this message translates to:
  /// **'Remove this step'**
  String get jobPlanFormRemoveStep;

  /// Label over one step's optional required Skill.
  ///
  /// In en, this message translates to:
  /// **'Required skill (optional)'**
  String get jobPlanFormRequiredSkill;

  /// Label over one step's optional estimated hours.
  ///
  /// In en, this message translates to:
  /// **'Hours (optional)'**
  String get jobPlanFormHoursOptional;

  /// The submit action of the meter form dialog.
  ///
  /// In en, this message translates to:
  /// **'Define'**
  String get meterFormSubmit;

  /// Help text under the meter's code.
  ///
  /// In en, this message translates to:
  /// **'How this meter is known on the Asset, e.g. RUN-HRS.'**
  String get meterFormCodeHelp;

  /// Label over the choice between a cumulative meter and a gauge.
  ///
  /// In en, this message translates to:
  /// **'Kind of meter'**
  String get meterFormType;

  /// Shown in place of the unit picker when the catalogue could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The units of measure could not be read.'**
  String get meterFormUomFailed;

  /// Title of the dialog that records a reading against one meter, naming it.
  ///
  /// In en, this message translates to:
  /// **'Record a reading on {meter}'**
  String readingFormTitle(String meter);

  /// The submit action of the reading dialog when the counter was reset or replaced.
  ///
  /// In en, this message translates to:
  /// **'Record rollover'**
  String get readingFormSubmitRollover;

  /// The submit action of the reading dialog for an ordinary reading.
  ///
  /// In en, this message translates to:
  /// **'Record reading'**
  String get readingFormSubmit;

  /// The line above the reading field showing where the meter stands now.
  ///
  /// In en, this message translates to:
  /// **'Accumulated use so far: {value}'**
  String readingFormAccumulatedSoFar(String value);

  /// Label over the reading field when the counter was reset or replaced.
  ///
  /// In en, this message translates to:
  /// **'What the new counter reads now'**
  String get readingFormNewCounterReads;

  /// Label over the reading field for an ordinary reading.
  ///
  /// In en, this message translates to:
  /// **'What the counter reads'**
  String get readingFormCounterReads;

  /// Help text under the reading field when the counter was reset or replaced.
  ///
  /// In en, this message translates to:
  /// **'The accumulated use is carried forward into the offset; the new counter usually reads 0.'**
  String get readingFormRolloverHelp;

  /// Help text under the reading field for an ordinary reading, naming the meter's unit.
  ///
  /// In en, this message translates to:
  /// **'In {uom}, exactly as the counter shows.'**
  String readingFormReadingHelp(String uom);

  /// The checkbox on a cumulative meter that says this reading follows a reset or a replacement.
  ///
  /// In en, this message translates to:
  /// **'The counter was reset or replaced'**
  String get readingFormRolloverTitle;

  /// What the reset-or-replaced checkbox does, under its own label.
  ///
  /// In en, this message translates to:
  /// **'Carries the accumulated use into the offset and records this as the new counter\'s start.'**
  String get readingFormRolloverSubtitle;

  /// Title of the dialog that accepts one Request, naming it.
  ///
  /// In en, this message translates to:
  /// **'Accept {requestNo}?'**
  String requestAcceptTitle(String requestNo);

  /// The dismiss action of the accept dialog: the Request stays in the triage queue.
  ///
  /// In en, this message translates to:
  /// **'Keep it waiting'**
  String get requestAcceptDismiss;

  /// The submit action of the accept dialog.
  ///
  /// In en, this message translates to:
  /// **'Accept this Request'**
  String get requestAcceptSubmit;

  /// What accepting a Request does, above the priority choice.
  ///
  /// In en, this message translates to:
  /// **'Accepting raises a Work order for this Request. Its priority is your call, not the reporter\'s urgency.'**
  String get requestAcceptBody;

  /// Title of the dialog that declines one Request, naming it.
  ///
  /// In en, this message translates to:
  /// **'Decline {requestNo}?'**
  String requestDeclineTitle(String requestNo);

  /// Label over the reason the database requires before a Request may be declined.
  ///
  /// In en, this message translates to:
  /// **'Why is this being declined?'**
  String get requestDeclineReason;

  /// The submit action of the decline dialog.
  ///
  /// In en, this message translates to:
  /// **'Decline this Request'**
  String get requestDeclineSubmit;

  /// Title of the dialog that marks one Request as a duplicate of another.
  ///
  /// In en, this message translates to:
  /// **'Mark as a duplicate'**
  String get requestDuplicateTitle;

  /// The dismiss action of the duplicate dialog: the Request stays its own.
  ///
  /// In en, this message translates to:
  /// **'Keep it separate'**
  String get requestDuplicateDismiss;

  /// Stands where the candidate list would be when no other open Request exists.
  ///
  /// In en, this message translates to:
  /// **'There is no other open Request for this one to duplicate.'**
  String get requestDuplicateNone;

  /// The question above the candidate list, naming the Request that would leave the queue.
  ///
  /// In en, this message translates to:
  /// **'Which Request survives? {requestNo} leaves the queue.'**
  String requestDuplicateWhich(String requestNo);

  /// Title of the dialog that books labour against a Work order.
  ///
  /// In en, this message translates to:
  /// **'Book labour'**
  String get labourBookingTitle;

  /// Label over the kind of labour being booked.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get labourBookingActivity;

  /// Label over when the booked labour started.
  ///
  /// In en, this message translates to:
  /// **'Started at'**
  String get labourBookingStartedAt;

  /// Label over when the booked labour ended.
  ///
  /// In en, this message translates to:
  /// **'Ended at'**
  String get labourBookingEndedAt;

  /// The checkbox saying the booked labour was worked outside normal hours.
  ///
  /// In en, this message translates to:
  /// **'Overtime'**
  String get labourBookingOvertime;

  /// Shown in place of the Employee picker when the directory could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Employees could not be read.'**
  String get labourBookingEmployeesFailed;

  /// Title of the dialog that books a part against a Work order.
  ///
  /// In en, this message translates to:
  /// **'Book a part'**
  String get partBookingTitle;

  /// The submit action of the part booking dialog.
  ///
  /// In en, this message translates to:
  /// **'Book part'**
  String get partBookingSubmit;

  /// Label over where the part comes from: a Store or bought in.
  ///
  /// In en, this message translates to:
  /// **'Sourced'**
  String get partBookingSourced;

  /// Shown in place of the part and store pickers when their options could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The options could not be read.'**
  String get partBookingOptionsFailed;

  /// Label over the part number of a part bought in.
  ///
  /// In en, this message translates to:
  /// **'Part number (optional)'**
  String get partBookingPartNoOptional;

  /// Label over the cost of one unit of a part bought in.
  ///
  /// In en, this message translates to:
  /// **'Unit cost (optional)'**
  String get partBookingUnitCostOptional;

  /// The failure state's heading when the Non-conformance register could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Non-conformance register could not be read'**
  String get nonconformancesUnavailableTitle;

  /// The empty state's heading when the Account can see no Site at all.
  ///
  /// In en, this message translates to:
  /// **'No Site to show'**
  String get nonconformancesNoSiteTitle;

  /// What the no-Site empty state says under its heading.
  ///
  /// In en, this message translates to:
  /// **'Your Account can see no Site yet, so there is nothing to read here.'**
  String get nonconformancesNoSiteMessage;

  /// One-line description under the Non-conformance register's title.
  ///
  /// In en, this message translates to:
  /// **'What was found not to conform at this Site, where it was found, and how much of it there is.'**
  String get nonconformancesDescription;

  /// The button that opens the form recording a Non-conformance, and the title of that form.
  ///
  /// In en, this message translates to:
  /// **'Record a Non-conformance'**
  String get nonconformanceRecord;

  /// The Org Unit filter's own label when it narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'All Org Units'**
  String get commonAllOrgUnits;

  /// The status filter's option that narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'Any status'**
  String get nonconformancesAnyStatus;

  /// Label over a Defect code picker, and the register's own Defect code filter.
  ///
  /// In en, this message translates to:
  /// **'Defect code'**
  String get commonDefectCode;

  /// The Defect code filter's option that narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'Every Defect code'**
  String get nonconformancesEveryDefectCode;

  /// Label over a Product picker, and the register's own Product filter.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get commonProduct;

  /// The Product filter's option that narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'Every Product'**
  String get nonconformancesEveryProduct;

  /// Label over the severity filter and the severity field of a Non-conformance.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get nonconformancesSeverity;

  /// The severity filter's option that narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'Any severity'**
  String get nonconformancesAnySeverity;

  /// Label over the first date of the detected-between filter.
  ///
  /// In en, this message translates to:
  /// **'Detected from'**
  String get nonconformancesDetectedFrom;

  /// Label over the last date of the detected-between filter.
  ///
  /// In en, this message translates to:
  /// **'Detected to'**
  String get nonconformancesDetectedTo;

  /// Said under the register when the list was capped rather than complete.
  ///
  /// In en, this message translates to:
  /// **'There are more Non-conformances than this list shows. Narrow it by Org Unit, by status or by date to see the rest.'**
  String get nonconformancesTruncated;

  /// The empty state's heading when the register has records but no filter matches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches these filters'**
  String get nonconformancesNoMatchTitle;

  /// What the filtered-empty state says under its heading.
  ///
  /// In en, this message translates to:
  /// **'The register has Non-conformances, but none of them is in the area, state, Defect code, Product, severity or dates you picked.'**
  String get nonconformancesNoMatchMessage;

  /// The action on the filtered-empty state that clears every filter at once.
  ///
  /// In en, this message translates to:
  /// **'Clear the filters'**
  String get nonconformancesClearTheFilters;

  /// The empty state's heading when the Site's register has no records at all.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been found not to conform'**
  String get nonconformancesNoneExistTitle;

  /// What the no-record state says under its heading.
  ///
  /// In en, this message translates to:
  /// **'No Non-conformance has been recorded at this Site.'**
  String get nonconformancesNoneExistMessage;

  /// The register's column heading over each Non-conformance's own number.
  ///
  /// In en, this message translates to:
  /// **'Non-conformance'**
  String get nonconformancesNumberColumn;

  /// The register's column heading over the Product, Defect code and detection point of one find.
  ///
  /// In en, this message translates to:
  /// **'What was found'**
  String get nonconformancesFoundColumn;

  /// The register's column heading over a record's state chip.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get commonState;

  /// The register's column heading over where a Non-conformance was filed.
  ///
  /// In en, this message translates to:
  /// **'Filed'**
  String get nonconformancesFiledColumn;

  /// The button on a register row that opens the record itself.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// How much product one Non-conformance affects, with its unit.
  ///
  /// In en, this message translates to:
  /// **'{count} {uom} affected'**
  String nonconformanceQuantityAffected(String count, String uom);

  /// How many times the affected quantity of one Non-conformance has been raised.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{raised 1 time} other{raised {count} times}}'**
  String nonconformanceQuantityRaised(int count);

  /// The Org Unit a Non-conformance was found at, and what it was filed against.
  ///
  /// In en, this message translates to:
  /// **'{orgUnit} · filed against {against}'**
  String nonconformanceFiledAgainst(String orgUnit, String against);

  /// The submit action of the form that records a Non-conformance.
  ///
  /// In en, this message translates to:
  /// **'Record it'**
  String get nonconformanceFormRecord;

  /// Help text under the Product field of the Non-conformance form.
  ///
  /// In en, this message translates to:
  /// **'What the nonconforming product is.'**
  String get nonconformanceFormProductHelp;

  /// Help text under the Defect code field of the Non-conformance form.
  ///
  /// In en, this message translates to:
  /// **'What is wrong with it. The severity starts at this code own default.'**
  String get nonconformanceFormDefectCodeHelp;

  /// The Defect code picker's option that has nothing chosen yet.
  ///
  /// In en, this message translates to:
  /// **'Choose a code'**
  String get nonconformanceFormChooseCode;

  /// Label over the detection point of a Non-conformance.
  ///
  /// In en, this message translates to:
  /// **'Detection point'**
  String get nonconformanceFormDetectionPoint;

  /// Help text under the detection point field.
  ///
  /// In en, this message translates to:
  /// **'Where the control plan caught it.'**
  String get nonconformanceFormDetectionPointHelp;

  /// The detection point picker's option that has nothing chosen yet.
  ///
  /// In en, this message translates to:
  /// **'Choose a point'**
  String get nonconformanceFormChoosePoint;

  /// Help text under the severity field before a Defect code is chosen.
  ///
  /// In en, this message translates to:
  /// **'Chosen with the Defect code.'**
  String get nonconformanceFormSeverityHelpUnset;

  /// Help text under the severity field once a Defect code carries a default.
  ///
  /// In en, this message translates to:
  /// **'Starts at {severity}. Raising it is allowed; lowering it is a later decision.'**
  String nonconformanceFormSeverityHelpSet(String severity);

  /// The severity picker's option before a Defect code is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose a Defect code first'**
  String get nonconformanceFormChooseCodeFirst;

  /// The severity picker's own option once a Defect code carries a default.
  ///
  /// In en, this message translates to:
  /// **'Starts at {severity}'**
  String nonconformanceFormStartsAt(String severity);

  /// Help text under the quantity field of the Non-conformance form.
  ///
  /// In en, this message translates to:
  /// **'How many pieces.'**
  String get nonconformanceFormQuantityHelp;

  /// Label over the optional lot reference of a Non-conformance.
  ///
  /// In en, this message translates to:
  /// **'Lot reference (optional)'**
  String get nonconformanceFormLotRef;

  /// Help text under the lot reference field.
  ///
  /// In en, this message translates to:
  /// **'What else is affected — a batch number is better than nothing.'**
  String get nonconformanceFormLotRefHelp;

  /// Label over the optional Asset a Non-conformance was found on.
  ///
  /// In en, this message translates to:
  /// **'Asset (optional)'**
  String get nonconformanceFormAssetOptional;

  /// Help text under the optional Asset picker.
  ///
  /// In en, this message translates to:
  /// **'Which machine, if the find was on one. It must sit at that Org Unit.'**
  String get nonconformanceFormAssetHelp;

  /// Label over the optional free-text detail of a Non-conformance.
  ///
  /// In en, this message translates to:
  /// **'Detail (optional)'**
  String get nonconformanceFormDetailOptional;

  /// Label over the optional immediate containment of a Non-conformance.
  ///
  /// In en, this message translates to:
  /// **'Immediate containment (optional)'**
  String get nonconformanceFormContainment;

  /// Help text under the immediate containment field.
  ///
  /// In en, this message translates to:
  /// **'What was done at once. Recording it makes this contained.'**
  String get nonconformanceFormContainmentHelp;

  /// Label over the optional moment a Non-conformance was detected.
  ///
  /// In en, this message translates to:
  /// **'Detected at (optional)'**
  String get nonconformanceFormDetectedAt;

  /// Help text under the detected-at field.
  ///
  /// In en, this message translates to:
  /// **'When it was found, if that is not now. This is what decides the production day and shift it is filed against.'**
  String get nonconformanceFormDetectedAtHelp;

  /// Heading of the Org Unit chooser inside the Non-conformance form.
  ///
  /// In en, this message translates to:
  /// **'Where it was found'**
  String get nonconformanceFormWhereFound;

  /// What the Org Unit chooser does, under its heading.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit the nonconforming product was found at. This is what decides who may act on it.'**
  String get nonconformanceFormWhereFoundHelp;

  /// Confirms the Org Unit a Non-conformance will be filed at, once one is chosen.
  ///
  /// In en, this message translates to:
  /// **'This Non-conformance will be recorded at {orgUnit}.'**
  String nonconformanceFormWillBeRecorded(String orgUnit);

  /// What the floor Non-conformance dialog asks, above its fields.
  ///
  /// In en, this message translates to:
  /// **'What was found not to conform? Everything with a known set is chosen from what this device can see.'**
  String get nonconformanceFloorIntro;

  /// The floor form's Product picker option that has nothing chosen yet.
  ///
  /// In en, this message translates to:
  /// **'Choose a Product'**
  String get nonconformanceFloorChooseProduct;

  /// Label over the detection point in the floor Non-conformance dialog.
  ///
  /// In en, this message translates to:
  /// **'Detected at'**
  String get nonconformanceFloorDetectedAt;

  /// Tells the floor form's caller which severity the chosen Defect code brings.
  ///
  /// In en, this message translates to:
  /// **'Starts at {severity} — this Defect code\'s own severity.'**
  String nonconformanceFloorStartsAt(String severity);

  /// Label over the quantity in the floor Non-conformance dialog.
  ///
  /// In en, this message translates to:
  /// **'How much of it'**
  String get nonconformanceFloorHowMuch;

  /// Label over the lot or batch reference in the floor Non-conformance dialog.
  ///
  /// In en, this message translates to:
  /// **'Lot or batch (if it has one)'**
  String get nonconformanceFloorLot;

  /// Label over the free-text description in the floor Non-conformance dialog.
  ///
  /// In en, this message translates to:
  /// **'What did you see?'**
  String get nonconformanceFloorWhatDidYouSee;

  /// What the floor Non-conformance dialog asks before the identity fields.
  ///
  /// In en, this message translates to:
  /// **'Who found it? Your Employee number and PIN identify you for this record only — it is filed as your find.'**
  String get nonconformanceFloorWhoFound;

  /// Label over the Employee number field of the floor Non-conformance dialog.
  ///
  /// In en, this message translates to:
  /// **'Employee number'**
  String get nonconformanceFloorEmployeeNumber;

  /// Label over the PIN field of the floor Non-conformance dialog.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get nonconformanceFloorPin;

  /// The page head of one Non-conformance's detail.
  ///
  /// In en, this message translates to:
  /// **'Non-conformance'**
  String get nonconformanceTitle;

  /// The empty state's heading when the address names no record.
  ///
  /// In en, this message translates to:
  /// **'No such Non-conformance'**
  String get nonconformanceDetailMissingTitle;

  /// What the missing-record state says under its heading.
  ///
  /// In en, this message translates to:
  /// **'Nothing is recorded at this address. It may have been removed, or the address may be wrong.'**
  String get nonconformanceDetailMissingMessage;

  /// The control that returns from one record to the register.
  ///
  /// In en, this message translates to:
  /// **'Back to Non-conformances'**
  String get nonconformanceDetailBack;

  /// The failure state's heading when one record could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Non-conformance could not be read'**
  String get nonconformanceDetailUnavailableTitle;

  /// The severity chip on one record, naming the severity itself.
  ///
  /// In en, this message translates to:
  /// **'{severity} severity'**
  String nonconformanceDetailSeverityChip(String severity);

  /// The chip saying when one record was closed.
  ///
  /// In en, this message translates to:
  /// **'Finished {date}'**
  String nonconformanceDetailFinishedAt(String date);

  /// The summary fact over the record's own free-text detail.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get nonconformanceDetailDetail;

  /// The summary fact over how much product the record affects.
  ///
  /// In en, this message translates to:
  /// **'Quantity affected'**
  String get nonconformanceDetailQuantityAffected;

  /// The summary fact over what the record was filed against.
  ///
  /// In en, this message translates to:
  /// **'Filed against'**
  String get nonconformanceDetailFiledAgainst;

  /// Stands where an optional free-text value was left blank.
  ///
  /// In en, this message translates to:
  /// **'None given'**
  String get commonNoneGiven;

  /// Stands where an optional record was never named.
  ///
  /// In en, this message translates to:
  /// **'None named'**
  String get commonNoneNamed;

  /// Stands where an optional field was never filled in.
  ///
  /// In en, this message translates to:
  /// **'Not given'**
  String get commonNotGiven;

  /// Stands where an optional moment was never recorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get commonNotRecorded;

  /// Stands where nothing has been written into an optional field yet.
  ///
  /// In en, this message translates to:
  /// **'None recorded yet'**
  String get commonNoneRecorded;

  /// The fact over the lot reference of one record.
  ///
  /// In en, this message translates to:
  /// **'Lot reference'**
  String get nonconformanceDetailLotRef;

  /// The fact over what was done at once about one record.
  ///
  /// In en, this message translates to:
  /// **'Immediate containment'**
  String get nonconformanceDetailContainment;

  /// The Defect code of one record, its code and the severity it starts at.
  ///
  /// In en, this message translates to:
  /// **'{name} · {code} · starts at {severity}'**
  String nonconformanceDetailDefectCodeValue(
    String name,
    String code,
    String severity,
  );

  /// The heading over every transition one record offers.
  ///
  /// In en, this message translates to:
  /// **'What can be done'**
  String get nonconformanceDetailActionsSection;

  /// The action that records more of the same nonconforming product.
  ///
  /// In en, this message translates to:
  /// **'Increase the quantity'**
  String get nonconformanceIncreaseQuantity;

  /// The action that raises a record's severity or records its containment.
  ///
  /// In en, this message translates to:
  /// **'Raise severity or contain it'**
  String get nonconformanceUpdate;

  /// The action that records what is done with a part of the affected quantity.
  ///
  /// In en, this message translates to:
  /// **'Record a Disposition'**
  String get nonconformanceDisposition;

  /// The Quality-authority decision to accept the nonconforming product as it is.
  ///
  /// In en, this message translates to:
  /// **'Grant a Concession'**
  String get nonconformanceConcession;

  /// The Quality-authority decision to lower a record's severity.
  ///
  /// In en, this message translates to:
  /// **'Lower the severity'**
  String get nonconformanceLowerSeverity;

  /// The Quality-authority decision to reopen a closed record.
  ///
  /// In en, this message translates to:
  /// **'Reopen it'**
  String get nonconformanceReopen;

  /// The Quality-authority decision that a record was raised in error.
  ///
  /// In en, this message translates to:
  /// **'Cancel it in error'**
  String get nonconformanceCancel;

  /// The heading over every change to a record's affected quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity history'**
  String get nonconformanceDetailQuantityHistory;

  /// What the quantity history section explains about itself.
  ///
  /// In en, this message translates to:
  /// **'Sorting finds more than the first count. Every change is kept, and the affected quantity never shrinks.'**
  String get nonconformanceDetailQuantityHistoryNote;

  /// Stands where the quantity history is empty.
  ///
  /// In en, this message translates to:
  /// **'The affected quantity has not been changed since it was recorded.'**
  String get nonconformanceDetailNoQuantityHistory;

  /// The heading over the Dispositions recorded against one record.
  ///
  /// In en, this message translates to:
  /// **'Dispositions'**
  String get nonconformanceDetailDispositions;

  /// What the Dispositions section explains about itself.
  ///
  /// In en, this message translates to:
  /// **'Product is dealt with in parts. A Non-conformance closes by itself once all of its quantity has a Disposition.'**
  String get nonconformanceDetailDispositionsNote;

  /// How much of the affected quantity already has a Disposition.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} {uom} dispositioned'**
  String nonconformanceDetailDispositioned(
    String done,
    String total,
    String uom,
  );

  /// Stands where no Disposition has been recorded.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been decided about this product yet.'**
  String get nonconformanceDetailNoDispositions;

  /// How much rework one Disposition took.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute of rework} other{{count} minutes of rework}}'**
  String nonconformanceDetailReworkMinutes(int count);

  /// The heading over the corrections a holder of Quality authority made to one record.
  ///
  /// In en, this message translates to:
  /// **'Corrections'**
  String get nonconformanceDetailCorrections;

  /// What the Corrections section explains about itself.
  ///
  /// In en, this message translates to:
  /// **'What a holder of Quality authority has changed about this record, and why.'**
  String get nonconformanceDetailCorrectionsNote;

  /// Stands where no correction has been made.
  ///
  /// In en, this message translates to:
  /// **'This record has not been corrected.'**
  String get nonconformanceDetailNoCorrections;

  /// The heading over the Concerns a record is evidence behind.
  ///
  /// In en, this message translates to:
  /// **'The cause'**
  String get nonconformanceDetailCause;

  /// What the cause section explains about itself.
  ///
  /// In en, this message translates to:
  /// **'Nonconforming product is dealt with here; the problem behind it is solved in the action log, as a Concern. One problem that shows up several times stays one Concern.'**
  String get nonconformanceDetailCauseNote;

  /// Stands where the record is evidence behind no Concern.
  ///
  /// In en, this message translates to:
  /// **'Nothing is being done about the cause yet.'**
  String get nonconformanceDetailNoConcerns;

  /// Says which Concern this occurrence of the problem started.
  ///
  /// In en, this message translates to:
  /// **'raised from this record'**
  String get nonconformanceDetailRaisedFrom;

  /// Says a Concern linked to this record is past its due date.
  ///
  /// In en, this message translates to:
  /// **'overdue'**
  String get nonconformanceDetailOverdue;

  /// The action that raises a Concern from one record.
  ///
  /// In en, this message translates to:
  /// **'Raise a Concern'**
  String get nonconformanceRaiseConcern;

  /// The action that links one record to a Concern that already exists.
  ///
  /// In en, this message translates to:
  /// **'Link it to a Concern'**
  String get nonconformanceLinkConcern;

  /// An empty state's heading when the Account can see no Site at all.
  ///
  /// In en, this message translates to:
  /// **'No Site to show'**
  String get commonNoSiteTitle;

  /// What the no-Site empty state says under its heading.
  ///
  /// In en, this message translates to:
  /// **'Your Account can see no Site yet, so there is nothing to read here.'**
  String get commonNoSiteMessage;

  /// The Org Unit a record was registered at, and what it was registered against.
  ///
  /// In en, this message translates to:
  /// **'{orgUnit} · filed against {against}'**
  String commonFiledAgainst(String orgUnit, String against);

  /// A register's column heading over what each record was filed against.
  ///
  /// In en, this message translates to:
  /// **'Filed against'**
  String get commonFiledAgainstColumn;

  /// A filter's option that narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get commonAny;

  /// Label over the type filter of a register, and the register's own Type column.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get commonType;

  /// Label over the category filter of the Safety observation register.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get commonCategory;

  /// Label over the filter that narrows by whether an Action was raised.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get commonAction;

  /// Label over the severity filter of a register, and its Severity column.
  ///
  /// In en, this message translates to:
  /// **'Severity'**
  String get commonSeverity;

  /// The failure state's heading when the Safety incident register could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Safety incident register could not be read'**
  String get safetyIncidentsUnavailableTitle;

  /// One-line description under the Safety incident register's title.
  ///
  /// In en, this message translates to:
  /// **'What went wrong at this Site, where it happened, and where it sits on the severity ladder.'**
  String get safetyIncidentsDescription;

  /// The button that opens the form recording a Safety incident.
  ///
  /// In en, this message translates to:
  /// **'Record a Safety incident'**
  String get safetyIncidentRecord;

  /// Label over the incident type filter.
  ///
  /// In en, this message translates to:
  /// **'Incident type'**
  String get safetyIncidentType;

  /// Label over the filter that narrows by whether an incident is recordable, and the option that keeps only recordable ones.
  ///
  /// In en, this message translates to:
  /// **'Recordable'**
  String get safetyRecordable;

  /// The recordable filter's option that keeps only incidents that need not be reported.
  ///
  /// In en, this message translates to:
  /// **'Not recordable'**
  String get safetyNotRecordable;

  /// Label over the first date of the occurred-between filter.
  ///
  /// In en, this message translates to:
  /// **'Occurred from'**
  String get safetyOccurredFrom;

  /// Label over the last date of the occurred-between filter.
  ///
  /// In en, this message translates to:
  /// **'Occurred to'**
  String get safetyOccurredTo;

  /// Said under the Safety incident register when the list was capped rather than complete.
  ///
  /// In en, this message translates to:
  /// **'There are more Safety incidents than this list shows. Narrow it by Org Unit, by status or by date to see the rest.'**
  String get safetyIncidentsTruncated;

  /// What the filtered-empty state of the Safety incident register says under its heading.
  ///
  /// In en, this message translates to:
  /// **'The register has Safety incidents, but none of them is in the area, state, type, severity, recordability or dates you picked.'**
  String get safetyIncidentsNoMatchMessage;

  /// The empty state's heading when the Site recorded no incident at all.
  ///
  /// In en, this message translates to:
  /// **'No incidents recorded for this period'**
  String get safetyIncidentsNoneTitle;

  /// What the no-incident state says under its heading.
  ///
  /// In en, this message translates to:
  /// **'No Safety incident has been recorded at this Site for the area and dates shown.'**
  String get safetyIncidentsNoneMessage;

  /// The Safety incident register's column heading over each incident's own number.
  ///
  /// In en, this message translates to:
  /// **'Incident #'**
  String get safetyIncidentNumberColumn;

  /// The failure state's heading when the Safety observation register could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'The Safety observation register could not be read'**
  String get safetyObservationsUnavailableTitle;

  /// One-line description under the Safety observation register's title.
  ///
  /// In en, this message translates to:
  /// **'What was seen before anything went wrong, ranked worst-first by the worst credible outcome.'**
  String get safetyObservationsDescription;

  /// The button that opens the form recording a Safety observation.
  ///
  /// In en, this message translates to:
  /// **'Record an observation'**
  String get safetyObservationRecord;

  /// The type filter's option that narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'Any type'**
  String get safetyAnyType;

  /// The category filter's option that narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'Any category'**
  String get safetyAnyCategory;

  /// Label over the filter that narrows observations by how bad the outcome could have been.
  ///
  /// In en, this message translates to:
  /// **'Severity potential'**
  String get safetySeverityPotential;

  /// The severity-potential filter's option that narrows nothing.
  ///
  /// In en, this message translates to:
  /// **'Any potential'**
  String get safetyAnyPotential;

  /// The label of the stop-work badge on an observation, and the filter that narrows by it.
  ///
  /// In en, this message translates to:
  /// **'Stop-work'**
  String get safetyStopWork;

  /// The stop-work filter's option that keeps only observations that stopped the work.
  ///
  /// In en, this message translates to:
  /// **'Stop-work only'**
  String get safetyStopWorkOnly;

  /// The stop-work filter's option that keeps only observations that did not stop the work.
  ///
  /// In en, this message translates to:
  /// **'Not stop-work'**
  String get safetyNotStopWork;

  /// The action filter's option that keeps only observations nothing has been raised for.
  ///
  /// In en, this message translates to:
  /// **'No Action raised'**
  String get safetyNoActionRaised;

  /// The action filter's option that keeps only observations an Action has been raised from.
  ///
  /// In en, this message translates to:
  /// **'Action raised'**
  String get safetyActionRaised;

  /// Label over the first date of the observed-between filter.
  ///
  /// In en, this message translates to:
  /// **'Observed from'**
  String get safetyObservedFrom;

  /// Label over the last date of the observed-between filter.
  ///
  /// In en, this message translates to:
  /// **'Observed to'**
  String get safetyObservedTo;

  /// Said under the Safety observation register when the list was capped rather than complete.
  ///
  /// In en, this message translates to:
  /// **'There are more Safety observations than this list shows. Narrow it by Org Unit, by type or by date to see the rest.'**
  String get safetyObservationsTruncated;

  /// What the filtered-empty state of the Safety observation register says under its heading.
  ///
  /// In en, this message translates to:
  /// **'The register has Safety observations, but none of them is in the area, type, category, potential, stop-work or dates you picked.'**
  String get safetyObservationsNoMatchMessage;

  /// The empty state's heading when the Site recorded no observation at all — a register with no rows is bad news here.
  ///
  /// In en, this message translates to:
  /// **'No observations recorded. The leading indicator is empty.'**
  String get safetyObservationsNoneTitle;

  /// What the no-observation state says under its heading.
  ///
  /// In en, this message translates to:
  /// **'No Safety observation has been recorded at this Site for the area and dates shown.'**
  String get safetyObservationsNoneMessage;

  /// The Safety observation register's column heading over the worst credible outcome.
  ///
  /// In en, this message translates to:
  /// **'Potential'**
  String get safetyPotentialColumn;

  /// Title of the dialog a person on the floor reports a Safety incident from.
  ///
  /// In en, this message translates to:
  /// **'Report a Safety incident'**
  String get safetyIncidentReport;

  /// The submit action of the floor Safety incident dialog.
  ///
  /// In en, this message translates to:
  /// **'Report it'**
  String get safetyReportSubmit;

  /// What the floor Safety incident dialog asks, above its fields.
  ///
  /// In en, this message translates to:
  /// **'What happened? Everything with a known set is chosen from a fixed list.'**
  String get safetyIncidentFloorIntro;

  /// Label over the free-text account of a Safety incident.
  ///
  /// In en, this message translates to:
  /// **'What happened'**
  String get safetyWhatHappened;

  /// Label over what was done at once about a Safety incident.
  ///
  /// In en, this message translates to:
  /// **'Immediate action (optional)'**
  String get safetyImmediateAction;

  /// Label over the moment a Safety incident happened.
  ///
  /// In en, this message translates to:
  /// **'Occurred at'**
  String get safetyOccurredAt;

  /// What the floor Safety incident dialog asks before its identity fields.
  ///
  /// In en, this message translates to:
  /// **'Who is reporting this? Your Employee number and PIN identify you for this record only — it is filed as your report.'**
  String get safetyIncidentFloorWho;

  /// Title of the dialog a person on the floor records a Safety observation from.
  ///
  /// In en, this message translates to:
  /// **'Record a Safety observation'**
  String get safetyObservationRecordTitle;

  /// What the floor Safety observation dialog asks, above its fields.
  ///
  /// In en, this message translates to:
  /// **'What was seen? Everything with a known set is chosen from a fixed list.'**
  String get safetyObservationFloorIntro;

  /// Label over the free-text account of a Safety observation.
  ///
  /// In en, this message translates to:
  /// **'What was seen'**
  String get safetyWhatWasSeen;

  /// Label over what was done at once about a Safety observation.
  ///
  /// In en, this message translates to:
  /// **'Action taken (optional)'**
  String get safetyActionTaken;

  /// The switch saying the observer stopped the work on the strength of the observation.
  ///
  /// In en, this message translates to:
  /// **'Stop-work authority was exercised'**
  String get safetyStopWorkExercised;

  /// What the floor Safety observation dialog asks before its identity fields.
  ///
  /// In en, this message translates to:
  /// **'Who is recording this? Your Employee number and PIN identify you for this record only.'**
  String get safetyObservationFloorWho;

  /// The one way out of a refused dialog.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Said when the leave request a decision dialog was opened for is not the caller's to decide.
  ///
  /// In en, this message translates to:
  /// **'This leave request is not one you can decide.'**
  String get routerLeaveNotDecidable;

  /// Said when the leave request a cancel dialog was opened for cannot be cancelled by this caller.
  ///
  /// In en, this message translates to:
  /// **'This leave request cannot be cancelled.'**
  String get routerLeaveNotCancellable;

  /// The heading of the refusal shown when a measure address names no known kind of measure.
  ///
  /// In en, this message translates to:
  /// **'That is not a measure'**
  String get routerNotAMeasure;

  /// What the refusal explains, under its heading.
  ///
  /// In en, this message translates to:
  /// **'A measure is a containment, a countermeasure or a preventive action.'**
  String get routerNotAMeasureBody;

  /// The way out of the measure refusal back to the Action it was opened from.
  ///
  /// In en, this message translates to:
  /// **'Back to the Action'**
  String get routerBackToAction;

  /// The heading of the refusal shown when a form opens for a caller with no write Grant at this Site.
  ///
  /// In en, this message translates to:
  /// **'You cannot do that here'**
  String get routerCannotDoThatHere;

  /// Why the form was refused, under its heading.
  ///
  /// In en, this message translates to:
  /// **'You do not hold a write Grant anywhere at this Site.'**
  String get routerNoWriteGrant;

  /// The way out of the write-Grant refusal back to the register it was opened from.
  ///
  /// In en, this message translates to:
  /// **'Back to the list'**
  String get routerBackToList;

  /// The tooltip of the button on a code field or a picker that opens the camera to read a code.
  ///
  /// In en, this message translates to:
  /// **'Scan with the camera'**
  String get cameraScanButton;

  /// The camera dialog's own title, and the screen reader's name for its preview.
  ///
  /// In en, this message translates to:
  /// **'Scan a code'**
  String get cameraScanTitle;

  /// What to do with the camera, under the camera dialog's title.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the code — it is read as soon as it is recognised.'**
  String get cameraScanPointAtCode;

  /// The camera dialog's one way out that changes nothing.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get cameraScanClose;

  /// The camera dialog's heading when the browser refuses the camera or the permission was denied.
  ///
  /// In en, this message translates to:
  /// **'The camera could not be opened'**
  String get cameraScanRefusedTitle;

  /// Why the camera did not open, and what the person can do about it in the browser's own chrome.
  ///
  /// In en, this message translates to:
  /// **'Allow this site to use the camera in the browser, then try again.'**
  String get cameraScanRefusedBody;

  /// The camera dialog's heading when the browser has no code decoder at all.
  ///
  /// In en, this message translates to:
  /// **'This browser cannot read a code with the camera'**
  String get cameraScanUnsupportedTitle;

  /// What a person does instead when their browser cannot decode a code from the camera.
  ///
  /// In en, this message translates to:
  /// **'Type the code instead, or use the shop-floor reader.'**
  String get cameraScanUnsupportedBody;

  /// No description provided for @accountCorrectionChangeRoleAndGrants.
  ///
  /// In en, this message translates to:
  /// **'Change role and Grants'**
  String get accountCorrectionChangeRoleAndGrants;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @accountCorrectionHoldsTheRoleAndTheOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'{email} holds the role and the Org Unit Grants chosen here. Whatever is set below replaces what it has now.'**
  String accountCorrectionHoldsTheRoleAndTheOrgUnit(Object email);

  /// No description provided for @accountCorrectionAnAdministratorCanActEverywhereThisAccount.
  ///
  /// In en, this message translates to:
  /// **'An administrator can act everywhere. This Account will be able to see and change every Site and every Org Unit, and to admit other Accounts. Every Org Unit Grant it holds now is removed, and none are needed.'**
  String get accountCorrectionAnAdministratorCanActEverywhereThisAccount;

  /// No description provided for @accountCorrectionThisAccountWasTurnedAwaySavingThis.
  ///
  /// In en, this message translates to:
  /// **'This Account was turned away. Saving this admits it to the Platform and lets it sign in.'**
  String get accountCorrectionThisAccountWasTurnedAwaySavingThis;

  /// No description provided for @accountCorrectionThisAccountIsDeactivatedSavingThisReactivates.
  ///
  /// In en, this message translates to:
  /// **'This Account is deactivated. Saving this reactivates it and lets it sign in again.'**
  String get accountCorrectionThisAccountIsDeactivatedSavingThisReactivates;

  /// No description provided for @commonChangeEmployeeLink.
  ///
  /// In en, this message translates to:
  /// **'Change Employee link'**
  String get commonChangeEmployeeLink;

  /// No description provided for @accountEmployeeWillBeLinkedToTheEmployeeChosen.
  ///
  /// In en, this message translates to:
  /// **'{email} will be linked to the Employee chosen here, or to none.'**
  String accountEmployeeWillBeLinkedToTheEmployeeChosen(Object email);

  /// No description provided for @commonResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get commonResetPassword;

  /// No description provided for @accountPasswordChooseANewPasswordForTellThem.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password for {email}. Tell them what it is yourself; it is not shown again.'**
  String accountPasswordChooseANewPasswordForTellThem(Object email);

  /// No description provided for @accountPasswordAtLeastCharacters.
  ///
  /// In en, this message translates to:
  /// **'At least {minimumPasswordLength} characters.'**
  String accountPasswordAtLeastCharacters(Object minimumPasswordLength);

  /// No description provided for @accountRolesRolesFor.
  ///
  /// In en, this message translates to:
  /// **'Roles for {accountName}'**
  String accountRolesRolesFor(Object accountName);

  /// No description provided for @commonAssigning.
  ///
  /// In en, this message translates to:
  /// **'Assigning…'**
  String get commonAssigning;

  /// No description provided for @accountRolesRoleAssigned.
  ///
  /// In en, this message translates to:
  /// **'{length, plural, =1{1 role assigned} other{{length} roles assigned}}'**
  String accountRolesRoleAssigned(int length);

  /// No description provided for @accountRolesEveryAccountHoldsThis.
  ///
  /// In en, this message translates to:
  /// **'{code} — every Account holds this'**
  String accountRolesEveryAccountHoldsThis(Object code);

  /// No description provided for @accountRolesEveryAccountWhoseOwnRoleIs.
  ///
  /// In en, this message translates to:
  /// **'{code} — every Account whose own role is {legacyRole}'**
  String accountRolesEveryAccountWhoseOwnRoleIs(Object code, Object legacyRole);

  /// No description provided for @accountRolesPermission.
  ///
  /// In en, this message translates to:
  /// **'{code} — {length, plural, =1{1 permission} other{{length} permissions}}'**
  String accountRolesPermission(String code, int length);

  /// No description provided for @accountsTheAccountsCouldNotBeLoaded.
  ///
  /// In en, this message translates to:
  /// **'The Accounts could not be loaded'**
  String get accountsTheAccountsCouldNotBeLoaded;

  /// No description provided for @accountsNoAccountsYet.
  ///
  /// In en, this message translates to:
  /// **'No Accounts yet'**
  String get accountsNoAccountsYet;

  /// No description provided for @accountsAccountsAppearHereAsSoonAsSomebody.
  ///
  /// In en, this message translates to:
  /// **'Accounts appear here as soon as somebody signs in for the first time.'**
  String get accountsAccountsAppearHereAsSoonAsSomebody;

  /// No description provided for @accountsEveryAccountOnThisPlantWhatIt.
  ///
  /// In en, this message translates to:
  /// **'Every Account on this plant: what it holds, and whether it can sign in.'**
  String get accountsEveryAccountOnThisPlantWhatIt;

  /// No description provided for @commonFilterAccounts.
  ///
  /// In en, this message translates to:
  /// **'Filter Accounts'**
  String get commonFilterAccounts;

  /// No description provided for @accountsByNameEmailOrRole.
  ///
  /// In en, this message translates to:
  /// **'By name, email or role.'**
  String get accountsByNameEmailOrRole;

  /// No description provided for @commonNoAccountsMatch.
  ///
  /// In en, this message translates to:
  /// **'No Accounts match'**
  String get commonNoAccountsMatch;

  /// No description provided for @accountsThisPlantHasAccountsButNoneMatches.
  ///
  /// In en, this message translates to:
  /// **'This plant has Accounts, but none matches \"{term}\". Try a different name, email or role, or clear the filter.'**
  String accountsThisPlantHasAccountsButNoneMatches(Object term);

  /// No description provided for @accountsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountsEmail;

  /// No description provided for @accountsRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get accountsRole;

  /// No description provided for @accountsStanding.
  ///
  /// In en, this message translates to:
  /// **'Standing'**
  String get accountsStanding;

  /// No description provided for @accountsSince.
  ///
  /// In en, this message translates to:
  /// **'Since'**
  String get accountsSince;

  /// No description provided for @accountsGrants.
  ///
  /// In en, this message translates to:
  /// **'Grants'**
  String get accountsGrants;

  /// No description provided for @accountsReviewInApprovals.
  ///
  /// In en, this message translates to:
  /// **'Review in Approvals'**
  String get accountsReviewInApprovals;

  /// No description provided for @accountsChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get accountsChange;

  /// No description provided for @accountsLinkAnEmployee.
  ///
  /// In en, this message translates to:
  /// **'Link an Employee'**
  String get accountsLinkAnEmployee;

  /// No description provided for @accountsEverywhere.
  ///
  /// In en, this message translates to:
  /// **'Everywhere'**
  String get accountsEverywhere;

  /// No description provided for @accountsNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get accountsNone;

  /// No description provided for @accountsOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Org Unit} other{{count} Org Units}}'**
  String accountsOrgUnit(int count);

  /// No description provided for @accountsActsEverywhereInEverySiteNoOrg.
  ///
  /// In en, this message translates to:
  /// **'Acts everywhere, in every Site. No Org Unit Grants, and none needed.'**
  String get accountsActsEverywhereInEverySiteNoOrg;

  /// No description provided for @accountsNoOrgUnitGrantsCanSignIn.
  ///
  /// In en, this message translates to:
  /// **'No Org Unit Grants. Can sign in, but cannot act in any Org Unit.'**
  String get accountsNoOrgUnitGrantsCanSignIn;

  /// No description provided for @accountsDeactivateThisAccount.
  ///
  /// In en, this message translates to:
  /// **'Deactivate this Account?'**
  String get accountsDeactivateThisAccount;

  /// No description provided for @accountsWillNotBeAbleToSignIn.
  ///
  /// In en, this message translates to:
  /// **'{email} will not be able to sign in. Nothing is deleted — the role and the Org Unit Grants stay exactly as they are, and an administrator can reactivate the Account at any time.'**
  String accountsWillNotBeAbleToSignIn(Object email);

  /// No description provided for @admissionAdmitThisAccount.
  ///
  /// In en, this message translates to:
  /// **'Admit this Account'**
  String get admissionAdmitThisAccount;

  /// No description provided for @commonAdmitting.
  ///
  /// In en, this message translates to:
  /// **'Admitting…'**
  String get commonAdmitting;

  /// No description provided for @commonAdmit.
  ///
  /// In en, this message translates to:
  /// **'Admit'**
  String get commonAdmit;

  /// No description provided for @admissionWillBeLetInToThePlatform.
  ///
  /// In en, this message translates to:
  /// **'{email} will be let in to the Platform with the role chosen here.'**
  String admissionWillBeLetInToThePlatform(Object email);

  /// No description provided for @admissionAnAdministratorCanActEverywhereThisAccount.
  ///
  /// In en, this message translates to:
  /// **'An administrator can act everywhere. This Account will be able to see and change every Site and every Org Unit, and to admit other Accounts. No Org Unit Grants are given, and none are needed.'**
  String get admissionAnAdministratorCanActEverywhereThisAccount;

  /// No description provided for @admissionThisAccountWillBeAdmittedWithNo.
  ///
  /// In en, this message translates to:
  /// **'This Account will be admitted with no Org Unit Grants, so it can sign in but cannot yet act in any Org Unit.'**
  String get admissionThisAccountWillBeAdmittedWithNo;

  /// No description provided for @approvalQueueTheQueueCouldNotBeLoaded.
  ///
  /// In en, this message translates to:
  /// **'The queue could not be loaded'**
  String get approvalQueueTheQueueCouldNotBeLoaded;

  /// No description provided for @approvalQueueNobodyIsWaiting.
  ///
  /// In en, this message translates to:
  /// **'Nobody is waiting'**
  String get approvalQueueNobodyIsWaiting;

  /// No description provided for @approvalQueueEveryAccountHasBeenDealtWithNew.
  ///
  /// In en, this message translates to:
  /// **'Every Account has been dealt with. New requests appear here.'**
  String get approvalQueueEveryAccountHasBeenDealtWithNew;

  /// No description provided for @approvalQueueEveryoneWaitingToBeLetInTo.
  ///
  /// In en, this message translates to:
  /// **'Everyone waiting to be let in to the Platform.'**
  String get approvalQueueEveryoneWaitingToBeLetInTo;

  /// No description provided for @approvalQueueByEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'By email address.'**
  String get approvalQueueByEmailAddress;

  /// No description provided for @approvalQueueAccountsAreWaitingButNoneMatchesTry.
  ///
  /// In en, this message translates to:
  /// **'Accounts are waiting, but none matches \"{term}\". Try a different email address, or clear the filter.'**
  String approvalQueueAccountsAreWaitingButNoneMatchesTry(Object term);

  /// No description provided for @approvalQueueAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get approvalQueueAccount;

  /// No description provided for @approvalQueueSuggestedEmployee.
  ///
  /// In en, this message translates to:
  /// **'Suggested Employee'**
  String get approvalQueueSuggestedEmployee;

  /// No description provided for @approvalQueueWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get approvalQueueWaiting;

  /// No description provided for @approvalQueueRejecting.
  ///
  /// In en, this message translates to:
  /// **'Rejecting…'**
  String get approvalQueueRejecting;

  /// No description provided for @commonReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get commonReject;

  /// No description provided for @approvalQueueRejectThisAccount.
  ///
  /// In en, this message translates to:
  /// **'Reject this Account?'**
  String get approvalQueueRejectThisAccount;

  /// No description provided for @approvalQueueWillNotBeLetInToThe.
  ///
  /// In en, this message translates to:
  /// **'{email} will not be let in to the Platform, and will be told their request was turned down. An administrator can still admit them later.'**
  String approvalQueueWillNotBeLetInToThe(Object email);

  /// No description provided for @attendancePickerChooseAnOrgUnitAndAProduction.
  ///
  /// In en, this message translates to:
  /// **'Choose an Org Unit and a production day to open that shift\'s attendance sheet.'**
  String get attendancePickerChooseAnOrgUnitAndAProduction;

  /// No description provided for @attendancePickerProductionDay.
  ///
  /// In en, this message translates to:
  /// **'Production day'**
  String get attendancePickerProductionDay;

  /// No description provided for @attendancePickerTheShiftsCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The shifts could not be read'**
  String get attendancePickerTheShiftsCouldNotBeRead;

  /// No description provided for @attendancePickerNoShiftsAreScheduledHereOnThat.
  ///
  /// In en, this message translates to:
  /// **'No shifts are scheduled here on that day.'**
  String get attendancePickerNoShiftsAreScheduledHereOnThat;

  /// No description provided for @attendancePickerChooseAnotherProductionDayOrAnotherOrg.
  ///
  /// In en, this message translates to:
  /// **'Choose another production day, or another Org Unit.'**
  String get attendancePickerChooseAnotherProductionDayOrAnotherOrg;

  /// No description provided for @commonTheSitesAreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The Sites are unavailable.'**
  String get commonTheSitesAreUnavailable;

  /// No description provided for @commonThereAreNoSitesToBrowseYet.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites to browse yet.'**
  String get commonThereAreNoSitesToBrowseYet;

  /// No description provided for @commonNothingToBrowseInThisSite.
  ///
  /// In en, this message translates to:
  /// **'Nothing to browse in this Site.'**
  String get commonNothingToBrowseInThisSite;

  /// No description provided for @commonCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get commonCollapse;

  /// No description provided for @commonExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get commonExpand;

  /// No description provided for @attendanceRecordMark.
  ///
  /// In en, this message translates to:
  /// **'Mark {displayName}'**
  String attendanceRecordMark(Object displayName);

  /// No description provided for @attendanceRecordWorkedMinutes.
  ///
  /// In en, this message translates to:
  /// **'Worked minutes'**
  String get attendanceRecordWorkedMinutes;

  /// No description provided for @attendanceRecordOvertimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'Overtime minutes'**
  String get attendanceRecordOvertimeMinutes;

  /// No description provided for @attendanceSheetTheAttendanceSheetCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The attendance sheet could not be read'**
  String get attendanceSheetTheAttendanceSheetCouldNotBeRead;

  /// No description provided for @attendanceSheetNobodyWithAnEditGrantHereHas.
  ///
  /// In en, this message translates to:
  /// **'Nobody with an edit Grant here has opened this sheet yet, so there is nothing to show. Only a supervisor holding an edit Grant reaching this shift — or an administrator — can start it.'**
  String get attendanceSheetNobodyWithAnEditGrantHereHas;

  /// No description provided for @attendanceSheetConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get attendanceSheetConfirmed;

  /// No description provided for @attendanceSheetConfirming.
  ///
  /// In en, this message translates to:
  /// **'Confirming…'**
  String get attendanceSheetConfirming;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @attendanceSheetNobodyIsOnThisSheetYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody is on this sheet yet.'**
  String get attendanceSheetNobodyIsOnThisSheetYet;

  /// No description provided for @attendanceSheetAddAStandInFromTheDirectory.
  ///
  /// In en, this message translates to:
  /// **'Add a stand-in from the Directory below to open the sheet with somebody on it.'**
  String get attendanceSheetAddAStandInFromTheDirectory;

  /// No description provided for @attendanceSheetASupervisorHoldingAnEditGrantReaching.
  ///
  /// In en, this message translates to:
  /// **'A supervisor holding an edit Grant reaching this shift adds the people who were on it.'**
  String get attendanceSheetASupervisorHoldingAnEditGrantReaching;

  /// No description provided for @attendanceSheetMarkAnException.
  ///
  /// In en, this message translates to:
  /// **'Mark an exception'**
  String get attendanceSheetMarkAnException;

  /// No description provided for @attendanceSheetRemoveFromTheSheet.
  ///
  /// In en, this message translates to:
  /// **'Remove from the sheet'**
  String get attendanceSheetRemoveFromTheSheet;

  /// No description provided for @attendanceSheetAddAStandIn.
  ///
  /// In en, this message translates to:
  /// **'Add a stand-in'**
  String get attendanceSheetAddAStandIn;

  /// No description provided for @commonSearchTheDirectory.
  ///
  /// In en, this message translates to:
  /// **'Search the Directory'**
  String get commonSearchTheDirectory;

  /// No description provided for @attendanceSheetWorkedMin.
  ///
  /// In en, this message translates to:
  /// **'Worked (min)'**
  String get attendanceSheetWorkedMin;

  /// No description provided for @attendanceSheetOvertimeMin.
  ///
  /// In en, this message translates to:
  /// **'Overtime (min)'**
  String get attendanceSheetOvertimeMin;

  /// No description provided for @attendanceToConfirmPastShiftsWhoseSheetIsMissingOr.
  ///
  /// In en, this message translates to:
  /// **'Past shifts whose sheet is missing or hasn\'t been confirmed yet, oldest first, across the Org Units you can confirm one at.'**
  String get attendanceToConfirmPastShiftsWhoseSheetIsMissingOr;

  /// No description provided for @attendanceToConfirmTheWorklistCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The worklist could not be read'**
  String get attendanceToConfirmTheWorklistCouldNotBeRead;

  /// No description provided for @attendanceToConfirmNothingToConfirmHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing to confirm here.'**
  String get attendanceToConfirmNothingToConfirmHere;

  /// No description provided for @attendanceToConfirmEveryPastShiftYouCanConfirmHas.
  ///
  /// In en, this message translates to:
  /// **'Every past shift you can confirm has a confirmed sheet.'**
  String get attendanceToConfirmEveryPastShiftYouCanConfirmHas;

  /// No description provided for @attendanceToConfirmNoShiftInThisWindowNeedsConfirming.
  ///
  /// In en, this message translates to:
  /// **'No shift in this window needs confirming. Widen the window, or clear the Org Unit.'**
  String get attendanceToConfirmNoShiftInThisWindowNeedsConfirming;

  /// No description provided for @commonFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get commonFrom;

  /// No description provided for @commonOrgUnit2.
  ///
  /// In en, this message translates to:
  /// **'Org Unit: {orgUnitName}'**
  String commonOrgUnit2(Object orgUnitName);

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonHideOrgUnits.
  ///
  /// In en, this message translates to:
  /// **'Hide Org Units'**
  String get commonHideOrgUnits;

  /// No description provided for @commonFilterByOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Filter by Org Unit'**
  String get commonFilterByOrgUnit;

  /// No description provided for @attendanceToConfirmOpenSheet.
  ///
  /// In en, this message translates to:
  /// **'Open sheet'**
  String get attendanceToConfirmOpenSheet;

  /// No description provided for @commonUsd.
  ///
  /// In en, this message translates to:
  /// **'USD'**
  String get commonUsd;

  /// No description provided for @costRateFormTheRateBelowIsClosedOnThe.
  ///
  /// In en, this message translates to:
  /// **'The rate below is closed on the day the new one takes effect. It stays readable, and a cost asked for an earlier date still resolves it.'**
  String get costRateFormTheRateBelowIsClosedOnThe;

  /// No description provided for @costRateFormTheListOfSitesOrgUnitsAssets.
  ///
  /// In en, this message translates to:
  /// **'The list of Sites, Org Units, Assets and cost centres could not be read, so a scope cannot be chosen: {scopesFailure}'**
  String costRateFormTheListOfSitesOrgUnitsAssets(Object scopesFailure);

  /// No description provided for @commonScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get commonScope;

  /// No description provided for @costRateFormWhich.
  ///
  /// In en, this message translates to:
  /// **'Which {value}'**
  String costRateFormWhich(Object value);

  /// No description provided for @costRateFormRateType.
  ///
  /// In en, this message translates to:
  /// **'Rate type'**
  String get costRateFormRateType;

  /// No description provided for @costRateFormScopeAndRateType.
  ///
  /// In en, this message translates to:
  /// **'Scope and rate type'**
  String get costRateFormScopeAndRateType;

  /// No description provided for @costRateFormARateSScopeAndRateType.
  ///
  /// In en, this message translates to:
  /// **'A rate\'s scope and rate type cannot be corrected — add a rate for the new scope instead'**
  String get costRateFormARateSScopeAndRateType;

  /// No description provided for @costRateFormMultiplier15ForTimeAndA.
  ///
  /// In en, this message translates to:
  /// **'Multiplier (1.5 for time-and-a-half)'**
  String get costRateFormMultiplier15ForTimeAndA;

  /// No description provided for @costRateFormAmountPerHour.
  ///
  /// In en, this message translates to:
  /// **'Amount per hour'**
  String get costRateFormAmountPerHour;

  /// No description provided for @costRateFormTheNewAmountFromTheDateBelow.
  ///
  /// In en, this message translates to:
  /// **'The new amount, from the date below'**
  String get costRateFormTheNewAmountFromTheDateBelow;

  /// No description provided for @commonCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get commonCurrency;

  /// No description provided for @commonAThreeLetterCodeSuchAsUsd.
  ///
  /// In en, this message translates to:
  /// **'A three-letter code, such as USD'**
  String get commonAThreeLetterCodeSuchAsUsd;

  /// No description provided for @costRateFormNewRateTakesEffectOn.
  ///
  /// In en, this message translates to:
  /// **'New rate takes effect on'**
  String get costRateFormNewRateTakesEffectOn;

  /// No description provided for @commonTakesEffectOn.
  ///
  /// In en, this message translates to:
  /// **'Takes effect on'**
  String get commonTakesEffectOn;

  /// No description provided for @costRateFormTheOldRateIsClosedOnThis.
  ///
  /// In en, this message translates to:
  /// **'The old rate is closed on this day, and the new one starts'**
  String get costRateFormTheOldRateIsClosedOnThis;

  /// No description provided for @commonAppliesUntilOptional.
  ///
  /// In en, this message translates to:
  /// **'Applies until (optional)'**
  String get commonAppliesUntilOptional;

  /// No description provided for @costRateFormLeftBlankThisRateIsTheCurrent.
  ///
  /// In en, this message translates to:
  /// **'Left blank, this rate is the current one. Setting it closes the rate on that day, which is the exclusive end of the period.'**
  String get costRateFormLeftBlankThisRateIsTheCurrent;

  /// No description provided for @costRatesTheCostRateCatalogueCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The cost rate catalogue could not be read'**
  String get costRatesTheCostRateCatalogueCouldNotBe;

  /// No description provided for @costRatesWhatAnHourCostsOneCatalogueShared.
  ///
  /// In en, this message translates to:
  /// **'What an hour costs — one catalogue shared by every Site, and what the Cost numbers on the tier board are worked out from. A rate is never overwritten: it is closed, and a new one opened, so a cost reported for an earlier month stays what it was.'**
  String get costRatesWhatAnHourCostsOneCatalogueShared;

  /// No description provided for @costRatesAddCostRate.
  ///
  /// In en, this message translates to:
  /// **'Add cost rate'**
  String get costRatesAddCostRate;

  /// No description provided for @costRatesNoCostRatesYet.
  ///
  /// In en, this message translates to:
  /// **'No cost rates yet'**
  String get costRatesNoCostRatesYet;

  /// No description provided for @costRatesUntilARateIsSetEveryCost.
  ///
  /// In en, this message translates to:
  /// **'Until a rate is set, every Cost number resolves to nothing.'**
  String get costRatesUntilARateIsSetEveryCost;

  /// No description provided for @costRatesRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get costRatesRate;

  /// No description provided for @commonPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get commonPeriod;

  /// No description provided for @commonCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get commonCorrect;

  /// No description provided for @commonRevise.
  ///
  /// In en, this message translates to:
  /// **'Revise'**
  String get commonRevise;

  /// No description provided for @commonClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get commonClosed;

  /// No description provided for @directoryTheDirectoryCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Directory could not be read'**
  String get directoryTheDirectoryCouldNotBeRead;

  /// No description provided for @directoryNobodyMatchesThisSearch.
  ///
  /// In en, this message translates to:
  /// **'Nobody matches this search'**
  String get directoryNobodyMatchesThisSearch;

  /// No description provided for @directoryTryADifferentNameOrClearA.
  ///
  /// In en, this message translates to:
  /// **'Try a different name, or clear a filter.'**
  String get directoryTryADifferentNameOrClearA;

  /// No description provided for @directoryWhoWorksHereSearchedFilteredAndDeparted.
  ///
  /// In en, this message translates to:
  /// **'Who works here — searched, filtered, and Departed Employees kept out of sight until asked for.'**
  String get directoryWhoWorksHereSearchedFilteredAndDeparted;

  /// No description provided for @commonAddEmployee.
  ///
  /// In en, this message translates to:
  /// **'Add Employee'**
  String get commonAddEmployee;

  /// No description provided for @directoryMyRecord.
  ///
  /// In en, this message translates to:
  /// **'My record'**
  String get directoryMyRecord;

  /// No description provided for @directorySearchByName.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get directorySearchByName;

  /// No description provided for @commonJobRole.
  ///
  /// In en, this message translates to:
  /// **'Job role'**
  String get commonJobRole;

  /// No description provided for @directoryAllJobRoles.
  ///
  /// In en, this message translates to:
  /// **'All job roles'**
  String get directoryAllJobRoles;

  /// No description provided for @directoryIncludeDeparted.
  ///
  /// In en, this message translates to:
  /// **'Include Departed'**
  String get directoryIncludeDeparted;

  /// No description provided for @commonEmployment.
  ///
  /// In en, this message translates to:
  /// **'Employment'**
  String get commonEmployment;

  /// No description provided for @commonDeparted.
  ///
  /// In en, this message translates to:
  /// **'Departed'**
  String get commonDeparted;

  /// No description provided for @commonActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get commonActive;

  /// No description provided for @employeeAssignmentAssignToAnOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Assign {displayName} to an Org Unit'**
  String employeeAssignmentAssignToAnOrgUnit(Object displayName);

  /// No description provided for @employeeAssignmentWhereItWorksNow.
  ///
  /// In en, this message translates to:
  /// **'Where it works now'**
  String get employeeAssignmentWhereItWorksNow;

  /// No description provided for @employeeAssignmentJobRoleOptional.
  ///
  /// In en, this message translates to:
  /// **'Job role (optional)'**
  String get employeeAssignmentJobRoleOptional;

  /// No description provided for @employeeAssignmentNoJobRole.
  ///
  /// In en, this message translates to:
  /// **'No job role'**
  String get employeeAssignmentNoJobRole;

  /// No description provided for @employeeAssignmentEffectiveDate.
  ///
  /// In en, this message translates to:
  /// **'Effective date'**
  String get employeeAssignmentEffectiveDate;

  /// No description provided for @employeeCorrectionCorrectSRecord.
  ///
  /// In en, this message translates to:
  /// **'Correct {displayName}\'s record'**
  String employeeCorrectionCorrectSRecord(Object displayName);

  /// No description provided for @commonFirstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get commonFirstName;

  /// No description provided for @commonLastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get commonLastName;

  /// No description provided for @commonEmploymentType.
  ///
  /// In en, this message translates to:
  /// **'Employment type'**
  String get commonEmploymentType;

  /// No description provided for @commonWorkEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Work email (optional)'**
  String get commonWorkEmailOptional;

  /// No description provided for @employeeDepartureRecordThatHasLeft.
  ///
  /// In en, this message translates to:
  /// **'Record that {displayName} has left'**
  String employeeDepartureRecordThatHasLeft(Object displayName);

  /// No description provided for @employeeDepartureAccountStillLinked.
  ///
  /// In en, this message translates to:
  /// **'Account still linked'**
  String get employeeDepartureAccountStillLinked;

  /// No description provided for @employeeDepartureTheRecordStaysNothingIsDeletedAnd.
  ///
  /// In en, this message translates to:
  /// **'The record stays — nothing is deleted, and this can be undone by reinstating the record at any time.'**
  String get employeeDepartureTheRecordStaysNothingIsDeletedAnd;

  /// No description provided for @employeeDepartureEffectiveDateOptional.
  ///
  /// In en, this message translates to:
  /// **'Effective date (optional)'**
  String get employeeDepartureEffectiveDateOptional;

  /// No description provided for @commonLeftBlankTodayIsRecorded.
  ///
  /// In en, this message translates to:
  /// **'Left blank, today is recorded.'**
  String get commonLeftBlankTodayIsRecorded;

  /// No description provided for @employeeDepartureRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get employeeDepartureRecording;

  /// No description provided for @commonRecordDeparture.
  ///
  /// In en, this message translates to:
  /// **'Record departure'**
  String get commonRecordDeparture;

  /// No description provided for @employeeDepartureHasLeftAndTheirAccountCanStill.
  ///
  /// In en, this message translates to:
  /// **'{displayName} has left, and their Account ({email}) can still sign in. The departure is already recorded either way — deactivating the Account is a separate, optional step.'**
  String employeeDepartureHasLeftAndTheirAccountCanStill(
    Object displayName,
    Object email,
  );

  /// No description provided for @employeeDepartureNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get employeeDepartureNotNow;

  /// No description provided for @employeeDepartureDeactivating.
  ///
  /// In en, this message translates to:
  /// **'Deactivating…'**
  String get employeeDepartureDeactivating;

  /// No description provided for @employeeDepartureDeactivateAccount.
  ///
  /// In en, this message translates to:
  /// **'Deactivate Account'**
  String get employeeDepartureDeactivateAccount;

  /// No description provided for @employeeDetailThisRecordCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'This record could not be read'**
  String get employeeDetailThisRecordCouldNotBeRead;

  /// No description provided for @employeeDetailAssignmentHistory.
  ///
  /// In en, this message translates to:
  /// **'Assignment history'**
  String get employeeDetailAssignmentHistory;

  /// No description provided for @employeeDetailNoAssignmentHasBeenRecorded.
  ///
  /// In en, this message translates to:
  /// **'No Assignment has been recorded.'**
  String get employeeDetailNoAssignmentHasBeenRecorded;

  /// No description provided for @employeeDetailRecordSkill.
  ///
  /// In en, this message translates to:
  /// **'Record skill'**
  String get employeeDetailRecordSkill;

  /// No description provided for @employeeDetailNoQualificationsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No qualifications recorded.'**
  String get employeeDetailNoQualificationsRecorded;

  /// No description provided for @employeeDetailHired.
  ///
  /// In en, this message translates to:
  /// **'Hired'**
  String get employeeDetailHired;

  /// No description provided for @employeeDetailWorkEmail.
  ///
  /// In en, this message translates to:
  /// **'Work email'**
  String get employeeDetailWorkEmail;

  /// No description provided for @commonCorrectRecord.
  ///
  /// In en, this message translates to:
  /// **'Correct record'**
  String get commonCorrectRecord;

  /// No description provided for @employeeDetailSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get employeeDetailSignature;

  /// No description provided for @commonReinstate.
  ///
  /// In en, this message translates to:
  /// **'Reinstate'**
  String get commonReinstate;

  /// No description provided for @employeeDetailCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get employeeDetailCurrent;

  /// No description provided for @employeeDetailLapsed.
  ///
  /// In en, this message translates to:
  /// **'{name} · Lapsed'**
  String employeeDetailLapsed(Object name);

  /// No description provided for @employeeDetailReAssess.
  ///
  /// In en, this message translates to:
  /// **'Re-assess'**
  String get employeeDetailReAssess;

  /// No description provided for @commonAdding.
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get commonAdding;

  /// No description provided for @employeeLinkPickerSuggestedMatch.
  ///
  /// In en, this message translates to:
  /// **'Suggested match: {value}'**
  String employeeLinkPickerSuggestedMatch(Object value);

  /// No description provided for @employeeLinkPickerLinkedTo.
  ///
  /// In en, this message translates to:
  /// **'Linked to: {value}'**
  String employeeLinkPickerLinkedTo(Object value);

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @employeeLinkPickerNoEmployeeWillBeLinked.
  ///
  /// In en, this message translates to:
  /// **'No Employee will be linked.'**
  String get employeeLinkPickerNoEmployeeWillBeLinked;

  /// No description provided for @employeeSignatureNoSignatureIsKeptForUploadA.
  ///
  /// In en, this message translates to:
  /// **'No Signature is kept for {displayName}. Upload a picture of it, or draw it here.'**
  String employeeSignatureNoSignatureIsKeptForUploadA(Object displayName);

  /// No description provided for @commonThisSignatureCouldNotBeShown.
  ///
  /// In en, this message translates to:
  /// **'This Signature could not be shown.'**
  String get commonThisSignatureCouldNotBeShown;

  /// No description provided for @employeeSignatureSetForBy.
  ///
  /// In en, this message translates to:
  /// **'Set for {displayName} by {who}'**
  String employeeSignatureSetForBy(Object displayName, Object who);

  /// No description provided for @employeeSignatureSetBy.
  ///
  /// In en, this message translates to:
  /// **'Set by {displayName}'**
  String employeeSignatureSetBy(Object displayName);

  /// No description provided for @employeeSignatureSignatureOf.
  ///
  /// In en, this message translates to:
  /// **'Signature of {displayName}'**
  String employeeSignatureSignatureOf(Object displayName);

  /// No description provided for @commonUploadAPicture.
  ///
  /// In en, this message translates to:
  /// **'Upload a picture'**
  String get commonUploadAPicture;

  /// No description provided for @commonReplaceWithAPicture.
  ///
  /// In en, this message translates to:
  /// **'Replace with a picture'**
  String get commonReplaceWithAPicture;

  /// No description provided for @commonDrawIt.
  ///
  /// In en, this message translates to:
  /// **'Draw it'**
  String get commonDrawIt;

  /// No description provided for @commonDrawANewOne.
  ///
  /// In en, this message translates to:
  /// **'Draw a new one'**
  String get commonDrawANewOne;

  /// No description provided for @commonKeepThisSignature.
  ///
  /// In en, this message translates to:
  /// **'Keep this Signature'**
  String get commonKeepThisSignature;

  /// No description provided for @employeeSkillFormReAssessFor.
  ///
  /// In en, this message translates to:
  /// **'Re-assess {value} for {displayName}'**
  String employeeSkillFormReAssessFor(Object value, Object displayName);

  /// No description provided for @employeeSkillFormRecordASkillFor.
  ///
  /// In en, this message translates to:
  /// **'Record a skill for {displayName}'**
  String employeeSkillFormRecordASkillFor(Object displayName);

  /// No description provided for @employeeSkillFormSkill.
  ///
  /// In en, this message translates to:
  /// **'Skill'**
  String get employeeSkillFormSkill;

  /// No description provided for @employeeSkillFormProficiency04Iluo.
  ///
  /// In en, this message translates to:
  /// **'Proficiency (0–4, ILUO)'**
  String get employeeSkillFormProficiency04Iluo;

  /// No description provided for @employeeSkillForm0None.
  ///
  /// In en, this message translates to:
  /// **'0 — none'**
  String get employeeSkillForm0None;

  /// No description provided for @employeeSkillFormAssessedOnOptional.
  ///
  /// In en, this message translates to:
  /// **'Assessed on (optional)'**
  String get employeeSkillFormAssessedOnOptional;

  /// No description provided for @employeeSkillFormExpiresOnOptional.
  ///
  /// In en, this message translates to:
  /// **'Expires on (optional)'**
  String get employeeSkillFormExpiresOnOptional;

  /// No description provided for @employeeSkillFormLeftBlankNeverExpiresOrIsRe.
  ///
  /// In en, this message translates to:
  /// **'Left blank, never expires (or is re-derived from the skill\'s own revalidation period).'**
  String get employeeSkillFormLeftBlankNeverExpiresOrIsRe;

  /// No description provided for @employeeSkillFormEvidenceReferenceOptional.
  ///
  /// In en, this message translates to:
  /// **'Evidence reference (optional)'**
  String get employeeSkillFormEvidenceReferenceOptional;

  /// No description provided for @floorTrainingTrainingFor.
  ///
  /// In en, this message translates to:
  /// **'Training for {employeeName}'**
  String floorTrainingTrainingFor(Object employeeName);

  /// No description provided for @floorTrainingYourTraining.
  ///
  /// In en, this message translates to:
  /// **'Your training'**
  String get floorTrainingYourTraining;

  /// No description provided for @floorTrainingDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get floorTrainingDone;

  /// No description provided for @floorTrainingShowMyTraining.
  ///
  /// In en, this message translates to:
  /// **'Show my training'**
  String get floorTrainingShowMyTraining;

  /// No description provided for @floorTrainingWhoAreYouYourEmployeeNumberAnd.
  ///
  /// In en, this message translates to:
  /// **'Who are you? Your Employee number and PIN show the training waiting on you at this device.'**
  String get floorTrainingWhoAreYouYourEmployeeNumberAnd;

  /// No description provided for @floorTrainingScanTheBadgeOrTypeTheNumber.
  ///
  /// In en, this message translates to:
  /// **'Scan the badge or type the number.'**
  String get floorTrainingScanTheBadgeOrTypeTheNumber;

  /// No description provided for @floorTrainingNothingIsWaitingOnYouAtThis.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting on you at this device.'**
  String get floorTrainingNothingIsWaitingOnYouAtThis;

  /// No description provided for @jobRoleFormCorrectJobRole.
  ///
  /// In en, this message translates to:
  /// **'Correct job role'**
  String get jobRoleFormCorrectJobRole;

  /// No description provided for @commonAddJobRole.
  ///
  /// In en, this message translates to:
  /// **'Add job role'**
  String get commonAddJobRole;

  /// No description provided for @jobRolesTheJobRoleCatalogueCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The job role catalogue could not be read'**
  String get jobRolesTheJobRoleCatalogueCouldNotBe;

  /// No description provided for @jobRolesWhatAnEmployeeDoesDefinedOnceShared.
  ///
  /// In en, this message translates to:
  /// **'What an Employee does — defined once, shared by every Site.'**
  String get jobRolesWhatAnEmployeeDoesDefinedOnceShared;

  /// No description provided for @jobRolesNoJobRolesYet.
  ///
  /// In en, this message translates to:
  /// **'No job roles yet'**
  String get jobRolesNoJobRolesYet;

  /// No description provided for @commonNothingHasBeenDefinedInTheCatalogue.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been defined in the catalogue.'**
  String get commonNothingHasBeenDefinedInTheCatalogue;

  /// No description provided for @jobRolesFilterJobRoles.
  ///
  /// In en, this message translates to:
  /// **'Filter job roles'**
  String get jobRolesFilterJobRoles;

  /// No description provided for @jobRolesByNameOrCode.
  ///
  /// In en, this message translates to:
  /// **'By name or code.'**
  String get jobRolesByNameOrCode;

  /// No description provided for @jobRolesNoJobRolesMatch.
  ///
  /// In en, this message translates to:
  /// **'No job roles match'**
  String get jobRolesNoJobRolesMatch;

  /// No description provided for @jobRolesNothingInTheCatalogueMatchesTryA.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the catalogue matches \"{term}\". Try a different name or code, or clear the filter.'**
  String jobRolesNothingInTheCatalogueMatchesTryA(Object term);

  /// No description provided for @leaveRequestCancelCancelLeaveRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel leave request'**
  String get leaveRequestCancelCancelLeaveRequest;

  /// No description provided for @leaveRequestCancelCancelTheRequestFor.
  ///
  /// In en, this message translates to:
  /// **'Cancel the {leaveTypeName} request for {displayName}, {periodLabel} ({daysLabel})?'**
  String leaveRequestCancelCancelTheRequestFor(
    Object leaveTypeName,
    Object displayName,
    Object periodLabel,
    Object daysLabel,
  );

  /// No description provided for @leaveRequestCancelKeepRequest.
  ///
  /// In en, this message translates to:
  /// **'Keep request'**
  String get leaveRequestCancelKeepRequest;

  /// No description provided for @leaveRequestCancelCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get leaveRequestCancelCancelling;

  /// No description provided for @commonCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get commonCancelRequest;

  /// No description provided for @commonRequestLeave.
  ///
  /// In en, this message translates to:
  /// **'Request leave'**
  String get commonRequestLeave;

  /// No description provided for @leaveRequestFormRequesting.
  ///
  /// In en, this message translates to:
  /// **'Requesting…'**
  String get leaveRequestFormRequesting;

  /// No description provided for @leaveRequestFormLeaveTypesCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'Leave types could not be read'**
  String get leaveRequestFormLeaveTypesCouldNotBeRead;

  /// No description provided for @leaveRequestFormLeaveType.
  ///
  /// In en, this message translates to:
  /// **'Leave type'**
  String get leaveRequestFormLeaveType;

  /// No description provided for @leaveRequestFormFirstDay.
  ///
  /// In en, this message translates to:
  /// **'First day'**
  String get leaveRequestFormFirstDay;

  /// No description provided for @leaveRequestFormLastDay.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get leaveRequestFormLastDay;

  /// No description provided for @leaveRequestsLeaveRequestsCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'Leave requests could not be read'**
  String get leaveRequestsLeaveRequestsCouldNotBeRead;

  /// No description provided for @leaveRequestsAskToBeAwayFromWorkAnd.
  ///
  /// In en, this message translates to:
  /// **'Ask to be away from work, and follow what became of it.'**
  String get leaveRequestsAskToBeAwayFromWorkAnd;

  /// No description provided for @leaveRequestsMine.
  ///
  /// In en, this message translates to:
  /// **'Mine'**
  String get leaveRequestsMine;

  /// No description provided for @leaveRequestsToDecide.
  ///
  /// In en, this message translates to:
  /// **'To decide'**
  String get leaveRequestsToDecide;

  /// No description provided for @leaveRequestsNoLeaveRequestsYet.
  ///
  /// In en, this message translates to:
  /// **'No leave requests yet'**
  String get leaveRequestsNoLeaveRequestsYet;

  /// No description provided for @leaveRequestsNothingToDecide.
  ///
  /// In en, this message translates to:
  /// **'Nothing to decide'**
  String get leaveRequestsNothingToDecide;

  /// No description provided for @leaveRequestsRequestLeaveToAskForTimeAway.
  ///
  /// In en, this message translates to:
  /// **'Request leave to ask for time away.'**
  String get leaveRequestsRequestLeaveToAskForTimeAway;

  /// No description provided for @leaveRequestsNoPendingLeaveRequestsAreWaitingFor.
  ///
  /// In en, this message translates to:
  /// **'No pending leave requests are waiting for you.'**
  String get leaveRequestsNoPendingLeaveRequestsAreWaitingFor;

  /// No description provided for @leaveRequestsNote.
  ///
  /// In en, this message translates to:
  /// **'Note: {note}'**
  String leaveRequestsNote(Object note);

  /// No description provided for @leaveRequestsDecisionNote.
  ///
  /// In en, this message translates to:
  /// **'Decision note: {decisionNote}'**
  String leaveRequestsDecisionNote(Object decisionNote);

  /// No description provided for @leaveRequestsApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get leaveRequestsApprove;

  /// No description provided for @mySignatureYourSignatureCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'Your Signature could not be read'**
  String get mySignatureYourSignatureCouldNotBeRead;

  /// No description provided for @mySignatureNoSignatureKept.
  ///
  /// In en, this message translates to:
  /// **'No Signature kept'**
  String get mySignatureNoSignatureKept;

  /// No description provided for @mySignatureYouHaveNotKeptASignatureYet.
  ///
  /// In en, this message translates to:
  /// **'You have not kept a Signature yet. Upload a picture of it, or draw it here.'**
  String get mySignatureYouHaveNotKeptASignatureYet;

  /// No description provided for @mySignatureYourSignature.
  ///
  /// In en, this message translates to:
  /// **'Your Signature'**
  String get mySignatureYourSignature;

  /// No description provided for @mySignatureYourOwnMarkKeptOnceAndApplied.
  ///
  /// In en, this message translates to:
  /// **'Your own mark, kept once and applied wherever you would otherwise sign a sheet by hand. Replacing it never changes a sheet you have already signed.'**
  String get mySignatureYourOwnMarkKeptOnceAndApplied;

  /// No description provided for @mySignatureDrawYourSignature.
  ///
  /// In en, this message translates to:
  /// **'Draw your Signature'**
  String get mySignatureDrawYourSignature;

  /// No description provided for @commonAddRootOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Add root Org Unit'**
  String get commonAddRootOrgUnit;

  /// No description provided for @orgUnitFormAddOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Add Org Unit'**
  String get orgUnitFormAddOrgUnit;

  /// No description provided for @orgUnitFormUnitType.
  ///
  /// In en, this message translates to:
  /// **'Unit type'**
  String get orgUnitFormUnitType;

  /// No description provided for @orgUnitFormSortOrderOptional.
  ///
  /// In en, this message translates to:
  /// **'Sort order (optional)'**
  String get orgUnitFormSortOrderOptional;

  /// No description provided for @commonImportABranch.
  ///
  /// In en, this message translates to:
  /// **'Import a branch'**
  String get commonImportABranch;

  /// No description provided for @orgUnitImportImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get orgUnitImportImporting;

  /// No description provided for @orgUnitImportImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get orgUnitImportImport;

  /// No description provided for @orgUnitImportAJsonArrayOfRowsEachRow.
  ///
  /// In en, this message translates to:
  /// **'A JSON array of rows. Each row references its own parent by \"parentCode\" — another row in this same array, or an existing code at this Site — never by id.'**
  String get orgUnitImportAJsonArrayOfRowsEachRow;

  /// No description provided for @orgUnitImportRow.
  ///
  /// In en, this message translates to:
  /// **'Row {row}{code}{field}: {message}'**
  String orgUnitImportRow(
    String row,
    String code,
    String field,
    String message,
  );

  /// No description provided for @orgUnitPickerOrgUnitGrants.
  ///
  /// In en, this message translates to:
  /// **'Org Unit Grants'**
  String get orgUnitPickerOrgUnitGrants;

  /// No description provided for @orgUnitPickerEverythingOnTheRightIsWhatThis.
  ///
  /// In en, this message translates to:
  /// **'Everything on the right is what this Account will hold. Nothing is added to what it has now — this is the whole set.'**
  String get orgUnitPickerEverythingOnTheRightIsWhatThis;

  /// No description provided for @orgUnitPickerQualityAuthorityAndSafetyAuthorityAreEach.
  ///
  /// In en, this message translates to:
  /// **'Quality authority and Safety authority are each separate from the level and from each other — a view-only Grant may carry either, and an edit Grant need not — and each reaches everything beneath the Org Unit it is given on.'**
  String get orgUnitPickerQualityAuthorityAndSafetyAuthorityAreEach;

  /// No description provided for @orgUnitPickerBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get orgUnitPickerBrowse;

  /// No description provided for @orgUnitPickerGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get orgUnitPickerGranted;

  /// No description provided for @orgUnitPickerGrantThisOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Grant this Org Unit'**
  String get orgUnitPickerGrantThisOrgUnit;

  /// No description provided for @orgUnitPickerNothingBeneathThis.
  ///
  /// In en, this message translates to:
  /// **'Nothing beneath this'**
  String get orgUnitPickerNothingBeneathThis;

  /// No description provided for @orgUnitPickerGranted2.
  ///
  /// In en, this message translates to:
  /// **'Granted ({length})'**
  String orgUnitPickerGranted2(Object length);

  /// No description provided for @orgUnitPickerNoOrgUnitsGrantedThisAccountWill.
  ///
  /// In en, this message translates to:
  /// **'No Org Units granted. This Account will be able to sign in but not act anywhere.'**
  String get orgUnitPickerNoOrgUnitsGrantedThisAccountWill;

  /// No description provided for @orgUnitPickerQualityAuthority.
  ///
  /// In en, this message translates to:
  /// **'Quality authority'**
  String get orgUnitPickerQualityAuthority;

  /// No description provided for @orgUnitPickerSafetyAuthority.
  ///
  /// In en, this message translates to:
  /// **'Safety authority'**
  String get orgUnitPickerSafetyAuthority;

  /// No description provided for @orgUnitPickerRemoveThisGrant.
  ///
  /// In en, this message translates to:
  /// **'Remove this Grant'**
  String get orgUnitPickerRemoveThisGrant;

  /// No description provided for @orgUnitsASiteSOwnShapeWhereA.
  ///
  /// In en, this message translates to:
  /// **'A Site\'s own shape — where a KPI is measured, an Account is granted, and an Asset sits.'**
  String get orgUnitsASiteSOwnShapeWhereA;

  /// No description provided for @commonAddSite.
  ///
  /// In en, this message translates to:
  /// **'Add Site'**
  String get commonAddSite;

  /// No description provided for @commonEditSite.
  ///
  /// In en, this message translates to:
  /// **'Edit Site'**
  String get commonEditSite;

  /// No description provided for @orgUnitsTheSitesCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Sites could not be read'**
  String get orgUnitsTheSitesCouldNotBeRead;

  /// No description provided for @orgUnitsThereAreNoSitesYet.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites yet.'**
  String get orgUnitsThereAreNoSitesYet;

  /// No description provided for @orgUnitsAnAdministratorAddsTheFirstSiteEvery.
  ///
  /// In en, this message translates to:
  /// **'An administrator adds the first Site; every Org Unit sits beneath one.'**
  String get orgUnitsAnAdministratorAddsTheFirstSiteEvery;

  /// No description provided for @orgUnitsFindAnOrgUnitByName.
  ///
  /// In en, this message translates to:
  /// **'Find an Org Unit by name'**
  String get orgUnitsFindAnOrgUnitByName;

  /// No description provided for @orgUnitsPickingOneRevealsAndSelectsItIn.
  ///
  /// In en, this message translates to:
  /// **'Picking one reveals and selects it in the tree below.'**
  String get orgUnitsPickingOneRevealsAndSelectsItIn;

  /// No description provided for @orgUnitsRetired.
  ///
  /// In en, this message translates to:
  /// **'Retired'**
  String get orgUnitsRetired;

  /// No description provided for @orgUnitsTheOrgUnitTreeCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The Org Unit tree could not be read'**
  String get orgUnitsTheOrgUnitTreeCouldNotBe;

  /// No description provided for @orgUnitsNothingToBrowseInThisSiteYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing to browse in this Site yet.'**
  String get orgUnitsNothingToBrowseInThisSiteYet;

  /// No description provided for @orgUnitsAnAdministratorAddsTheFirstOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'An administrator adds the first Org Unit, or imports a branch.'**
  String get orgUnitsAnAdministratorAddsTheFirstOrgUnit;

  /// No description provided for @orgUnitsBelow.
  ///
  /// In en, this message translates to:
  /// **'{childCount} below'**
  String orgUnitsBelow(Object childCount);

  /// No description provided for @orgUnitsAddAnOrgUnitHere.
  ///
  /// In en, this message translates to:
  /// **'Add an Org Unit here'**
  String get orgUnitsAddAnOrgUnitHere;

  /// No description provided for @orgUnitsRetire.
  ///
  /// In en, this message translates to:
  /// **'Retire'**
  String get orgUnitsRetire;

  /// No description provided for @orgUnitsRetireThisOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Retire this Org Unit?'**
  String get orgUnitsRetireThisOrgUnit;

  /// No description provided for @orgUnitsWillReadAsRetiredRatherThanDeleted.
  ///
  /// In en, this message translates to:
  /// **'{name} will read as retired rather than deleted, and can be reinstated at any time.'**
  String orgUnitsWillReadAsRetiredRatherThanDeleted(Object name);

  /// No description provided for @productCostFormTheCostBelowIsClosedOnThe.
  ///
  /// In en, this message translates to:
  /// **'The cost below is closed on the day the new one takes effect. It stays readable, and scrap already costed at it keeps that figure.'**
  String get productCostFormTheCostBelowIsClosedOnThe;

  /// No description provided for @productCostFormTheProductListCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Product list could not be read, so a Product cannot be chosen: {productsFailure}'**
  String productCostFormTheProductListCouldNotBeRead(Object productsFailure);

  /// No description provided for @productCostFormTheProductAStandardCostBelongsTo.
  ///
  /// In en, this message translates to:
  /// **'The Product a standard cost belongs to cannot be corrected — record a cost against the other Product instead'**
  String get productCostFormTheProductAStandardCostBelongsTo;

  /// No description provided for @productCostFormStandardCostPerUnit.
  ///
  /// In en, this message translates to:
  /// **'Standard cost, per unit'**
  String get productCostFormStandardCostPerUnit;

  /// No description provided for @productCostFormTheNewCostFromTheDateBelow.
  ///
  /// In en, this message translates to:
  /// **'The new cost, from the date below'**
  String get productCostFormTheNewCostFromTheDateBelow;

  /// No description provided for @productCostFormNewCostTakesEffectOn.
  ///
  /// In en, this message translates to:
  /// **'New cost takes effect on'**
  String get productCostFormNewCostTakesEffectOn;

  /// No description provided for @productCostFormTheOldCostIsClosedOnThis.
  ///
  /// In en, this message translates to:
  /// **'The old cost is closed on this day, and the new one starts'**
  String get productCostFormTheOldCostIsClosedOnThis;

  /// No description provided for @productCostFormLeftBlankThisCostIsTheCurrent.
  ///
  /// In en, this message translates to:
  /// **'Left blank, this cost is the current one. Setting it closes the cost on that day, which is the exclusive end of the period.'**
  String get productCostFormLeftBlankThisCostIsTheCurrent;

  /// No description provided for @productCostsTheStandardCostCatalogueCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The standard cost catalogue could not be read'**
  String get productCostsTheStandardCostCatalogueCouldNotBe;

  /// No description provided for @productCostsWhatAUnitIsCostedAtOne.
  ///
  /// In en, this message translates to:
  /// **'What a unit is costed at — one catalogue shared by every Site, and what scrap and rework are priced with. A cost is never overwritten: it is closed, and a new one opened, so a cost reported for an earlier month stays what it was.'**
  String get productCostsWhatAUnitIsCostedAtOne;

  /// No description provided for @productCostsAddStandardCost.
  ///
  /// In en, this message translates to:
  /// **'Add standard cost'**
  String get productCostsAddStandardCost;

  /// No description provided for @productCostsNoStandardCostsYet.
  ///
  /// In en, this message translates to:
  /// **'No standard costs yet'**
  String get productCostsNoStandardCostsYet;

  /// No description provided for @productCostsUntilACostIsSetScrapAnd.
  ///
  /// In en, this message translates to:
  /// **'Until a cost is set, scrap and rework are priced at nothing.'**
  String get productCostsUntilACostIsSetScrapAnd;

  /// No description provided for @roleFormCorrectRole.
  ///
  /// In en, this message translates to:
  /// **'Correct role'**
  String get roleFormCorrectRole;

  /// No description provided for @commonAddRole.
  ///
  /// In en, this message translates to:
  /// **'Add role'**
  String get commonAddRole;

  /// No description provided for @roleForm330CharactersAZ09.
  ///
  /// In en, this message translates to:
  /// **'3–30 characters: A–Z, 0–9 and underscore, e.g. ROLE_STORE_ROOM'**
  String get roleForm330CharactersAZ09;

  /// No description provided for @roleFormWhatItIsFor.
  ///
  /// In en, this message translates to:
  /// **'What it is for'**
  String get roleFormWhatItIsFor;

  /// No description provided for @roleFormInActiveUse.
  ///
  /// In en, this message translates to:
  /// **'In active use'**
  String get roleFormInActiveUse;

  /// No description provided for @roleFormARetiredRoleKeepsItsHistoryAnd.
  ///
  /// In en, this message translates to:
  /// **'A retired role keeps its history and can be assigned to nobody.'**
  String get roleFormARetiredRoleKeepsItsHistoryAnd;

  /// No description provided for @rolePermissionsWhatCarries.
  ///
  /// In en, this message translates to:
  /// **'What {code} carries'**
  String rolePermissionsWhatCarries(Object code);

  /// No description provided for @rolePermissionsOfPermissions.
  ///
  /// In en, this message translates to:
  /// **'{length} of {total} permissions'**
  String rolePermissionsOfPermissions(Object length, Object total);

  /// No description provided for @rolesTheRolesCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The roles could not be read'**
  String get rolesTheRolesCouldNotBeRead;

  /// No description provided for @rolesWhatAnAccountMayDoEachRole.
  ///
  /// In en, this message translates to:
  /// **'What an Account may do. Each role is a group of permissions; every Account holds the default group, and a role marked automatic is earned by the Account\'s own role.'**
  String get rolesWhatAnAccountMayDoEachRole;

  /// No description provided for @rolesNoRoles.
  ///
  /// In en, this message translates to:
  /// **'No roles'**
  String get rolesNoRoles;

  /// No description provided for @rolesNothingIsCarryingAPermissionThatShould.
  ///
  /// In en, this message translates to:
  /// **'Nothing is carrying a permission. That should not happen: the seed creates the default group, so this means the deployment is incomplete.'**
  String get rolesNothingIsCarryingAPermissionThatShould;

  /// No description provided for @rolesDefaultGroup.
  ///
  /// In en, this message translates to:
  /// **'Default group'**
  String get rolesDefaultGroup;

  /// No description provided for @rolesAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic: {legacyRole}'**
  String rolesAutomatic(Object legacyRole);

  /// No description provided for @rolesReaches.
  ///
  /// In en, this message translates to:
  /// **'{length, plural, =1{1 permission} other{{length} permissions}} · reaches {holderCount, plural, =1{1 Account} other{{holderCount} Accounts}}'**
  String rolesReaches(int length, int holderCount);

  /// No description provided for @rolesPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get rolesPermissions;

  /// No description provided for @siteFormTimezonesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Timezones unavailable'**
  String get siteFormTimezonesUnavailable;

  /// No description provided for @siteFormTheTimezoneListCouldNotBeLoaded.
  ///
  /// In en, this message translates to:
  /// **'The timezone list could not be loaded.'**
  String get siteFormTheTimezoneListCouldNotBeLoaded;

  /// No description provided for @siteFormTimezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get siteFormTimezone;

  /// No description provided for @siteFormCountryCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Country code (optional)'**
  String get siteFormCountryCodeOptional;

  /// No description provided for @skillCoverageOrgUnitAndSkill.
  ///
  /// In en, this message translates to:
  /// **'Org Unit and skill'**
  String get skillCoverageOrgUnitAndSkill;

  /// No description provided for @skillCoverageRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get skillCoverageRequired;

  /// No description provided for @skillCoverageQualified.
  ///
  /// In en, this message translates to:
  /// **'Qualified'**
  String get skillCoverageQualified;

  /// No description provided for @skillCoverageLapsed.
  ///
  /// In en, this message translates to:
  /// **'Lapsed'**
  String get skillCoverageLapsed;

  /// No description provided for @skillCoverageShortfall.
  ///
  /// In en, this message translates to:
  /// **'Shortfall'**
  String get skillCoverageShortfall;

  /// No description provided for @skillCoverageSkillCoverageCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'Skill coverage could not be read'**
  String get skillCoverageSkillCoverageCouldNotBeRead;

  /// No description provided for @skillCoverageWhereThisSiteFallsShortOfIts.
  ///
  /// In en, this message translates to:
  /// **'Where this Site falls short of its own skill requirements.'**
  String get skillCoverageWhereThisSiteFallsShortOfIts;

  /// No description provided for @skillCoverageEveryRequirementIsMet.
  ///
  /// In en, this message translates to:
  /// **'Every requirement is met'**
  String get skillCoverageEveryRequirementIsMet;

  /// No description provided for @skillCoverageThisSiteHasNoShortfallAgainstThe.
  ///
  /// In en, this message translates to:
  /// **'This Site has no shortfall against the skill requirements it has set for itself.'**
  String get skillCoverageThisSiteHasNoShortfallAgainstThe;

  /// No description provided for @skillCoverageFilterSkillCoverage.
  ///
  /// In en, this message translates to:
  /// **'Filter skill coverage'**
  String get skillCoverageFilterSkillCoverage;

  /// No description provided for @skillCoverageByOrgUnitOrSkill.
  ///
  /// In en, this message translates to:
  /// **'By Org Unit or skill.'**
  String get skillCoverageByOrgUnitOrSkill;

  /// No description provided for @skillCoverageNoShortfallsMatch.
  ///
  /// In en, this message translates to:
  /// **'No shortfalls match'**
  String get skillCoverageNoShortfallsMatch;

  /// No description provided for @skillCoverageThisSiteIsShortSomewhereButNothing.
  ///
  /// In en, this message translates to:
  /// **'This Site is short somewhere, but nothing matches \"{term}\". Try a different Org Unit or skill, or clear the filter.'**
  String skillCoverageThisSiteIsShortSomewhereButNothing(Object term);

  /// The wide/table reading of one requirement: the headcount needed and the level they must hold. The narrow layout says the same record with its qualified and lapsed counts.
  ///
  /// In en, this message translates to:
  /// **'Needs {minimumQualifiedHeadcount} at level {minimumLevel}+'**
  String skillCoverageNeedsAtLevel(
    Object minimumQualifiedHeadcount,
    Object minimumLevel,
  );

  /// No description provided for @skillCoverageNeedsAtLevelQualifiedLapsed.
  ///
  /// In en, this message translates to:
  /// **'Needs {minimumQualifiedHeadcount} at level {minimumLevel}+, {qualifiedHeadcount} qualified, {expiredHeadcount} lapsed'**
  String skillCoverageNeedsAtLevelQualifiedLapsed(
    Object minimumQualifiedHeadcount,
    Object minimumLevel,
    Object qualifiedHeadcount,
    Object expiredHeadcount,
  );

  /// No description provided for @skillCoverageShort.
  ///
  /// In en, this message translates to:
  /// **'Short {shortfall}'**
  String skillCoverageShort(Object shortfall);

  /// No description provided for @skillFormCorrectSkill.
  ///
  /// In en, this message translates to:
  /// **'Correct skill'**
  String get skillFormCorrectSkill;

  /// No description provided for @commonAddSkill.
  ///
  /// In en, this message translates to:
  /// **'Add skill'**
  String get commonAddSkill;

  /// No description provided for @skillFormRequiresCertification.
  ///
  /// In en, this message translates to:
  /// **'Requires certification'**
  String get skillFormRequiresCertification;

  /// No description provided for @skillFormRevalidationPeriodInMonthsOptional.
  ///
  /// In en, this message translates to:
  /// **'Revalidation period, in months (optional)'**
  String get skillFormRevalidationPeriodInMonthsOptional;

  /// No description provided for @skillFormLeftBlankThisSkillNeverNeedsRevalidating.
  ///
  /// In en, this message translates to:
  /// **'Left blank, this skill never needs revalidating.'**
  String get skillFormLeftBlankThisSkillNeverNeedsRevalidating;

  /// No description provided for @skillQualifiedEmployeesWhoHolds.
  ///
  /// In en, this message translates to:
  /// **'Who holds {name}'**
  String skillQualifiedEmployeesWhoHolds(Object name);

  /// No description provided for @skillQualifiedEmployeesScopedTo.
  ///
  /// In en, this message translates to:
  /// **'Scoped to'**
  String get skillQualifiedEmployeesScopedTo;

  /// No description provided for @skillQualifiedEmployeesMinimumProficiency.
  ///
  /// In en, this message translates to:
  /// **'Minimum proficiency'**
  String get skillQualifiedEmployeesMinimumProficiency;

  /// No description provided for @skillQualifiedEmployeesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get skillQualifiedEmployeesSearch;

  /// No description provided for @skillQualifiedEmployeesChooseAnOrgUnitThenSearch.
  ///
  /// In en, this message translates to:
  /// **'Choose an Org Unit, then search.'**
  String get skillQualifiedEmployeesChooseAnOrgUnitThenSearch;

  /// No description provided for @skillQualifiedEmployeesNobodyCurrentlyQualifiesAtThisOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Nobody currently qualifies at this Org Unit.'**
  String get skillQualifiedEmployeesNobodyCurrentlyQualifiesAtThisOrgUnit;

  /// No description provided for @skillQualifiedEmployeesLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {proficiencyLevel}'**
  String skillQualifiedEmployeesLevel(Object proficiencyLevel);

  /// No description provided for @skillsTheSkillCatalogueCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The skill catalogue could not be read'**
  String get skillsTheSkillCatalogueCouldNotBeRead;

  /// No description provided for @skillsWhatThePlantQualifiesAnEmployeeTo.
  ///
  /// In en, this message translates to:
  /// **'What the plant qualifies an Employee to do — defined once, shared by every Site.'**
  String get skillsWhatThePlantQualifiesAnEmployeeTo;

  /// No description provided for @skillsNoSkillsYet.
  ///
  /// In en, this message translates to:
  /// **'No skills yet'**
  String get skillsNoSkillsYet;

  /// No description provided for @skillsFilterSkills.
  ///
  /// In en, this message translates to:
  /// **'Filter skills'**
  String get skillsFilterSkills;

  /// No description provided for @skillsByNameCodeOrCategory.
  ///
  /// In en, this message translates to:
  /// **'By name, code or category.'**
  String get skillsByNameCodeOrCategory;

  /// No description provided for @skillsNoSkillsMatch.
  ///
  /// In en, this message translates to:
  /// **'No skills match'**
  String get skillsNoSkillsMatch;

  /// No description provided for @skillsNothingInTheCatalogueMatchesTryA.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the catalogue matches \"{term}\". Try a different name, code or category, or clear the filter.'**
  String skillsNothingInTheCatalogueMatchesTryA(Object term);

  /// No description provided for @skillsWhoHoldsThis.
  ///
  /// In en, this message translates to:
  /// **'Who holds this'**
  String get skillsWhoHoldsThis;

  /// No description provided for @trainingAnswerSignYourConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Sign your confirmation'**
  String get trainingAnswerSignYourConfirmation;

  /// No description provided for @trainingAnswerChooseWhatYourAnswerIsSignedWith.
  ///
  /// In en, this message translates to:
  /// **'Choose what your answer is signed with. You can also confirm without a Signature.'**
  String get trainingAnswerChooseWhatYourAnswerIsSignedWith;

  /// No description provided for @trainingAnswerYouKeepNoSignatureDrawOneNow.
  ///
  /// In en, this message translates to:
  /// **'You keep no Signature. Draw one now for this answer, or confirm without a Signature.'**
  String get trainingAnswerYouKeepNoSignatureDrawOneNow;

  /// No description provided for @trainingAnswerYourSignatureWhichUseMySignatureApplies.
  ///
  /// In en, this message translates to:
  /// **'Your Signature, which \"Use my Signature\" applies:'**
  String get trainingAnswerYourSignatureWhichUseMySignatureApplies;

  /// No description provided for @trainingAnswerUseMySignature.
  ///
  /// In en, this message translates to:
  /// **'Use my Signature'**
  String get trainingAnswerUseMySignature;

  /// No description provided for @trainingAnswerDrawOneNow.
  ///
  /// In en, this message translates to:
  /// **'Draw one now'**
  String get trainingAnswerDrawOneNow;

  /// No description provided for @trainingAnswerNoSignature.
  ///
  /// In en, this message translates to:
  /// **'No Signature'**
  String get trainingAnswerNoSignature;

  /// No description provided for @trainingAnswerConfirmWithThisSignature.
  ///
  /// In en, this message translates to:
  /// **'Confirm with this Signature'**
  String get trainingAnswerConfirmWithThisSignature;

  /// No description provided for @commonNoSuchTrainingRecord.
  ///
  /// In en, this message translates to:
  /// **'No such Training record'**
  String get commonNoSuchTrainingRecord;

  /// No description provided for @commonBackToTrainingRecords.
  ///
  /// In en, this message translates to:
  /// **'Back to Training records'**
  String get commonBackToTrainingRecords;

  /// No description provided for @trainingDetailTheTrainingRecordCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Training record could not be read'**
  String get trainingDetailTheTrainingRecordCouldNotBeRead;

  /// No description provided for @trainingDetailTheForm.
  ///
  /// In en, this message translates to:
  /// **'The form'**
  String get trainingDetailTheForm;

  /// No description provided for @trainingDetailTheTraining.
  ///
  /// In en, this message translates to:
  /// **'The training'**
  String get trainingDetailTheTraining;

  /// No description provided for @commonTrainedOn.
  ///
  /// In en, this message translates to:
  /// **'Trained on'**
  String get commonTrainedOn;

  /// No description provided for @trainingDetailDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get trainingDetailDuration;

  /// No description provided for @trainingDetailTrainer.
  ///
  /// In en, this message translates to:
  /// **'Trainer'**
  String get trainingDetailTrainer;

  /// No description provided for @trainingDetailObjective.
  ///
  /// In en, this message translates to:
  /// **'Objective'**
  String get trainingDetailObjective;

  /// No description provided for @trainingDetailTrainees.
  ///
  /// In en, this message translates to:
  /// **'Trainees ({traineeCount})'**
  String trainingDetailTrainees(Object traineeCount);

  /// No description provided for @commonAddTrainee.
  ///
  /// In en, this message translates to:
  /// **'Add Trainee'**
  String get commonAddTrainee;

  /// No description provided for @trainingDetailNoTraineesAreOnThisTrainingRecord.
  ///
  /// In en, this message translates to:
  /// **'No Trainees are on this Training record yet.'**
  String get trainingDetailNoTraineesAreOnThisTrainingRecord;

  /// No description provided for @trainingDetailSendToTrainees.
  ///
  /// In en, this message translates to:
  /// **'Send to Trainees'**
  String get trainingDetailSendToTrainees;

  /// No description provided for @trainingDetailDiscardDraft.
  ///
  /// In en, this message translates to:
  /// **'Discard draft'**
  String get trainingDetailDiscardDraft;

  /// No description provided for @trainingDetailEvaluated.
  ///
  /// In en, this message translates to:
  /// **'Evaluated: {value}'**
  String trainingDetailEvaluated(Object value);

  /// No description provided for @trainingDetailRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove {employeeName}'**
  String trainingDetailRemove(Object employeeName);

  /// No description provided for @trainingDetailDiscardThisDraft.
  ///
  /// In en, this message translates to:
  /// **'Discard this draft?'**
  String get trainingDetailDiscardThisDraft;

  /// No description provided for @trainingDetailTheDraftAndTheTraineesListedOn.
  ///
  /// In en, this message translates to:
  /// **'The draft and the Trainees listed on it will be deleted, and it cannot be brought back. Nobody has been asked about it yet.'**
  String get trainingDetailTheDraftAndTheTraineesListedOn;

  /// No description provided for @trainingDetailDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get trainingDetailDiscard;

  /// No description provided for @commonEvaluation.
  ///
  /// In en, this message translates to:
  /// **'Evaluation'**
  String get commonEvaluation;

  /// No description provided for @trainingFormThatTrainingFormCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That training form could not be read'**
  String get trainingFormThatTrainingFormCouldNotBeRead;

  /// No description provided for @trainingFormTrainingRecord.
  ///
  /// In en, this message translates to:
  /// **'Training Record'**
  String get trainingFormTrainingRecord;

  /// No description provided for @trainingFormBiNBNGhiNhN.
  ///
  /// In en, this message translates to:
  /// **'Biên bản ghi nhận đào tạo'**
  String get trainingFormBiNBNGhiNhN;

  /// No description provided for @trainingFormAttendanceListDanhSChThamGia.
  ///
  /// In en, this message translates to:
  /// **'Attendance list/ danh sách tham gia :'**
  String get trainingFormAttendanceListDanhSChThamGia;

  /// No description provided for @trainingRaiseCorrectTrainingRecord.
  ///
  /// In en, this message translates to:
  /// **'Correct training record'**
  String get trainingRaiseCorrectTrainingRecord;

  /// No description provided for @commonRaiseTrainingRecord.
  ///
  /// In en, this message translates to:
  /// **'Raise training record'**
  String get commonRaiseTrainingRecord;

  /// No description provided for @trainingRaiseCorrecting.
  ///
  /// In en, this message translates to:
  /// **'Correcting…'**
  String get trainingRaiseCorrecting;

  /// No description provided for @trainingRaiseRaising.
  ///
  /// In en, this message translates to:
  /// **'Raising…'**
  String get trainingRaiseRaising;

  /// No description provided for @trainingRaiseTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get trainingRaiseTitle;

  /// No description provided for @trainingRaiseWhatTheTrainingWas.
  ///
  /// In en, this message translates to:
  /// **'What the training was.'**
  String get trainingRaiseWhatTheTrainingWas;

  /// No description provided for @trainingRaiseTheDayItWasGiven.
  ///
  /// In en, this message translates to:
  /// **'The day it was given.'**
  String get trainingRaiseTheDayItWasGiven;

  /// No description provided for @trainingRaiseDurationHours.
  ///
  /// In en, this message translates to:
  /// **'Duration (hours)'**
  String get trainingRaiseDurationHours;

  /// No description provided for @trainingRaiseHowLongItLastedEG1.
  ///
  /// In en, this message translates to:
  /// **'How long it lasted, e.g. 1.5.'**
  String get trainingRaiseHowLongItLastedEG1;

  /// No description provided for @trainingRaiseTrainerOptional.
  ///
  /// In en, this message translates to:
  /// **'Trainer (optional)'**
  String get trainingRaiseTrainerOptional;

  /// No description provided for @trainingRaiseWhoGaveItFoundInTheDirectory.
  ///
  /// In en, this message translates to:
  /// **'Who gave it, found in the Directory.'**
  String get trainingRaiseWhoGaveItFoundInTheDirectory;

  /// No description provided for @trainingRaiseObjectiveOptional.
  ///
  /// In en, this message translates to:
  /// **'Objective (optional)'**
  String get trainingRaiseObjectiveOptional;

  /// No description provided for @trainingRaiseWhatTheTrainingSetOutToTeach.
  ///
  /// In en, this message translates to:
  /// **'What the training set out to teach.'**
  String get trainingRaiseWhatTheTrainingSetOutToTeach;

  /// No description provided for @trainingRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get trainingRecord;

  /// No description provided for @trainingTrainees.
  ///
  /// In en, this message translates to:
  /// **'Trainees'**
  String get trainingTrainees;

  /// No description provided for @trainingAnswers.
  ///
  /// In en, this message translates to:
  /// **'Answers'**
  String get trainingAnswers;

  /// No description provided for @trainingTrainingRecordsCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'Training records could not be read'**
  String get trainingTrainingRecordsCouldNotBeRead;

  /// No description provided for @trainingNoTrainingRecordsMatch.
  ///
  /// In en, this message translates to:
  /// **'No Training records match'**
  String get trainingNoTrainingRecordsMatch;

  /// No description provided for @trainingNothingWasTrainedUnderThatOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Nothing was trained under that Org Unit in those days.'**
  String get trainingNothingWasTrainedUnderThatOrgUnit;

  /// No description provided for @trainingNoTrainingRecordsYet.
  ///
  /// In en, this message translates to:
  /// **'No Training records yet'**
  String get trainingNoTrainingRecordsYet;

  /// No description provided for @trainingRaiseATrainingRecordToStartThe.
  ///
  /// In en, this message translates to:
  /// **'Raise a Training record to start the register.'**
  String get trainingRaiseATrainingRecordToStartThe;

  /// No description provided for @trainingNothingHasBeenRecordedAsTrainedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recorded as trained yet.'**
  String get trainingNothingHasBeenRecordedAsTrainedYet;

  /// No description provided for @trainingWhatThePlantHasTrainedPeopleOn.
  ///
  /// In en, this message translates to:
  /// **'What the plant has trained people on, and when.'**
  String get trainingWhatThePlantHasTrainedPeopleOn;

  /// No description provided for @trainingThereAreMoreTrainingRecordsThanThis.
  ///
  /// In en, this message translates to:
  /// **'There are more Training records than this list shows. Narrow it by Org Unit or by dates to see the rest.'**
  String get trainingThereAreMoreTrainingRecordsThanThis;

  /// No description provided for @trainingTheFormFor.
  ///
  /// In en, this message translates to:
  /// **'The form for {number}'**
  String trainingTheFormFor(Object number);

  /// No description provided for @trainingToConfirmYourTrainingToConfirmCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'Your Training to confirm could not be read'**
  String get trainingToConfirmYourTrainingToConfirmCouldNotBe;

  /// No description provided for @trainingToConfirmNothingWaitingOnYou.
  ///
  /// In en, this message translates to:
  /// **'Nothing waiting on you'**
  String get trainingToConfirmNothingWaitingOnYou;

  /// No description provided for @trainingToConfirmNoTrainingRecordHasBeenSentTo.
  ///
  /// In en, this message translates to:
  /// **'No Training record has been sent to you that you have not answered.'**
  String get trainingToConfirmNoTrainingRecordHasBeenSentTo;

  /// No description provided for @trainingToConfirmTrainingRecordsSentToYouThatYou.
  ///
  /// In en, this message translates to:
  /// **'Training records sent to you that you have not answered yet, oldest first. Confirm that you attended, or decline because the record is wrong.'**
  String get trainingToConfirmTrainingRecordsSentToYouThatYou;

  /// No description provided for @trainingToConfirmYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get trainingToConfirmYourAnswer;

  /// No description provided for @trainingTraineeEmployeesOf.
  ///
  /// In en, this message translates to:
  /// **'Employees of {orgUnitName}'**
  String trainingTraineeEmployeesOf(Object orgUnitName);

  /// No description provided for @trainingTraineeWholeDirectory.
  ///
  /// In en, this message translates to:
  /// **'Whole Directory'**
  String get trainingTraineeWholeDirectory;

  /// No description provided for @trainingTraineeAnyoneInTheDirectoryFoundByName.
  ///
  /// In en, this message translates to:
  /// **'Anyone in the Directory, found by name or number.'**
  String get trainingTraineeAnyoneInTheDirectoryFoundByName;

  /// No description provided for @trainingTraineeAnEmployeeOfFoundByNameOr.
  ///
  /// In en, this message translates to:
  /// **'An Employee of {orgUnitName}, found by name or number.'**
  String trainingTraineeAnEmployeeOfFoundByNameOr(Object orgUnitName);

  /// No description provided for @workedHoursDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get workedHoursDay;

  /// No description provided for @workedHoursWorked.
  ///
  /// In en, this message translates to:
  /// **'Worked'**
  String get workedHoursWorked;

  /// No description provided for @workedHoursBackToEmployee.
  ///
  /// In en, this message translates to:
  /// **'Back to Employee'**
  String get workedHoursBackToEmployee;

  /// No description provided for @workedHoursTheConfirmedHoursThisEmployeeActuallyWorked.
  ///
  /// In en, this message translates to:
  /// **'The confirmed hours this Employee actually worked, day by day. Only confirmed attendance counts — an unconfirmed sheet is a draft.'**
  String get workedHoursTheConfirmedHoursThisEmployeeActuallyWorked;

  /// No description provided for @workedHoursTheWorkedHoursSummaryCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The worked-hours summary could not be read'**
  String get workedHoursTheWorkedHoursSummaryCouldNotBe;

  /// No description provided for @workedHoursNoConfirmedWorkedHoursInThisWindow.
  ///
  /// In en, this message translates to:
  /// **'No confirmed worked hours in this window.'**
  String get workedHoursNoConfirmedWorkedHoursInThisWindow;

  /// No description provided for @workedHoursWidenTheWindowOrConfirmTheShift.
  ///
  /// In en, this message translates to:
  /// **'Widen the window, or confirm the shift sheets for the days this Employee worked.'**
  String get workedHoursWidenTheWindowOrConfirmTheShift;

  /// No description provided for @workedHoursTotals.
  ///
  /// In en, this message translates to:
  /// **'Totals'**
  String get workedHoursTotals;

  /// No description provided for @workedHoursOfScheduled.
  ///
  /// In en, this message translates to:
  /// **'of {value} scheduled'**
  String workedHoursOfScheduled(Object value);

  /// No description provided for @leaveRequestDecisionApproveLeaveRequest.
  ///
  /// In en, this message translates to:
  /// **'Approve leave request'**
  String get leaveRequestDecisionApproveLeaveRequest;

  /// No description provided for @leaveRequestDecisionRejectLeaveRequest.
  ///
  /// In en, this message translates to:
  /// **'Reject leave request'**
  String get leaveRequestDecisionRejectLeaveRequest;

  /// No description provided for @commonTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get commonTo;

  /// No description provided for @commonEmployeeNumber.
  ///
  /// In en, this message translates to:
  /// **'Employee number'**
  String get commonEmployeeNumber;

  /// No description provided for @commonPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get commonPin;

  /// No description provided for @commonInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get commonInactive;

  /// No description provided for @commonDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get commonDeactivate;

  /// No description provided for @commonReactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get commonReactivate;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get commonReason;

  /// No description provided for @commonAssign.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get commonAssign;

  /// No description provided for @commonDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get commonDecline;

  /// No description provided for @commonOvertime.
  ///
  /// In en, this message translates to:
  /// **'Overtime'**
  String get commonOvertime;

  /// No description provided for @commonSessionEnded.
  ///
  /// In en, this message translates to:
  /// **'This session has ended. Sign in again to continue.'**
  String get commonSessionEnded;

  /// No description provided for @attendanceRecordChooseAReasonForThisAbsence.
  ///
  /// In en, this message translates to:
  /// **'Choose a reason for this absence.'**
  String get attendanceRecordChooseAReasonForThisAbsence;

  /// No description provided for @commonThatActionCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That Action could not be read'**
  String get commonThatActionCouldNotBeRead;

  /// No description provided for @commonThatActionHasEnded.
  ///
  /// In en, this message translates to:
  /// **'That Action has ended'**
  String get commonThatActionHasEnded;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get commonDone;

  /// No description provided for @actionCancelItIsClosedSoThereIsNothing.
  ///
  /// In en, this message translates to:
  /// **'It is closed, so there is nothing left to call off.'**
  String get actionCancelItIsClosedSoThereIsNothing;

  /// No description provided for @actionCancelItWasAlreadyCancelled.
  ///
  /// In en, this message translates to:
  /// **'It was already cancelled.'**
  String get actionCancelItWasAlreadyCancelled;

  /// No description provided for @actionCancelCallOff.
  ///
  /// In en, this message translates to:
  /// **'Call off {actionNo}?'**
  String actionCancelCallOff(Object actionNo);

  /// No description provided for @actionCancelLeaveItAlone.
  ///
  /// In en, this message translates to:
  /// **'Leave it alone'**
  String get actionCancelLeaveItAlone;

  /// No description provided for @actionCancelCallItOff.
  ///
  /// In en, this message translates to:
  /// **'Call it off'**
  String get actionCancelCallItOff;

  /// No description provided for @actionCancelCallingItOffEndsTheRecordWithout.
  ///
  /// In en, this message translates to:
  /// **'Calling it off ends the record without claiming anything was done about it. The row stays, with the reason you give it.'**
  String get actionCancelCallingItOffEndsTheRecordWithout;

  /// No description provided for @actionCancelWhyOptional.
  ///
  /// In en, this message translates to:
  /// **'Why (optional)'**
  String get actionCancelWhyOptional;

  /// No description provided for @actionCancelRaisedInErrorADuplicateOvertakenBy.
  ///
  /// In en, this message translates to:
  /// **'Raised in error, a duplicate, overtaken by events.'**
  String get actionCancelRaisedInErrorADuplicateOvertakenBy;

  /// No description provided for @commonBackToTheActionLog.
  ///
  /// In en, this message translates to:
  /// **'Back to the action log'**
  String get commonBackToTheActionLog;

  /// No description provided for @actionDetailHandItUp.
  ///
  /// In en, this message translates to:
  /// **'Hand it up…'**
  String get actionDetailHandItUp;

  /// No description provided for @actionDetailCallItOff.
  ///
  /// In en, this message translates to:
  /// **'Call it off…'**
  String get actionDetailCallItOff;

  /// No description provided for @actionDetailWhereItStands.
  ///
  /// In en, this message translates to:
  /// **'Where it stands'**
  String get actionDetailWhereItStands;

  /// No description provided for @commonOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get commonOwner;

  /// No description provided for @actionDetailEscalatedTo.
  ///
  /// In en, this message translates to:
  /// **'Escalated to'**
  String get actionDetailEscalatedTo;

  /// No description provided for @actionDetailClosingNote.
  ///
  /// In en, this message translates to:
  /// **'Closing note'**
  String get actionDetailClosingNote;

  /// No description provided for @actionDetailPillar.
  ///
  /// In en, this message translates to:
  /// **'Pillar {pillarCode}'**
  String actionDetailPillar(Object pillarCode);

  /// No description provided for @commonOverdueByDays.
  ///
  /// In en, this message translates to:
  /// **'Overdue by {daysOverdue} days'**
  String commonOverdueByDays(Object daysOverdue);

  /// No description provided for @actionDetailCycle.
  ///
  /// In en, this message translates to:
  /// **'Cycle {currentCycle}'**
  String actionDetailCycle(Object currentCycle);

  /// No description provided for @actionDetailCompleteThe.
  ///
  /// In en, this message translates to:
  /// **'Complete the {phaseLabel}'**
  String actionDetailCompleteThe(Object phaseLabel);

  /// No description provided for @actionDetailThisActionHasNoPhasesLeft.
  ///
  /// In en, this message translates to:
  /// **'This Action has no phases left.'**
  String get actionDetailThisActionHasNoPhasesLeft;

  /// No description provided for @actionDetailEarlierRounds.
  ///
  /// In en, this message translates to:
  /// **'Earlier rounds'**
  String get actionDetailEarlierRounds;

  /// No description provided for @actionDetailOpenWaitingOnThis.
  ///
  /// In en, this message translates to:
  /// **'Open — waiting on this'**
  String get actionDetailOpenWaitingOnThis;

  /// No description provided for @actionDetailNoNoteRecorded.
  ///
  /// In en, this message translates to:
  /// **'No note recorded'**
  String get actionDetailNoNoteRecorded;

  /// No description provided for @actionDetailDue.
  ///
  /// In en, this message translates to:
  /// **'due {dueDate}'**
  String actionDetailDue(Object dueDate);

  /// No description provided for @actionDetailDone.
  ///
  /// In en, this message translates to:
  /// **'done {value}'**
  String actionDetailDone(Object value);

  /// No description provided for @actionDetailAnswers.
  ///
  /// In en, this message translates to:
  /// **'Answers {actionNo}'**
  String actionDetailAnswers(Object actionNo);

  /// No description provided for @commonCapa.
  ///
  /// In en, this message translates to:
  /// **'CAPA'**
  String get commonCapa;

  /// No description provided for @actionDetailAFormal8dInvestigationOpenedOnThis.
  ///
  /// In en, this message translates to:
  /// **'A formal 8D investigation opened on this Concern: its team, its problem description and — as those slices land — its root causes and its effectiveness check. Its actions are the ones below, recorded once in the action log and read there.'**
  String get actionDetailAFormal8dInvestigationOpenedOnThis;

  /// No description provided for @actionDetailUnderInvestigation.
  ///
  /// In en, this message translates to:
  /// **'Under investigation: {capaNo}'**
  String actionDetailUnderInvestigation(Object capaNo);

  /// No description provided for @actionDetailOpenACapa.
  ///
  /// In en, this message translates to:
  /// **'Open a CAPA…'**
  String get actionDetailOpenACapa;

  /// No description provided for @actionDetailNobodyHasOpenedACapaOnThis.
  ///
  /// In en, this message translates to:
  /// **'Nobody has opened a CAPA on this Concern. Opening one needs Quality authority at this Concern\'s Org Unit.'**
  String get actionDetailNobodyHasOpenedACapaOnThis;

  /// No description provided for @actionDetailMeasures.
  ///
  /// In en, this message translates to:
  /// **'Measures'**
  String get actionDetailMeasures;

  /// No description provided for @actionDetailMeasuresOfThemCountermeasures.
  ///
  /// In en, this message translates to:
  /// **'Measures ({length}, {countermeasureCount} of them countermeasures)'**
  String actionDetailMeasuresOfThemCountermeasures(
    Object length,
    Object countermeasureCount,
  );

  /// No description provided for @actionDetailAddAMeasure.
  ///
  /// In en, this message translates to:
  /// **'Add a measure'**
  String get actionDetailAddAMeasure;

  /// No description provided for @actionDetailAddA.
  ///
  /// In en, this message translates to:
  /// **'Add a {value}…'**
  String actionDetailAddA(Object value);

  /// No description provided for @actionDetailEachMeasureIsAnActionOfIts.
  ///
  /// In en, this message translates to:
  /// **'Each measure is an Action of its own: open one and run its own cycle to its Act, and it counts as closed.'**
  String get actionDetailEachMeasureIsAnActionOfIts;

  /// No description provided for @actionDetailThisActionAnswersNoConcernOfIts.
  ///
  /// In en, this message translates to:
  /// **'This Action answers no Concern of its own.'**
  String get actionDetailThisActionAnswersNoConcernOfIts;

  /// No description provided for @actionDetailNothingAnswersThisYetAContainmentStops.
  ///
  /// In en, this message translates to:
  /// **'Nothing answers this yet. A containment stops the effect now; a countermeasure removes the cause.'**
  String get actionDetailNothingAnswersThisYetAContainmentStops;

  /// No description provided for @commonNobodyYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody yet'**
  String get commonNobodyYet;

  /// No description provided for @actionDetailOverdueByDays.
  ///
  /// In en, this message translates to:
  /// **'overdue by {daysOverdue} days'**
  String actionDetailOverdueByDays(Object daysOverdue);

  /// No description provided for @commonWaitingOnIts.
  ///
  /// In en, this message translates to:
  /// **'waiting on its {value}'**
  String commonWaitingOnIts(Object value);

  /// No description provided for @actionDetailCompleteThe2.
  ///
  /// In en, this message translates to:
  /// **'Complete the {value}…'**
  String actionDetailCompleteThe2(Object value);

  /// No description provided for @actionDetailNonConformances.
  ///
  /// In en, this message translates to:
  /// **'Non-conformances ({length})'**
  String actionDetailNonConformances(Object length);

  /// No description provided for @actionDetailTheOccurrencesThisConcernAnswersOneProblem.
  ///
  /// In en, this message translates to:
  /// **'The occurrences this Concern answers. One problem that shows up several times stays one Concern, so a further occurrence is linked here rather than raised as another.'**
  String get actionDetailTheOccurrencesThisConcernAnswersOneProblem;

  /// No description provided for @actionDetailNoNonConformanceIsLinkedToThis.
  ///
  /// In en, this message translates to:
  /// **'No Non-conformance is linked to this Concern.'**
  String get actionDetailNoNonConformanceIsLinkedToThis;

  /// No description provided for @actionDetailRaisedFromThis.
  ///
  /// In en, this message translates to:
  /// **'Raised from this'**
  String get actionDetailRaisedFromThis;

  /// No description provided for @actionDetailUnlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink…'**
  String get actionDetailUnlink;

  /// No description provided for @actionDetailTheObservationThisActionWasRaisedFrom.
  ///
  /// In en, this message translates to:
  /// **'The observation this Action was raised from — what was seen, and how bad it could have been.'**
  String get actionDetailTheObservationThisActionWasRaisedFrom;

  /// No description provided for @actionDetailTheIncidentThisConcernWasRaisedFrom.
  ///
  /// In en, this message translates to:
  /// **'The incident this Concern was raised from — its number and its severity, never who was hurt or their diagnosis.'**
  String get actionDetailTheIncidentThisConcernWasRaisedFrom;

  /// No description provided for @actionEscalateItIsClosedWhoeverNeededToKnow.
  ///
  /// In en, this message translates to:
  /// **'It is closed. Whoever needed to know about it was told before it was.'**
  String get actionEscalateItIsClosedWhoeverNeededToKnow;

  /// No description provided for @actionEscalateItWasCalledOffSoThereIs.
  ///
  /// In en, this message translates to:
  /// **'It was called off, so there is nothing to hand up.'**
  String get actionEscalateItWasCalledOffSoThereIs;

  /// No description provided for @actionEscalateNowhereToHandItUpTo.
  ///
  /// In en, this message translates to:
  /// **'Nowhere to hand it up to'**
  String get actionEscalateNowhereToHandItUpTo;

  /// No description provided for @actionEscalateThereIsNobodyAboveThis.
  ///
  /// In en, this message translates to:
  /// **'There is nobody above this'**
  String get actionEscalateThereIsNobodyAboveThis;

  /// No description provided for @actionEscalateSitsAtWhichIsAlreadyTheTop.
  ///
  /// In en, this message translates to:
  /// **'{actionNo} sits at {orgUnitName}, which is already the top of this Site. Nothing above it can be told.'**
  String actionEscalateSitsAtWhichIsAlreadyTheTop(
    Object actionNo,
    Object orgUnitName,
  );

  /// No description provided for @actionEscalateHandUp.
  ///
  /// In en, this message translates to:
  /// **'Hand {actionNo} up'**
  String actionEscalateHandUp(Object actionNo);

  /// No description provided for @actionEscalateHandItUp.
  ///
  /// In en, this message translates to:
  /// **'Hand it up'**
  String get actionEscalateHandItUp;

  /// No description provided for @actionEscalateRaisingThisTellsTheOrgUnitYou.
  ///
  /// In en, this message translates to:
  /// **'Raising this tells the Org Unit you choose. It stays where it is and keeps its owner and its cycle — this asks somebody above to know about it, not to take it over.'**
  String get actionEscalateRaisingThisTellsTheOrgUnitYou;

  /// No description provided for @actionEscalateNearestAboveIt.
  ///
  /// In en, this message translates to:
  /// **'{code} · nearest above it'**
  String actionEscalateNearestAboveIt(Object code);

  /// No description provided for @actionEscalatedToFilterFilterByWhatWasHandedUp.
  ///
  /// In en, this message translates to:
  /// **'Filter by what was handed up'**
  String get actionEscalatedToFilterFilterByWhatWasHandedUp;

  /// No description provided for @actionEscalatedToFilterAnyone.
  ///
  /// In en, this message translates to:
  /// **'Anyone'**
  String get actionEscalatedToFilterAnyone;

  /// No description provided for @actionEscalatedToFilterWhoseQueue.
  ///
  /// In en, this message translates to:
  /// **'Whose queue'**
  String get actionEscalatedToFilterWhoseQueue;

  /// No description provided for @actionEscalatedToFilterChooseTheOrgUnitThatConcernsWere.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit that concerns were handed up to — what is waiting on the area, not what sits at the line — or clear back to everything.'**
  String get actionEscalatedToFilterChooseTheOrgUnitThatConcernsWere;

  /// No description provided for @commonRaiseAConcern.
  ///
  /// In en, this message translates to:
  /// **'Raise a concern'**
  String get commonRaiseAConcern;

  /// No description provided for @actionFormRaiseIt.
  ///
  /// In en, this message translates to:
  /// **'Raise it'**
  String get actionFormRaiseIt;

  /// No description provided for @actionFormOneLineTheCauseGoesInThe.
  ///
  /// In en, this message translates to:
  /// **'One line. The cause goes in the Plan phase, not here.'**
  String get actionFormOneLineTheCauseGoesInThe;

  /// No description provided for @commonKindOfAction.
  ///
  /// In en, this message translates to:
  /// **'Kind of Action'**
  String get commonKindOfAction;

  /// No description provided for @actionFormThePillarCatalogueCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Pillar catalogue could not be read, so no Pillar can be chosen.'**
  String get actionFormThePillarCatalogueCouldNotBeRead;

  /// No description provided for @actionFormPillarOptional.
  ///
  /// In en, this message translates to:
  /// **'Pillar (optional)'**
  String get actionFormPillarOptional;

  /// No description provided for @actionFormWhichSqdcpNumberDoesThisThreaten.
  ///
  /// In en, this message translates to:
  /// **'Which SQDCP number does this threaten?'**
  String get actionFormWhichSqdcpNumberDoesThisThreaten;

  /// No description provided for @actionFormNoPillar.
  ///
  /// In en, this message translates to:
  /// **'No Pillar'**
  String get actionFormNoPillar;

  /// No description provided for @commonOwnerOptional.
  ///
  /// In en, this message translates to:
  /// **'Owner (optional)'**
  String get commonOwnerOptional;

  /// No description provided for @actionFormWhoWillDoItAnActionNobody.
  ///
  /// In en, this message translates to:
  /// **'Who will do it. An Action nobody owns is visibly nobody\'s.'**
  String get actionFormWhoWillDoItAnActionNobody;

  /// No description provided for @commonDueOptional.
  ///
  /// In en, this message translates to:
  /// **'Due (optional)'**
  String get commonDueOptional;

  /// No description provided for @actionFormChooseTheOrgUnitThisConcernIs.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit this concern is about. This is what decides who may act on it.'**
  String get actionFormChooseTheOrgUnitThisConcernIs;

  /// No description provided for @actionFormThisConcernWillBeRecordedAt.
  ///
  /// In en, this message translates to:
  /// **'This concern will be recorded at {value}.'**
  String actionFormThisConcernWillBeRecordedAt(Object value);

  /// No description provided for @actionMeasureAddA.
  ///
  /// In en, this message translates to:
  /// **'Add a {value}'**
  String actionMeasureAddA(Object value);

  /// No description provided for @actionMeasureAddThe.
  ///
  /// In en, this message translates to:
  /// **'Add the {value}'**
  String actionMeasureAddThe(Object value);

  /// No description provided for @actionMeasureAnswering.
  ///
  /// In en, this message translates to:
  /// **'Answering {actionNo}: {title}'**
  String actionMeasureAnswering(Object actionNo, Object title);

  /// No description provided for @actionMeasureWhatWillBeDone.
  ///
  /// In en, this message translates to:
  /// **'What will be done'**
  String get actionMeasureWhatWillBeDone;

  /// No description provided for @actionMeasureWhoWillDoIt.
  ///
  /// In en, this message translates to:
  /// **'Who will do it.'**
  String get actionMeasureWhoWillDoIt;

  /// No description provided for @actionMeasureWhereThisWorkHappens.
  ///
  /// In en, this message translates to:
  /// **'Where this work happens'**
  String get actionMeasureWhereThisWorkHappens;

  /// No description provided for @actionMeasureLeaveItAloneToRecordTheMeasure.
  ///
  /// In en, this message translates to:
  /// **'Leave it alone to record the measure at {orgUnitName}, where the concern sits. A fix that belongs somewhere else — a store, a supplier — can name that instead.'**
  String actionMeasureLeaveItAloneToRecordTheMeasure(Object orgUnitName);

  /// No description provided for @actionOrgUnitFilterNarrowTheLog.
  ///
  /// In en, this message translates to:
  /// **'Narrow the log'**
  String get actionOrgUnitFilterNarrowTheLog;

  /// No description provided for @actionOrgUnitFilterChooseTheOrgUnitWhoseActionsAnd.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit whose Actions and everything beneath it you want to read, or clear back to the whole Site.'**
  String get actionOrgUnitFilterChooseTheOrgUnitWhoseActionsAnd;

  /// No description provided for @actionPhaseCompleteThatIsNotTheOpenPhase.
  ///
  /// In en, this message translates to:
  /// **'That is not the open phase'**
  String get actionPhaseCompleteThatIsNotTheOpenPhase;

  /// No description provided for @actionPhaseCompleteThisActionHasNoOpenPhaseLeft.
  ///
  /// In en, this message translates to:
  /// **'This Action has no open phase left.'**
  String get actionPhaseCompleteThisActionHasNoOpenPhaseLeft;

  /// No description provided for @actionPhaseCompleteThisActionIsWaitingOnItsPhase.
  ///
  /// In en, this message translates to:
  /// **'This Action is waiting on its {value} phase, not its {value2}.'**
  String actionPhaseCompleteThisActionIsWaitingOnItsPhase(
    Object value,
    Object value2,
  );

  /// What the complete-the-Plan dialog says about the note it asks for.
  ///
  /// In en, this message translates to:
  /// **'What will be different, and how you will know. The target belongs here, in the plant\'s own words.'**
  String get actionPhaseCompletePlanProse;

  /// What the complete-the-Do dialog says about the note it asks for.
  ///
  /// In en, this message translates to:
  /// **'What was actually done.'**
  String get actionPhaseCompleteDoProse;

  /// What the complete-the-Check dialog says about the note it asks for.
  ///
  /// In en, this message translates to:
  /// **'What was measured, against what the Plan named.'**
  String get actionPhaseCompleteCheckProse;

  /// What the complete-the-Act dialog says about the note it asks for.
  ///
  /// In en, this message translates to:
  /// **'Which standard now holds it, so the fix outlives the person who made it.'**
  String get actionPhaseCompleteActProse;

  /// No description provided for @actionPhaseCompleteCompleteThe.
  ///
  /// In en, this message translates to:
  /// **'Complete the {label}'**
  String actionPhaseCompleteCompleteThe(Object label);

  /// No description provided for @actionPhaseCompleteWhatWasMeasured.
  ///
  /// In en, this message translates to:
  /// **'What was measured'**
  String get actionPhaseCompleteWhatWasMeasured;

  /// No description provided for @actionPhaseCompleteWhatWasDone.
  ///
  /// In en, this message translates to:
  /// **'What was done'**
  String get actionPhaseCompleteWhatWasDone;

  /// No description provided for @actionPhaseCompleteDidItHold.
  ///
  /// In en, this message translates to:
  /// **'Did it hold?'**
  String get actionPhaseCompleteDidItHold;

  /// No description provided for @actionPhaseCompleteAnsweringThatItDidNotOpensThe.
  ///
  /// In en, this message translates to:
  /// **'Answering that it did not opens the next cycle rather than closing the Action, and keeps this round on the record.'**
  String get actionPhaseCompleteAnsweringThatItDidNotOpensThe;

  /// No description provided for @actionUnlinkNonconformanceThatConcernCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That Concern could not be read'**
  String get actionUnlinkNonconformanceThatConcernCouldNotBeRead;

  /// No description provided for @actionUnlinkNonconformanceThatNonConformanceIsNotLinkedHere.
  ///
  /// In en, this message translates to:
  /// **'That Non-conformance is not linked here'**
  String get actionUnlinkNonconformanceThatNonConformanceIsNotLinkedHere;

  /// No description provided for @actionUnlinkNonconformanceThisConcernAnswersNothingByThatId.
  ///
  /// In en, this message translates to:
  /// **'This Concern answers nothing by that id. It may have been unlinked already, or the address may be wrong.'**
  String get actionUnlinkNonconformanceThisConcernAnswersNothingByThatId;

  /// No description provided for @actionUnlinkNonconformanceBackToTheConcern.
  ///
  /// In en, this message translates to:
  /// **'Back to the Concern'**
  String get actionUnlinkNonconformanceBackToTheConcern;

  /// No description provided for @actionUnlinkNonconformanceUnlinkThisNonConformance.
  ///
  /// In en, this message translates to:
  /// **'Unlink this Non-conformance'**
  String get actionUnlinkNonconformanceUnlinkThisNonConformance;

  /// No description provided for @actionUnlinkNonconformanceKeepItLinked.
  ///
  /// In en, this message translates to:
  /// **'Keep it linked'**
  String get actionUnlinkNonconformanceKeepItLinked;

  /// No description provided for @actionUnlinkNonconformanceUnlinkIt.
  ///
  /// In en, this message translates to:
  /// **'Unlink it'**
  String get actionUnlinkNonconformanceUnlinkIt;

  /// No description provided for @actionUnlinkNonconformanceItStopsBeingOneOfTheOccurrences.
  ///
  /// In en, this message translates to:
  /// **'It stops being one of the occurrences this Concern answers. The Non-conformance itself is untouched — it keeps its number, its Dispositions and its quantity.'**
  String get actionUnlinkNonconformanceItStopsBeingOneOfTheOccurrences;

  /// No description provided for @actionsTheActionLogCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The action log could not be read'**
  String get actionsTheActionLogCouldNotBeRead;

  /// No description provided for @actionsWhatThePlantOwesAtThisSite.
  ///
  /// In en, this message translates to:
  /// **'What the plant owes at this Site: what was found, who owns it, and when it is due. Overdue first.'**
  String get actionsWhatThePlantOwesAtThisSite;

  /// No description provided for @actionsEscalatedToAnyone.
  ///
  /// In en, this message translates to:
  /// **'Escalated to anyone'**
  String get actionsEscalatedToAnyone;

  /// No description provided for @actionsEscalatedTo.
  ///
  /// In en, this message translates to:
  /// **'Escalated to {escalatedToOrgUnitFilterName}'**
  String actionsEscalatedTo(Object escalatedToOrgUnitFilterName);

  /// No description provided for @actionsEveryKind.
  ///
  /// In en, this message translates to:
  /// **'Every kind'**
  String get actionsEveryKind;

  /// No description provided for @actionsShowClosed.
  ///
  /// In en, this message translates to:
  /// **'Show closed'**
  String get actionsShowClosed;

  /// No description provided for @actionsThereAreMoreActionsThanThisList.
  ///
  /// In en, this message translates to:
  /// **'There are more Actions than this list shows. Narrow it by Org Unit, by status or by kind to see the rest.'**
  String get actionsThereAreMoreActionsThanThisList;

  /// No description provided for @actionsTheLogHasActionsButNoneOf.
  ///
  /// In en, this message translates to:
  /// **'The log has Actions, but none of them is in the Org Unit, status or kind you picked.'**
  String get actionsTheLogHasActionsButNoneOf;

  /// No description provided for @actionsNothingOnTheLog.
  ///
  /// In en, this message translates to:
  /// **'Nothing on the log'**
  String get actionsNothingOnTheLog;

  /// No description provided for @actionsNoActionHasBeenRaisedAtThis.
  ///
  /// In en, this message translates to:
  /// **'No Action has been raised at this Site yet.'**
  String get actionsNoActionHasBeenRaisedAtThis;

  /// The Source column of an Action raised on the log itself, from no other record.
  ///
  /// In en, this message translates to:
  /// **'Raised here'**
  String get actionsSourceRaisedHere;

  /// No description provided for @actionsSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get actionsSource;

  /// No description provided for @actionsOfThemCountermeasures.
  ///
  /// In en, this message translates to:
  /// **'{measureCount, plural, =1{1 measure} other{{measureCount} measures}}, {countermeasureCount} of them countermeasures'**
  String actionsOfThemCountermeasures(
    int measureCount,
    int countermeasureCount,
  );

  /// No description provided for @actionsEscalatedTo2.
  ///
  /// In en, this message translates to:
  /// **'Escalated to {escalatedToOrgUnitName}'**
  String actionsEscalatedTo2(Object escalatedToOrgUnitName);

  /// No description provided for @actionsNoDueDate.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get actionsNoDueDate;

  /// No description provided for @actionsDue.
  ///
  /// In en, this message translates to:
  /// **'Due {dueDate}'**
  String actionsDue(Object dueDate);

  /// No description provided for @commonBackToTheCapa.
  ///
  /// In en, this message translates to:
  /// **'Back to the CAPA'**
  String get commonBackToTheCapa;

  /// No description provided for @commonThatCapaCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That CAPA could not be read'**
  String get commonThatCapaCouldNotBeRead;

  /// No description provided for @capaCauseThatIsNotA6mCategory.
  ///
  /// In en, this message translates to:
  /// **'That is not a 6M category'**
  String get capaCauseThatIsNotA6mCategory;

  /// No description provided for @capaCauseAFishboneHasSixBonesManMachine.
  ///
  /// In en, this message translates to:
  /// **'A fishbone has six bones: Man, Machine, Method, Material, Measurement and Environment.'**
  String get capaCauseAFishboneHasSixBonesManMachine;

  /// No description provided for @commonThisInvestigationIsOver.
  ///
  /// In en, this message translates to:
  /// **'This investigation is over'**
  String get commonThisInvestigationIsOver;

  /// No description provided for @capaCauseIsSoItsFishboneIsARecord.
  ///
  /// In en, this message translates to:
  /// **'{capaNo} is {value}, so its fishbone is a record rather than a worklist.'**
  String capaCauseIsSoItsFishboneIsARecord(Object capaNo, Object value);

  /// No description provided for @commonNotYoursToWrite.
  ///
  /// In en, this message translates to:
  /// **'Not yours to write'**
  String get commonNotYoursToWrite;

  /// No description provided for @commonWritingACapaSRootCausesNeeds.
  ///
  /// In en, this message translates to:
  /// **'Writing a CAPA\'s root causes needs edit access at its Org Unit, or a place on its team.'**
  String get commonWritingACapaSRootCausesNeeds;

  /// No description provided for @capaCauseThatCauseIsNotOnThisBone.
  ///
  /// In en, this message translates to:
  /// **'That cause is not on this bone'**
  String get capaCauseThatCauseIsNotOnThisBone;

  /// No description provided for @commonItMayHaveBeenRemovedAMoment.
  ///
  /// In en, this message translates to:
  /// **'It may have been removed a moment ago by somebody else.'**
  String get commonItMayHaveBeenRemovedAMoment;

  /// What the record-a-candidate-cause form says under its title, naming the branch the cause is filed under.
  ///
  /// In en, this message translates to:
  /// **'{categoryLabel} — something that could be behind the problem.'**
  String capaCauseSomethingThatCouldBeBehind(Object categoryLabel);

  /// The submit label of the record-a-candidate-cause form.
  ///
  /// In en, this message translates to:
  /// **'Record it'**
  String get capaCauseRecordIt;

  /// What the revise-a-cause form says under its title.
  ///
  /// In en, this message translates to:
  /// **'What it says, and which of the six it is filed under.'**
  String get capaCauseWhatItSaysAndWhichOfTheSix;

  /// The submit label of the revise-a-cause form.
  ///
  /// In en, this message translates to:
  /// **'Save it'**
  String get capaCauseSaveIt;

  /// No description provided for @capaCauseRecordACandidateCause.
  ///
  /// In en, this message translates to:
  /// **'Record a candidate cause'**
  String get capaCauseRecordACandidateCause;

  /// No description provided for @capaCauseReviseTheCause.
  ///
  /// In en, this message translates to:
  /// **'Revise the cause'**
  String get capaCauseReviseTheCause;

  /// No description provided for @capaCauseRemoveThisCause.
  ///
  /// In en, this message translates to:
  /// **'Remove this cause?'**
  String get capaCauseRemoveThisCause;

  /// No description provided for @commonRemoveIt.
  ///
  /// In en, this message translates to:
  /// **'Remove it'**
  String get commonRemoveIt;

  /// No description provided for @capaCauseItIsTakenOffTheBoneFor.
  ///
  /// In en, this message translates to:
  /// **'It is taken off the {categoryLabel} bone for good{value}. A chain started from it keeps the Why it began with.'**
  String capaCauseItIsTakenOffTheBoneFor(Object categoryLabel, Object value);

  /// No description provided for @capaCauseBothChainsHaveBeenStarted.
  ///
  /// In en, this message translates to:
  /// **'Both chains have been started'**
  String get capaCauseBothChainsHaveBeenStarted;

  /// No description provided for @capaCauseAlreadyReasonsBothWhyTheProblemHappened.
  ///
  /// In en, this message translates to:
  /// **'{capaNo} already reasons both why the problem happened and why it was not detected, so the Why for this cause belongs in one of them rather than at the head of a chain.'**
  String capaCauseAlreadyReasonsBothWhyTheProblemHappened(Object capaNo);

  /// No description provided for @capaCauseTheBoneItHangsFrom.
  ///
  /// In en, this message translates to:
  /// **'The bone it hangs from'**
  String get capaCauseTheBoneItHangsFrom;

  /// No description provided for @capaCauseTheCandidateCause.
  ///
  /// In en, this message translates to:
  /// **'The candidate cause'**
  String get capaCauseTheCandidateCause;

  /// No description provided for @capaCauseWhatYouSuspectSaidSoTheNext.
  ///
  /// In en, this message translates to:
  /// **'What you suspect, said so the next person can check it.'**
  String get capaCauseWhatYouSuspectSaidSoTheNext;

  /// No description provided for @capaCauseDecideThisCause.
  ///
  /// In en, this message translates to:
  /// **'Decide this cause'**
  String get capaCauseDecideThisCause;

  /// No description provided for @capaCauseRecordTheVerdict.
  ///
  /// In en, this message translates to:
  /// **'Record the verdict'**
  String get capaCauseRecordTheVerdict;

  /// No description provided for @capaCauseAVerdictIsADecisionTheReport.
  ///
  /// In en, this message translates to:
  /// **'A verdict is a decision the report reads back, so it is recorded with the evidence for it.'**
  String get capaCauseAVerdictIsADecisionTheReport;

  /// No description provided for @capaCauseTheEvidence.
  ///
  /// In en, this message translates to:
  /// **'The evidence'**
  String get capaCauseTheEvidence;

  /// No description provided for @capaCauseWhatYouLookedAtAndWhatIt.
  ///
  /// In en, this message translates to:
  /// **'What you looked at, and what it showed.'**
  String get capaCauseWhatYouLookedAtAndWhatIt;

  /// No description provided for @capaCauseStartAChainFromThisCause.
  ///
  /// In en, this message translates to:
  /// **'Start a chain from this cause'**
  String get capaCauseStartAChainFromThisCause;

  /// No description provided for @capaCauseStartTheChain.
  ///
  /// In en, this message translates to:
  /// **'Start the chain'**
  String get capaCauseStartTheChain;

  /// No description provided for @capaCauseTheEvidenceConfirmedThisCauseSoA.
  ///
  /// In en, this message translates to:
  /// **'The evidence confirmed this cause, so a chain may begin with it. What it says is the first Why.'**
  String get capaCauseTheEvidenceConfirmedThisCauseSoA;

  /// No description provided for @capaCauseWhichChainItBegins.
  ///
  /// In en, this message translates to:
  /// **'Which chain it begins'**
  String get capaCauseWhichChainItBegins;

  /// No description provided for @capaCauseTheFirstWhy.
  ///
  /// In en, this message translates to:
  /// **'The first Why'**
  String get capaCauseTheFirstWhy;

  /// No description provided for @capaCauseTheConfirmedCauseSaidTheWayThe.
  ///
  /// In en, this message translates to:
  /// **'The confirmed cause, said the way the chain should read.'**
  String get capaCauseTheConfirmedCauseSaidTheWayThe;

  /// No description provided for @capaDetailBackTo.
  ///
  /// In en, this message translates to:
  /// **'Back to {actionNo}'**
  String capaDetailBackTo(Object actionNo);

  /// No description provided for @capaDetailTheReport.
  ///
  /// In en, this message translates to:
  /// **'The report'**
  String get capaDetailTheReport;

  /// No description provided for @capaDetailInvestigation.
  ///
  /// In en, this message translates to:
  /// **'{methodLabel} investigation'**
  String capaDetailInvestigation(Object methodLabel);

  /// No description provided for @capaDetailDue.
  ///
  /// In en, this message translates to:
  /// **'due {dueDate}'**
  String capaDetailDue(Object dueDate);

  /// No description provided for @capaDetailEffectiveness.
  ///
  /// In en, this message translates to:
  /// **'Effectiveness'**
  String get capaDetailEffectiveness;

  /// No description provided for @commonACapaClosesOnlyWhenBothChains.
  ///
  /// In en, this message translates to:
  /// **'A CAPA closes only when both chains have a confirmed root cause, its Concern is closed, and somebody holding Quality authority other than its team lead has verified, some time later, that the problem has not come back.'**
  String get commonACapaClosesOnlyWhenBothChains;

  /// No description provided for @capaDetailRecordedByOn.
  ///
  /// In en, this message translates to:
  /// **'recorded by {value} on {value2}'**
  String capaDetailRecordedByOn(Object value, Object value2);

  /// No description provided for @capaDetailTheCheckDidNotHoldSoThe.
  ///
  /// In en, this message translates to:
  /// **'The check did not hold, so the Concern is open again in its next cycle: the work is on its Screen, in the Concern this investigation answers.'**
  String get capaDetailTheCheckDidNotHoldSoThe;

  /// No description provided for @commonTheConcernHasClosedSoTheEffectiveness.
  ///
  /// In en, this message translates to:
  /// **'The Concern has closed, so the effectiveness check is due on {dueAt}.'**
  String commonTheConcernHasClosedSoTheEffectiveness(Object dueAt);

  /// No description provided for @commonOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get commonOverdue;

  /// No description provided for @commonRecordTheEffectivenessCheck.
  ///
  /// In en, this message translates to:
  /// **'Record the effectiveness check'**
  String get commonRecordTheEffectivenessCheck;

  /// No description provided for @capaDetailYouLeadThisInvestigationSoSomebodyElse.
  ///
  /// In en, this message translates to:
  /// **'You lead this investigation, so somebody else records the check: a holder of Quality authority who is not on the team lead\'s Account.'**
  String get capaDetailYouLeadThisInvestigationSoSomebodyElse;

  /// No description provided for @capaDetailRecordingTheCheckNeedsQualityAuthorityAt.
  ///
  /// In en, this message translates to:
  /// **'Recording the check needs Quality authority at this Org Unit.'**
  String get capaDetailRecordingTheCheckNeedsQualityAuthorityAt;

  /// No description provided for @capaDetailTheCheckFallsDueDaysAfterThe.
  ///
  /// In en, this message translates to:
  /// **'The check falls due {effectivenessCheckDelayDays} days after the Concern closes, and the Concern has not closed yet.'**
  String capaDetailTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  );

  /// No description provided for @capaDetailTeam.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get capaDetailTeam;

  /// No description provided for @commonNobodyIsOnThisInvestigationYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody is on this investigation yet.'**
  String get commonNobodyIsOnThisInvestigationYet;

  /// No description provided for @commonTeamLead.
  ///
  /// In en, this message translates to:
  /// **'{name} · team lead'**
  String commonTeamLead(Object name);

  /// No description provided for @capaDetailTheProblem.
  ///
  /// In en, this message translates to:
  /// **'The problem'**
  String get capaDetailTheProblem;

  /// No description provided for @commonNobodyHasWrittenTheProblemDescriptionYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody has written the problem description yet.'**
  String get commonNobodyHasWrittenTheProblemDescriptionYet;

  /// No description provided for @capaDetailCandidateCauses.
  ///
  /// In en, this message translates to:
  /// **'Candidate causes'**
  String get capaDetailCandidateCauses;

  /// No description provided for @capaDetailTheFishboneWhatTheTeamSuspectedBy.
  ///
  /// In en, this message translates to:
  /// **'The fishbone: what the team suspected, by 6M category, and what the evidence said about each one. The chain that follows begins with the cause it confirmed.'**
  String get capaDetailTheFishboneWhatTheTeamSuspectedBy;

  /// No description provided for @capaDetailThisInvestigationIsOverSoItsFishbone.
  ///
  /// In en, this message translates to:
  /// **'This investigation is over, so its fishbone is a record rather than a worklist.'**
  String get capaDetailThisInvestigationIsOverSoItsFishbone;

  /// No description provided for @capaDetailRecordACause.
  ///
  /// In en, this message translates to:
  /// **'Record a cause'**
  String get capaDetailRecordACause;

  /// No description provided for @capaDetailNothingIsRecordedUnder.
  ///
  /// In en, this message translates to:
  /// **'Nothing is recorded under {value}.'**
  String capaDetailNothingIsRecordedUnder(Object value);

  /// No description provided for @capaDetailCause.
  ///
  /// In en, this message translates to:
  /// **'Cause {sequence}'**
  String capaDetailCause(Object sequence);

  /// No description provided for @commonEvidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence: {evidenceNote}'**
  String commonEvidence(Object evidenceNote);

  /// No description provided for @capaDetailChangeTheVerdict.
  ///
  /// In en, this message translates to:
  /// **'Change the verdict'**
  String get capaDetailChangeTheVerdict;

  /// No description provided for @capaDetailDecideIt.
  ///
  /// In en, this message translates to:
  /// **'Decide it'**
  String get capaDetailDecideIt;

  /// No description provided for @capaDetailStartAChainFromIt.
  ///
  /// In en, this message translates to:
  /// **'Start a chain from it'**
  String get capaDetailStartAChainFromIt;

  /// No description provided for @capaDetailRootCause.
  ///
  /// In en, this message translates to:
  /// **'Root cause'**
  String get capaDetailRootCause;

  /// No description provided for @capaDetailTwoChainsEachEndingAtOneConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Two chains, each ending at one confirmed root cause: why the problem happened, and why it was not detected.'**
  String get capaDetailTwoChainsEachEndingAtOneConfirmed;

  /// No description provided for @capaDetailThisInvestigationIsOverSoItsChains.
  ///
  /// In en, this message translates to:
  /// **'This investigation is over, so its chains are a record rather than a worklist.'**
  String get capaDetailThisInvestigationIsOverSoItsChains;

  /// No description provided for @commonAddAWhy.
  ///
  /// In en, this message translates to:
  /// **'Add a Why'**
  String get commonAddAWhy;

  /// No description provided for @capaDetailWhyTheProblemHappenedOneStepAt.
  ///
  /// In en, this message translates to:
  /// **'Why the problem happened, one step at a time.'**
  String get capaDetailWhyTheProblemHappenedOneStepAt;

  /// No description provided for @capaDetailWhyItWasNotDetectedOneStep.
  ///
  /// In en, this message translates to:
  /// **'Why it was not detected, one step at a time.'**
  String get capaDetailWhyItWasNotDetectedOneStep;

  /// No description provided for @commonNobodyHasStartedThisChainYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody has started this chain yet.'**
  String get commonNobodyHasStartedThisChainYet;

  /// No description provided for @commonThisChainHasNoConfirmedRootCause.
  ///
  /// In en, this message translates to:
  /// **'This chain has no confirmed root cause yet.'**
  String get commonThisChainHasNoConfirmedRootCause;

  /// No description provided for @commonConfirmedRootCause.
  ///
  /// In en, this message translates to:
  /// **'Confirmed root cause: {statement}'**
  String commonConfirmedRootCause(Object statement);

  /// No description provided for @capaDetailWhy.
  ///
  /// In en, this message translates to:
  /// **'Why {sequence}'**
  String capaDetailWhy(Object sequence);

  /// No description provided for @capaDetailConfirmedRootCause.
  ///
  /// In en, this message translates to:
  /// **'Confirmed root cause'**
  String get capaDetailConfirmedRootCause;

  /// No description provided for @capaDetailClearTheRootCause.
  ///
  /// In en, this message translates to:
  /// **'Clear the root cause'**
  String get capaDetailClearTheRootCause;

  /// No description provided for @capaDetailThisIsTheRootCause.
  ///
  /// In en, this message translates to:
  /// **'This is the root cause'**
  String get capaDetailThisIsTheRootCause;

  /// No description provided for @capaDetailMoveItEarlierInTheChain.
  ///
  /// In en, this message translates to:
  /// **'Move it earlier in the chain'**
  String get capaDetailMoveItEarlierInTheChain;

  /// No description provided for @capaDetailMoveItLaterInTheChain.
  ///
  /// In en, this message translates to:
  /// **'Move it later in the chain'**
  String get capaDetailMoveItLaterInTheChain;

  /// No description provided for @capaDetailTheConcern.
  ///
  /// In en, this message translates to:
  /// **'The Concern'**
  String get capaDetailTheConcern;

  /// No description provided for @capaDetailTheConcern2.
  ///
  /// In en, this message translates to:
  /// **'The Concern: {actionNo}'**
  String capaDetailTheConcern2(Object actionNo);

  /// No description provided for @capaDetailWhatTheConcernHasDone.
  ///
  /// In en, this message translates to:
  /// **'What the Concern has done'**
  String get capaDetailWhatTheConcernHasDone;

  /// No description provided for @capaDetailWhatTheConcernHasDone2.
  ///
  /// In en, this message translates to:
  /// **'What the Concern has done ({length})'**
  String capaDetailWhatTheConcernHasDone2(Object length);

  /// No description provided for @capaDetailTheContainmentD3TheCountermeasuresD5D6.
  ///
  /// In en, this message translates to:
  /// **'The containment (D3), the countermeasures (D5-D6) and the preventive actions (D7) are the Concern\'s own, recorded once in the action log — this is where they are read, not where they are recorded again.'**
  String get capaDetailTheContainmentD3TheCountermeasuresD5D6;

  /// No description provided for @capaDetailNothingAnswersThisConcernYetSoThere.
  ///
  /// In en, this message translates to:
  /// **'Nothing answers this Concern yet, so there is no work to show.'**
  String get capaDetailNothingAnswersThisConcernYetSoThere;

  /// No description provided for @commonCycle.
  ///
  /// In en, this message translates to:
  /// **'Cycle {cycle} · {phaseLabel}'**
  String commonCycle(Object cycle, Object phaseLabel);

  /// No description provided for @commonOpen2.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get commonOpen2;

  /// No description provided for @capaEffectivenessIsSoItsEffectivenessIsRecordedAnd.
  ///
  /// In en, this message translates to:
  /// **'{capaNo} is {value}, so its effectiveness is recorded and the record is read rather than changed.'**
  String capaEffectivenessIsSoItsEffectivenessIsRecordedAnd(
    Object capaNo,
    Object value,
  );

  /// No description provided for @capaEffectivenessNotYoursToDecide.
  ///
  /// In en, this message translates to:
  /// **'Not yours to decide'**
  String get capaEffectivenessNotYoursToDecide;

  /// No description provided for @capaEffectivenessRecordingACapaSEffectivenessCheckNeeds.
  ///
  /// In en, this message translates to:
  /// **'Recording a CAPA\'s effectiveness check needs Quality authority at its Org Unit.'**
  String get capaEffectivenessRecordingACapaSEffectivenessCheckNeeds;

  /// No description provided for @capaEffectivenessSomebodyElseHasToCheckThis.
  ///
  /// In en, this message translates to:
  /// **'Somebody else has to check this'**
  String get capaEffectivenessSomebodyElseHasToCheckThis;

  /// No description provided for @capaEffectivenessYouLeadTheInvestigationOnSoYou.
  ///
  /// In en, this message translates to:
  /// **'You lead the investigation on {capaNo}, so you are the one person whose judgement about this fix is not evidence. A holder of Quality authority who is not on the team lead\'s Account records the check.'**
  String capaEffectivenessYouLeadTheInvestigationOnSoYou(Object capaNo);

  /// No description provided for @capaEffectivenessTheCheckFallsDueDaysAfterThe.
  ///
  /// In en, this message translates to:
  /// **'The check falls due {effectivenessCheckDelayDays} days after the Concern closes.'**
  String capaEffectivenessTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  );

  /// No description provided for @capaEffectivenessTheConcernClosedAndTheCheckFell.
  ///
  /// In en, this message translates to:
  /// **'The Concern closed, and the check fell due on {effectivenessCheckDueAt}.'**
  String capaEffectivenessTheConcernClosedAndTheCheckFell(
    Object effectivenessCheckDueAt,
  );

  /// No description provided for @capaEffectivenessWhatTheCheckFound.
  ///
  /// In en, this message translates to:
  /// **'What the check found'**
  String get capaEffectivenessWhatTheCheckFound;

  /// No description provided for @capaEffectivenessAChainOfThisInvestigationHasNo.
  ///
  /// In en, this message translates to:
  /// **'A chain of this investigation has no confirmed root cause yet, so \"{value}\" cannot close it: the investigation has to have finished before the fix is judged to have held.'**
  String capaEffectivenessAChainOfThisInvestigationHasNo(Object value);

  /// No description provided for @capaEffectivenessWhatYouCheckedAndWhatYouFound.
  ///
  /// In en, this message translates to:
  /// **'What you checked, and what you found'**
  String get capaEffectivenessWhatYouCheckedAndWhatYouFound;

  /// No description provided for @capaEffectivenessTheEvidenceForTheVerdictSoThe.
  ///
  /// In en, this message translates to:
  /// **'The evidence for the verdict, so the next reader can weigh it.'**
  String get capaEffectivenessTheEvidenceForTheVerdictSoThe;

  /// No description provided for @capaOrgUnitFilterChooseTheOrgUnitWhoseInvestigationsAnd.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit whose investigations and everything beneath it you want to read, or clear back to every one of them.'**
  String get capaOrgUnitFilterChooseTheOrgUnitWhoseInvestigationsAnd;

  /// No description provided for @capaReportThatCapaReportCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That CAPA report could not be read'**
  String get capaReportThatCapaReportCouldNotBeRead;

  /// No description provided for @capaReportThe8dRecordOfThisInvestigationIts.
  ///
  /// In en, this message translates to:
  /// **'The 8D record of this investigation: its team, the problem it answers, what was done about it, and whether the fix held.'**
  String get capaReportThe8dRecordOfThisInvestigationIts;

  /// No description provided for @capaReportAnswersTheConcern.
  ///
  /// In en, this message translates to:
  /// **'Answers the Concern {actionNo} · {title}'**
  String capaReportAnswersTheConcern(Object actionNo, Object title);

  /// One line of the CAPA report's not-yet-done list: D1 has nobody on it.
  ///
  /// In en, this message translates to:
  /// **'The team has not been named.'**
  String get capaReportTheTeamHasNotBeenNamed;

  /// One line of the CAPA report's not-yet-done list: D2 is blank.
  ///
  /// In en, this message translates to:
  /// **'The problem description has not been written.'**
  String get capaReportTheProblemDescriptionHasNotBeenWritten;

  /// One line of the CAPA report's not-yet-done list: D3 has nothing on the Concern.
  ///
  /// In en, this message translates to:
  /// **'No containment action is recorded on the Concern.'**
  String get capaReportNoContainmentActionIsRecorded;

  /// One line of the CAPA report's not-yet-done list: a Why chain has no Why yet.
  ///
  /// In en, this message translates to:
  /// **'{chain} has not been started.'**
  String capaReportChainHasNotBeenStarted(Object chain);

  /// One line of the CAPA report's not-yet-done list: a Why chain has no confirmed root cause.
  ///
  /// In en, this message translates to:
  /// **'{chain} has no confirmed root cause.'**
  String capaReportChainHasNoConfirmedRootCause(Object chain);

  /// One line of the CAPA report's not-yet-done list: D5 has nothing on the Concern.
  ///
  /// In en, this message translates to:
  /// **'No countermeasure is recorded on the Concern.'**
  String get capaReportNoCountermeasureIsRecorded;

  /// One line of the CAPA report's not-yet-done list: D7 has nothing on the Concern.
  ///
  /// In en, this message translates to:
  /// **'No preventive action is recorded on the Concern.'**
  String get capaReportNoPreventiveActionIsRecorded;

  /// One line of the CAPA report's not-yet-done list: D8 has no verdict yet.
  ///
  /// In en, this message translates to:
  /// **'The effectiveness check has not been recorded.'**
  String get capaReportTheEffectivenessCheckHasNotBeenRecorded;

  /// The sentence the D3 section of the CAPA report reads when it is empty.
  ///
  /// In en, this message translates to:
  /// **'No containment action is recorded on the Concern yet.'**
  String get capaReportNoContainmentActionIsRecordedYet;

  /// The sentence the D5–D6 section of the CAPA report reads when it is empty.
  ///
  /// In en, this message translates to:
  /// **'No countermeasure is recorded on the Concern yet.'**
  String get capaReportNoCountermeasureIsRecordedYet;

  /// The sentence the D7 section of the CAPA report reads when it is empty.
  ///
  /// In en, this message translates to:
  /// **'No preventive action is recorded on the Concern yet.'**
  String get capaReportNoPreventiveActionIsRecordedYet;

  /// No description provided for @capaReportNotYetDone.
  ///
  /// In en, this message translates to:
  /// **'Not yet done'**
  String get capaReportNotYetDone;

  /// No description provided for @capaReportWhatThisReportIsStillWaitingFor.
  ///
  /// In en, this message translates to:
  /// **'What this report is still waiting for.'**
  String get capaReportWhatThisReportIsStillWaitingFor;

  /// No description provided for @capaReportD1Team.
  ///
  /// In en, this message translates to:
  /// **'D1 · Team'**
  String get capaReportD1Team;

  /// No description provided for @capaReportWhoInvestigatedThisProblemAndWhoLed.
  ///
  /// In en, this message translates to:
  /// **'Who investigated this problem, and who led it.'**
  String get capaReportWhoInvestigatedThisProblemAndWhoLed;

  /// No description provided for @capaReportD2TheProblem.
  ///
  /// In en, this message translates to:
  /// **'D2 · The problem'**
  String get capaReportD2TheProblem;

  /// No description provided for @capaReportWhatTheTeamIsInvestigatingInThe.
  ///
  /// In en, this message translates to:
  /// **'What the team is investigating, in the investigation\'s own words.'**
  String get capaReportWhatTheTeamIsInvestigatingInThe;

  /// No description provided for @capaReportD3Containment.
  ///
  /// In en, this message translates to:
  /// **'D3 · Containment'**
  String get capaReportD3Containment;

  /// No description provided for @capaReportWhatWasDoneToStopTheBad.
  ///
  /// In en, this message translates to:
  /// **'What was done to stop the bad product going any further.'**
  String get capaReportWhatWasDoneToStopTheBad;

  /// No description provided for @capaReportD4RootCause.
  ///
  /// In en, this message translates to:
  /// **'D4 · Root cause'**
  String get capaReportD4RootCause;

  /// No description provided for @capaReportTheCandidateCausesTheTeamConsideredAnd.
  ///
  /// In en, this message translates to:
  /// **'The candidate causes the team considered and the verdict on each, then two chains ending at one confirmed root cause: why the problem happened, and why it was not detected.'**
  String get capaReportTheCandidateCausesTheTeamConsideredAnd;

  /// No description provided for @capaReportD5D6Countermeasures.
  ///
  /// In en, this message translates to:
  /// **'D5–D6 · Countermeasures'**
  String get capaReportD5D6Countermeasures;

  /// No description provided for @capaReportWhatWasDoneAboutTheCauseAnd.
  ///
  /// In en, this message translates to:
  /// **'What was done about the cause, and whether its Check held.'**
  String get capaReportWhatWasDoneAboutTheCauseAnd;

  /// No description provided for @capaReportD7PreventiveActions.
  ///
  /// In en, this message translates to:
  /// **'D7 · Preventive actions'**
  String get capaReportD7PreventiveActions;

  /// No description provided for @capaReportWhatStopsItHappeningOnThisLine.
  ///
  /// In en, this message translates to:
  /// **'What stops it happening on this line again, with the outcome of every round.'**
  String get capaReportWhatStopsItHappeningOnThisLine;

  /// No description provided for @capaReportTheSafetyIncidentThisInvestigationAnswers.
  ///
  /// In en, this message translates to:
  /// **'The Safety incident this investigation answers'**
  String get capaReportTheSafetyIncidentThisInvestigationAnswers;

  /// No description provided for @capaReportTheIncidentTheConcernWasRaisedFrom.
  ///
  /// In en, this message translates to:
  /// **'The incident the Concern was raised from, with its number and severity — never the injury details, which the incident\'s own record restricts.'**
  String get capaReportTheIncidentTheConcernWasRaisedFrom;

  /// No description provided for @capaReportTheNonConformancesThisInvestigationAnswers.
  ///
  /// In en, this message translates to:
  /// **'The Non-conformances this investigation answers'**
  String get capaReportTheNonConformancesThisInvestigationAnswers;

  /// No description provided for @capaReportTheOccurrencesTheConcernAnswersWithThe.
  ///
  /// In en, this message translates to:
  /// **'The occurrences the Concern answers, with the number, the Product, the Defect code, the quantity and what was decided about the product.'**
  String get capaReportTheOccurrencesTheConcernAnswersWithThe;

  /// No description provided for @capaReportNoNonConformanceIsLinkedToThis.
  ///
  /// In en, this message translates to:
  /// **'No Non-conformance is linked to this Concern, so the report has no evidence to list.'**
  String get capaReportNoNonConformanceIsLinkedToThis;

  /// No description provided for @capaReportNoPhaseOfThisActionHasBeen.
  ///
  /// In en, this message translates to:
  /// **'No phase of this Action has been completed yet.'**
  String get capaReportNoPhaseOfThisActionHasBeen;

  /// No description provided for @capaReportTheCandidateCausesConsidered.
  ///
  /// In en, this message translates to:
  /// **'The candidate causes considered'**
  String get capaReportTheCandidateCausesConsidered;

  /// No description provided for @capaReportNoCandidateCauseIsRecordedSoNo.
  ///
  /// In en, this message translates to:
  /// **'No candidate cause is recorded, so no fishbone was worked.'**
  String get capaReportNoCandidateCauseIsRecordedSoNo;

  /// No description provided for @capaReportWhy.
  ///
  /// In en, this message translates to:
  /// **'Why {sequence} · {statement}'**
  String capaReportWhy(Object sequence, Object statement);

  /// No description provided for @capaReportD8Effectiveness.
  ///
  /// In en, this message translates to:
  /// **'D8 · Effectiveness'**
  String get capaReportD8Effectiveness;

  /// No description provided for @capaReportVerifiedByOn.
  ///
  /// In en, this message translates to:
  /// **'verified by {value} on {value2}'**
  String capaReportVerifiedByOn(Object value, Object value2);

  /// No description provided for @capaReportTheCheckFallsDueDaysAfterThe.
  ///
  /// In en, this message translates to:
  /// **'The check falls due {effectivenessCheckDelayDays} days after the Concern closes, and the Concern has not closed yet, so nothing has been verified.'**
  String capaReportTheCheckFallsDueDaysAfterThe(
    Object effectivenessCheckDelayDays,
  );

  /// No description provided for @capaReportRaisedFromThis.
  ///
  /// In en, this message translates to:
  /// **'raised from this'**
  String get capaReportRaisedFromThis;

  /// No description provided for @capaReportLinkedToThisConcern.
  ///
  /// In en, this message translates to:
  /// **'linked to this Concern'**
  String get capaReportLinkedToThisConcern;

  /// No description provided for @capaReportNoProductFromThisOccurrenceHasA.
  ///
  /// In en, this message translates to:
  /// **'No product from this occurrence has a Disposition yet.'**
  String get capaReportNoProductFromThisOccurrenceHasA;

  /// No description provided for @capaReportMinRework.
  ///
  /// In en, this message translates to:
  /// **'{value} min rework'**
  String capaReportMinRework(Object value);

  /// No description provided for @capaReportDecidedBy.
  ///
  /// In en, this message translates to:
  /// **'decided by {decidedBy}'**
  String capaReportDecidedBy(Object decidedBy);

  /// No description provided for @capaWhyThatIsNotAChain.
  ///
  /// In en, this message translates to:
  /// **'That is not a chain'**
  String get capaWhyThatIsNotAChain;

  /// No description provided for @capaWhyACapaReasonsWithTwoChainsWhy.
  ///
  /// In en, this message translates to:
  /// **'A CAPA reasons with two chains: why the problem happened, and why it was not detected.'**
  String get capaWhyACapaReasonsWithTwoChainsWhy;

  /// No description provided for @capaWhyIsSoItsChainsAreARecord.
  ///
  /// In en, this message translates to:
  /// **'{capaNo} is {value}, so its chains are a record rather than a worklist.'**
  String capaWhyIsSoItsChainsAreARecord(Object capaNo, Object value);

  /// No description provided for @capaWhyThatWhyIsNotInThisChain.
  ///
  /// In en, this message translates to:
  /// **'That Why is not in this chain'**
  String get capaWhyThatWhyIsNotInThisChain;

  /// No description provided for @capaWhyReviseWhy.
  ///
  /// In en, this message translates to:
  /// **'Revise Why {sequence}'**
  String capaWhyReviseWhy(Object sequence);

  /// No description provided for @capaWhyRemoveWhy.
  ///
  /// In en, this message translates to:
  /// **'Remove Why {sequence}?'**
  String capaWhyRemoveWhy(Object sequence);

  /// No description provided for @capaWhyItIsTakenOutOfTheChain.
  ///
  /// In en, this message translates to:
  /// **'It is taken out of the chain for good, and the Whys after it move up one. The rest of the investigation is not touched.'**
  String get capaWhyItIsTakenOutOfTheChain;

  /// No description provided for @capaWhyOneStepOfTheReasoningInYour.
  ///
  /// In en, this message translates to:
  /// **'{value} — one step of the reasoning, in your own words.'**
  String capaWhyOneStepOfTheReasoningInYour(Object value);

  /// No description provided for @capaWhyTheWhy.
  ///
  /// In en, this message translates to:
  /// **'The Why'**
  String get capaWhyTheWhy;

  /// No description provided for @capaWhyWhatYouFoundSaidSoTheNext.
  ///
  /// In en, this message translates to:
  /// **'What you found, said so the next person can follow it.'**
  String get capaWhyWhatYouFoundSaidSoTheNext;

  /// No description provided for @capasTheCapaListCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The CAPA list could not be read'**
  String get capasTheCapaListCouldNotBeRead;

  /// No description provided for @capasTheInvestigationsOpenedOnAConcernAnd.
  ///
  /// In en, this message translates to:
  /// **'The investigations opened on a Concern, and the effectiveness check each one is waiting on.'**
  String get capasTheInvestigationsOpenedOnAConcernAnd;

  /// No description provided for @capasOverdueChecks.
  ///
  /// In en, this message translates to:
  /// **'Overdue checks'**
  String get capasOverdueChecks;

  /// No description provided for @capasThereAreMoreInvestigationsThanThisList.
  ///
  /// In en, this message translates to:
  /// **'There are more investigations than this list shows. Narrow it by Org Unit or status.'**
  String get capasThereAreMoreInvestigationsThanThisList;

  /// No description provided for @capasNoInvestigationMatchesTheOrgUnitStatus.
  ///
  /// In en, this message translates to:
  /// **'No investigation matches the Org Unit, status or overdue check you asked for.'**
  String get capasNoInvestigationMatchesTheOrgUnitStatus;

  /// No description provided for @capasNoInvestigationsYet.
  ///
  /// In en, this message translates to:
  /// **'No investigations yet'**
  String get capasNoInvestigationsYet;

  /// No description provided for @capasACapaIsOpenedFromAConcern.
  ///
  /// In en, this message translates to:
  /// **'A CAPA is opened from a Concern, when somebody decides that the problem needs a root cause and a fix that holds.'**
  String get capasACapaIsOpenedFromAConcern;

  /// No description provided for @capasInvestigation.
  ///
  /// In en, this message translates to:
  /// **'Investigation'**
  String get capasInvestigation;

  /// No description provided for @capasEffectivenessCheck.
  ///
  /// In en, this message translates to:
  /// **'Effectiveness check'**
  String get capasEffectivenessCheck;

  /// No description provided for @capasOverdueCheck.
  ///
  /// In en, this message translates to:
  /// **'Overdue check'**
  String get capasOverdueCheck;

  /// No description provided for @capasRecordedBy.
  ///
  /// In en, this message translates to:
  /// **'{value}, recorded by {value2}.'**
  String capasRecordedBy(Object value, Object value2);

  /// No description provided for @capasTheEffectivenessCheckWasDueOn.
  ///
  /// In en, this message translates to:
  /// **'The effectiveness check was due on {effectivenessCheckDueAt}.'**
  String capasTheEffectivenessCheckWasDueOn(Object effectivenessCheckDueAt);

  /// No description provided for @capasTheEffectivenessCheckIsDueOn.
  ///
  /// In en, this message translates to:
  /// **'The effectiveness check is due on {effectivenessCheckDueAt}.'**
  String capasTheEffectivenessCheckIsDueOn(Object effectivenessCheckDueAt);

  /// No description provided for @capasTheEffectivenessCheckFallsDueDaysAfter.
  ///
  /// In en, this message translates to:
  /// **'The effectiveness check falls due {effectivenessCheckDelayDays} days after the Concern closes.'**
  String capasTheEffectivenessCheckFallsDueDaysAfter(
    Object effectivenessCheckDelayDays,
  );

  /// No description provided for @capasOnTheTeam.
  ///
  /// In en, this message translates to:
  /// **'{length} on the team'**
  String capasOnTheTeam(Object length);

  /// No description provided for @openCapaOpeningACapaNeedsAuthority.
  ///
  /// In en, this message translates to:
  /// **'Opening a CAPA needs authority'**
  String get openCapaOpeningACapaNeedsAuthority;

  /// No description provided for @openCapaOpeningACapaNeedsQualityAuthorityAt.
  ///
  /// In en, this message translates to:
  /// **'Opening a CAPA needs Quality authority at this Concern\'s Org Unit.'**
  String get openCapaOpeningACapaNeedsQualityAuthorityAt;

  /// The delete tooltip on a team member's chip in the open-a-CAPA dialog.
  ///
  /// In en, this message translates to:
  /// **'Take {displayName} off the team'**
  String openCapaTakeOffTheTeam(Object displayName);

  /// No description provided for @openCapaOpenACapaOn.
  ///
  /// In en, this message translates to:
  /// **'Open a CAPA on {actionNo}'**
  String openCapaOpenACapaOn(Object actionNo);

  /// No description provided for @openCapaOpenTheCapa.
  ///
  /// In en, this message translates to:
  /// **'Open the CAPA'**
  String get openCapaOpenTheCapa;

  /// No description provided for @openCapaAn8dInvestigationInTheActionLog.
  ///
  /// In en, this message translates to:
  /// **'{title} — an 8D investigation, in the action log, on this Concern. Its containments, countermeasures and preventive actions are the Concern\\u2019s own and are read on the CAPA rather than recorded again.'**
  String openCapaAn8dInvestigationInTheActionLog(Object title);

  /// No description provided for @openCapaTheProblemOptional.
  ///
  /// In en, this message translates to:
  /// **'The problem (optional)'**
  String get openCapaTheProblemOptional;

  /// No description provided for @openCapaD2WhatTheInvestigationIsAboutIn.
  ///
  /// In en, this message translates to:
  /// **'D2 — what the investigation is about, in the words a team will work from.'**
  String get openCapaD2WhatTheInvestigationIsAboutIn;

  /// No description provided for @openCapaTheTeam.
  ///
  /// In en, this message translates to:
  /// **'The team'**
  String get openCapaTheTeam;

  /// No description provided for @openCapaChosenFromTheEmployeeDirectoryLeaveIt.
  ///
  /// In en, this message translates to:
  /// **'Chosen from the Employee directory. Leave it empty to decide the team later — the investigation is what is being opened here.'**
  String get openCapaChosenFromTheEmployeeDirectoryLeaveIt;

  /// No description provided for @openCapaTeamLeadOptional.
  ///
  /// In en, this message translates to:
  /// **'Team lead (optional)'**
  String get openCapaTeamLeadOptional;

  /// No description provided for @openCapaWhoIsAnswerableForTheInvestigation.
  ///
  /// In en, this message translates to:
  /// **'Who is answerable for the investigation.'**
  String get openCapaWhoIsAnswerableForTheInvestigation;

  /// No description provided for @openCapaAddATeamMemberOptional.
  ///
  /// In en, this message translates to:
  /// **'Add a team member (optional)'**
  String get openCapaAddATeamMemberOptional;

  /// No description provided for @openCapaNobodyElseIsOnThisInvestigationYet.
  ///
  /// In en, this message translates to:
  /// **'Nobody else is on this investigation yet.'**
  String get openCapaNobodyElseIsOnThisInvestigationYet;

  /// No description provided for @awaitingApprovalYouReSignedInAsButAn.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed in as {email}, but an administrator hasn\'t admitted you to the Platform yet. Check back once they have.'**
  String awaitingApprovalYouReSignedInAsButAn(Object email);

  /// No description provided for @awaitingApprovalCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get awaitingApprovalCheckAgain;

  /// No description provided for @signInPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get signInPassword;

  /// The word between the password form and the Continue with Google button.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get signInOr;

  /// No description provided for @signInCreateAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get signInCreateAnAccount;

  /// No description provided for @signInContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get signInContinueWithGoogle;

  /// No description provided for @signInOneApplicationForRunningSeveralManufacturingPlants.
  ///
  /// In en, this message translates to:
  /// **'One application for running several manufacturing plants.'**
  String get signInOneApplicationForRunningSeveralManufacturingPlants;

  /// No description provided for @accessDeniedNotAvailableToYou.
  ///
  /// In en, this message translates to:
  /// **'Not available to you'**
  String get accessDeniedNotAvailableToYou;

  /// No description provided for @accessDeniedThisPartOfThePlatformIsFor.
  ///
  /// In en, this message translates to:
  /// **'This part of the Platform is for administrators. Ask one if you need what is here.'**
  String get accessDeniedThisPartOfThePlatformIsFor;

  /// No description provided for @commonBackToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get commonBackToHome;

  /// No description provided for @changePasswordAnAdministratorResetYourPasswordSoThe.
  ///
  /// In en, this message translates to:
  /// **'An administrator reset your password, so the one you were given is temporary. Choose your own to continue.'**
  String get changePasswordAnAdministratorResetYourPasswordSoThe;

  /// No description provided for @notFoundScreenNotFound.
  ///
  /// In en, this message translates to:
  /// **'Screen not found'**
  String get notFoundScreenNotFound;

  /// No description provided for @notFoundThereIsNothingAt.
  ///
  /// In en, this message translates to:
  /// **'There is nothing at {location}.'**
  String notFoundThereIsNothingAt(Object location);

  /// No description provided for @sessionErrorTheSessionCouldNotBeChecked.
  ///
  /// In en, this message translates to:
  /// **'The session could not be checked'**
  String get sessionErrorTheSessionCouldNotBeChecked;

  /// No description provided for @sessionErrorCouldNotCheckThisAccountSStatus.
  ///
  /// In en, this message translates to:
  /// **'Could not check this Account\'s status: {message}'**
  String sessionErrorCouldNotCheckThisAccountSStatus(Object message);

  /// No description provided for @appDateFieldChooseADate.
  ///
  /// In en, this message translates to:
  /// **'Choose a date'**
  String get appDateFieldChooseADate;

  /// No description provided for @appDateTimeFieldChooseADateAndTime.
  ///
  /// In en, this message translates to:
  /// **'Choose a date and time'**
  String get appDateTimeFieldChooseADateAndTime;

  /// No description provided for @appSearchFieldNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get appSearchFieldNoMatches;

  /// No description provided for @appSearchFieldNothingMatchedTryADifferentTerm.
  ///
  /// In en, this message translates to:
  /// **'Nothing matched \"{lastQueriedTerm}\" — try a different term.'**
  String appSearchFieldNothingMatchedTryADifferentTerm(Object lastQueriedTerm);

  /// No description provided for @appSearchFieldSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed'**
  String get appSearchFieldSearchFailed;

  /// No description provided for @appSearchFieldThereAreMoreMatchesThanAreShown.
  ///
  /// In en, this message translates to:
  /// **'There are more matches than are shown — keep typing to narrow the list.'**
  String get appSearchFieldThereAreMoreMatchesThanAreShown;

  /// No description provided for @failureStateNotVisibleToYou.
  ///
  /// In en, this message translates to:
  /// **'Not visible to you. {message}'**
  String failureStateNotVisibleToYou(Object message);

  /// No description provided for @failureStateNotVisibleToYou2.
  ///
  /// In en, this message translates to:
  /// **'Not visible to you'**
  String get failureStateNotVisibleToYou2;

  /// No description provided for @signaturePadSignatureDrawingArea.
  ///
  /// In en, this message translates to:
  /// **'Signature drawing area'**
  String get signaturePadSignatureDrawingArea;

  /// No description provided for @complaintDetailThatComplaintCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That complaint could not be read'**
  String get complaintDetailThatComplaintCouldNotBeRead;

  /// No description provided for @complaintDetailBackToCustomerComplaints.
  ///
  /// In en, this message translates to:
  /// **'Back to Customer complaints'**
  String get complaintDetailBackToCustomerComplaints;

  /// No description provided for @commonPastDue.
  ///
  /// In en, this message translates to:
  /// **'Past due'**
  String get commonPastDue;

  /// No description provided for @commonWarrantyClaim.
  ///
  /// In en, this message translates to:
  /// **'Warranty claim'**
  String get commonWarrantyClaim;

  /// No description provided for @complaintDetailTheProductThisIsAbout.
  ///
  /// In en, this message translates to:
  /// **'The product this is about'**
  String get complaintDetailTheProductThisIsAbout;

  /// No description provided for @complaintDetailNothingControlsTheProductThisCustomerComplained.
  ///
  /// In en, this message translates to:
  /// **'Nothing controls the product this customer complained about yet. Record a Non-conformance from this complaint, or link one that already exists for the same Product.'**
  String get complaintDetailNothingControlsTheProductThisCustomerComplained;

  /// No description provided for @commonLinkOneThatExists.
  ///
  /// In en, this message translates to:
  /// **'Link one that exists'**
  String get commonLinkOneThatExists;

  /// No description provided for @commonOpenRecord.
  ///
  /// In en, this message translates to:
  /// **'Open record'**
  String get commonOpenRecord;

  /// No description provided for @complaintDetailFoundByTheCustomerSoThisComplaint.
  ///
  /// In en, this message translates to:
  /// **'Found by the customer, so this complaint is where it started.'**
  String get complaintDetailFoundByTheCustomerSoThisComplaint;

  /// No description provided for @complaintDetailRecordedAtAndLinkedToThisComplaint.
  ///
  /// In en, this message translates to:
  /// **'Recorded at {value}, and linked to this complaint.'**
  String complaintDetailRecordedAtAndLinkedToThisComplaint(Object value);

  /// No description provided for @commonOpenTheNonConformance.
  ///
  /// In en, this message translates to:
  /// **'Open the Non-conformance'**
  String get commonOpenTheNonConformance;

  /// No description provided for @commonTheResponse.
  ///
  /// In en, this message translates to:
  /// **'The response'**
  String get commonTheResponse;

  /// No description provided for @complaintDetailClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed {closedAt}'**
  String complaintDetailClosed(Object closedAt);

  /// No description provided for @complaintDetailNothingHasBeenSaidBackToThis.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been said back to this customer yet.'**
  String get complaintDetailNothingHasBeenSaidBackToThis;

  /// No description provided for @complaintDetailCloseWithTheResponse.
  ///
  /// In en, this message translates to:
  /// **'Close with the response'**
  String get complaintDetailCloseWithTheResponse;

  /// No description provided for @complaintFormRecordACustomerComplaint.
  ///
  /// In en, this message translates to:
  /// **'Record a customer complaint'**
  String get complaintFormRecordACustomerComplaint;

  /// No description provided for @complaintFormCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get complaintFormCustomer;

  /// No description provided for @commonDefectCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Defect code (optional)'**
  String get commonDefectCodeOptional;

  /// No description provided for @complaintFormWhatTheCustomerSaysIsWrongA.
  ///
  /// In en, this message translates to:
  /// **'What the customer says is wrong. A Non-conformance recorded from this complaint carries it.'**
  String get complaintFormWhatTheCustomerSaysIsWrongA;

  /// No description provided for @commonNotKnownYet.
  ///
  /// In en, this message translates to:
  /// **'Not known yet'**
  String get commonNotKnownYet;

  /// No description provided for @complaintFormQuantityOptional.
  ///
  /// In en, this message translates to:
  /// **'Quantity (optional)'**
  String get complaintFormQuantityOptional;

  /// No description provided for @complaintFormInTheProductSOwnUnitOf.
  ///
  /// In en, this message translates to:
  /// **'In the Product\'s own unit of measure.'**
  String get complaintFormInTheProductSOwnUnitOf;

  /// No description provided for @complaintFormResponseDueOptional.
  ///
  /// In en, this message translates to:
  /// **'Response due (optional)'**
  String get complaintFormResponseDueOptional;

  /// No description provided for @complaintFormTheDayTheCustomerWasPromisedAn.
  ///
  /// In en, this message translates to:
  /// **'The day the customer was promised an answer.'**
  String get complaintFormTheDayTheCustomerWasPromisedAn;

  /// No description provided for @complaintFormWhatTheCustomerSaid.
  ///
  /// In en, this message translates to:
  /// **'What the customer said'**
  String get complaintFormWhatTheCustomerSaid;

  /// No description provided for @complaintFormWhoAnswersIt.
  ///
  /// In en, this message translates to:
  /// **'Who answers it'**
  String get complaintFormWhoAnswersIt;

  /// No description provided for @complaintFormChooseTheOrgUnitThatWillAnswer.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit that will answer this complaint. This is what decides who may act on it.'**
  String get complaintFormChooseTheOrgUnitThatWillAnswer;

  /// No description provided for @complaintFormThisComplaintWillBeFiledAt.
  ///
  /// In en, this message translates to:
  /// **'This complaint will be filed at {value}.'**
  String complaintFormThisComplaintWillBeFiledAt(Object value);

  /// No description provided for @commonLinkANonConformance.
  ///
  /// In en, this message translates to:
  /// **'Link a Non-conformance'**
  String get commonLinkANonConformance;

  /// No description provided for @commonLinking.
  ///
  /// In en, this message translates to:
  /// **'Linking…'**
  String get commonLinking;

  /// No description provided for @commonLinkIt.
  ///
  /// In en, this message translates to:
  /// **'Link it'**
  String get commonLinkIt;

  /// No description provided for @complaintLinkANonConformanceThatAlreadyExistsFor.
  ///
  /// In en, this message translates to:
  /// **'A Non-conformance that already exists for {productName} can be linked to this complaint, instead of recording a second one for the same problem.'**
  String complaintLinkANonConformanceThatAlreadyExistsFor(Object productName);

  /// No description provided for @commonTheNonConformancesCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Non-conformances could not be read'**
  String get commonTheNonConformancesCouldNotBeRead;

  /// No description provided for @complaintLinkNoNonConformanceHasBeenRecordedFor.
  ///
  /// In en, this message translates to:
  /// **'No Non-conformance has been recorded for this Product yet, so there is nothing to link. Record one from this complaint instead.'**
  String get complaintLinkNoNonConformanceHasBeenRecordedFor;

  /// No description provided for @commonTheNonConformanceThatControlsIt.
  ///
  /// In en, this message translates to:
  /// **'The Non-conformance that controls it'**
  String get commonTheNonConformanceThatControlsIt;

  /// No description provided for @complaintNonconformanceControlTheProduct.
  ///
  /// In en, this message translates to:
  /// **'Control the product'**
  String get complaintNonconformanceControlTheProduct;

  /// No description provided for @complaintNonconformanceANonConformanceIsRecordedAtFor.
  ///
  /// In en, this message translates to:
  /// **'A Non-conformance is recorded at {orgUnitName} for {productName}, found by the customer.'**
  String complaintNonconformanceANonConformanceIsRecordedAtFor(
    Object orgUnitName,
    Object productName,
  );

  /// No description provided for @complaintNonconformanceHowMuchProductIsInQuestionIn.
  ///
  /// In en, this message translates to:
  /// **'How much product is in question, in the Product\'s own unit.'**
  String get complaintNonconformanceHowMuchProductIsInQuestionIn;

  /// No description provided for @complaintNonconformanceTheComplaintSOwnDefectCodeIs.
  ///
  /// In en, this message translates to:
  /// **'The complaint\'s own Defect code is carried onto the record.'**
  String get complaintNonconformanceTheComplaintSOwnDefectCodeIs;

  /// No description provided for @commonTheDefectCodesCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Defect codes could not be read'**
  String get commonTheDefectCodesCouldNotBeRead;

  /// No description provided for @complaintNonconformanceThisComplaintCarriesNoneSoChooseThe.
  ///
  /// In en, this message translates to:
  /// **'This complaint carries none, so choose the one to record it against.'**
  String get complaintNonconformanceThisComplaintCarriesNoneSoChooseThe;

  /// No description provided for @commonWhatWasDoneAtOnceRecordingIt.
  ///
  /// In en, this message translates to:
  /// **'What was done at once. Recording it makes the record contained.'**
  String get commonWhatWasDoneAtOnceRecordingIt;

  /// No description provided for @commonNarrowTheRegister.
  ///
  /// In en, this message translates to:
  /// **'Narrow the register'**
  String get commonNarrowTheRegister;

  /// No description provided for @complaintOrgUnitFilterChooseTheOrgUnitWhoseComplaintsAnd.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit whose complaints, and everything beneath it, you want to read — or clear back to the whole Site.'**
  String get complaintOrgUnitFilterChooseTheOrgUnitWhoseComplaintsAnd;

  /// No description provided for @complaintRespondAnswerTheCustomer.
  ///
  /// In en, this message translates to:
  /// **'Answer the customer'**
  String get complaintRespondAnswerTheCustomer;

  /// No description provided for @complaintRespondClosing.
  ///
  /// In en, this message translates to:
  /// **'Closing…'**
  String get complaintRespondClosing;

  /// No description provided for @complaintRespondCloseTheComplaint.
  ///
  /// In en, this message translates to:
  /// **'Close the complaint'**
  String get complaintRespondCloseTheComplaint;

  /// No description provided for @complaintRespondWhatWasSaidBackToAboutThis.
  ///
  /// In en, this message translates to:
  /// **'What was said back to {customerName} about {complaintNo}. This closes the complaint.'**
  String complaintRespondWhatWasSaidBackToAboutThis(
    Object customerName,
    Object complaintNo,
  );

  /// No description provided for @complaintsTheComplaintRegisterCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The complaint register could not be read'**
  String get complaintsTheComplaintRegisterCouldNotBeRead;

  /// No description provided for @complaintsWhatCustomersHaveComplainedAboutAtThis.
  ///
  /// In en, this message translates to:
  /// **'What customers have complained about at this Site, and whether the product they complained about is under control.'**
  String get complaintsWhatCustomersHaveComplainedAboutAtThis;

  /// No description provided for @complaintsRecordAComplaint.
  ///
  /// In en, this message translates to:
  /// **'Record a complaint'**
  String get complaintsRecordAComplaint;

  /// No description provided for @complaintsThereAreMoreComplaintsThanThisList.
  ///
  /// In en, this message translates to:
  /// **'There are more complaints than this list shows. Narrow it by Org Unit or by status to see the rest.'**
  String get complaintsThereAreMoreComplaintsThanThisList;

  /// No description provided for @complaintsTheRegisterHasComplaintsButNoneOf.
  ///
  /// In en, this message translates to:
  /// **'The register has complaints, but none of them is in the area or state you picked.'**
  String get complaintsTheRegisterHasComplaintsButNoneOf;

  /// No description provided for @complaintsNoComplaints.
  ///
  /// In en, this message translates to:
  /// **'No complaints'**
  String get complaintsNoComplaints;

  /// No description provided for @complaintsNoCustomerHasComplainedAboutAnythingFrom.
  ///
  /// In en, this message translates to:
  /// **'No customer has complained about anything from this Site.'**
  String get complaintsNoCustomerHasComplainedAboutAnythingFrom;

  /// No description provided for @complaintsComplaint.
  ///
  /// In en, this message translates to:
  /// **'Complaint'**
  String get complaintsComplaint;

  /// No description provided for @complaintsCustomerAndProduct.
  ///
  /// In en, this message translates to:
  /// **'Customer and product'**
  String get complaintsCustomerAndProduct;

  /// No description provided for @complaintsResponseDue.
  ///
  /// In en, this message translates to:
  /// **'Response due'**
  String get complaintsResponseDue;

  /// No description provided for @commonControl.
  ///
  /// In en, this message translates to:
  /// **'Control'**
  String get commonControl;

  /// No description provided for @complaintsWarranty.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get complaintsWarranty;

  /// No description provided for @customerFormCorrectCustomer.
  ///
  /// In en, this message translates to:
  /// **'Correct Customer'**
  String get customerFormCorrectCustomer;

  /// No description provided for @commonAddCustomer.
  ///
  /// In en, this message translates to:
  /// **'Add Customer'**
  String get commonAddCustomer;

  /// No description provided for @customerFormACustomerSCodeCannotBeCorrected.
  ///
  /// In en, this message translates to:
  /// **'A Customer\'s code cannot be corrected'**
  String get customerFormACustomerSCodeCannotBeCorrected;

  /// No description provided for @commonContactEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Contact email (optional)'**
  String get commonContactEmailOptional;

  /// No description provided for @customersTheCustomerListCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Customer list could not be read'**
  String get customersTheCustomerListCouldNotBeRead;

  /// No description provided for @customersWhoThePlantSCustomersAreSo.
  ///
  /// In en, this message translates to:
  /// **'Who the plant\'s customers are, so a complaint has someone to belong to and a response has somewhere to go.'**
  String get customersWhoThePlantSCustomersAreSo;

  /// No description provided for @customersNoCustomersYet.
  ///
  /// In en, this message translates to:
  /// **'No Customers yet'**
  String get customersNoCustomersYet;

  /// No description provided for @commonNothingHasBeenDefinedInTheList.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been defined in the list.'**
  String get commonNothingHasBeenDefinedInTheList;

  /// No description provided for @customersFilterCustomers.
  ///
  /// In en, this message translates to:
  /// **'Filter Customers'**
  String get customersFilterCustomers;

  /// No description provided for @customersNoCustomersMatch.
  ///
  /// In en, this message translates to:
  /// **'No Customers match'**
  String get customersNoCustomersMatch;

  /// No description provided for @commonNothingInTheListMatchesTryA.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the list matches \"{term}\". Try a different name or code, or clear the filter.'**
  String commonNothingInTheListMatchesTryA(Object term);

  /// No description provided for @defectCodeFormCorrectDefectCode.
  ///
  /// In en, this message translates to:
  /// **'Correct Defect code'**
  String get defectCodeFormCorrectDefectCode;

  /// No description provided for @commonAddDefectCode.
  ///
  /// In en, this message translates to:
  /// **'Add Defect code'**
  String get commonAddDefectCode;

  /// No description provided for @defectCodeFormADefectCodeCannotBeCorrected.
  ///
  /// In en, this message translates to:
  /// **'A Defect code cannot be corrected'**
  String get defectCodeFormADefectCodeCannotBeCorrected;

  /// No description provided for @defectCodeFormDefaultSeverity.
  ///
  /// In en, this message translates to:
  /// **'Default severity'**
  String get defectCodeFormDefaultSeverity;

  /// No description provided for @defectCodeFormWhatANonConformanceRecordedAgainstThis.
  ///
  /// In en, this message translates to:
  /// **'What a Non-conformance recorded against this code starts at'**
  String get defectCodeFormWhatANonConformanceRecordedAgainstThis;

  /// No description provided for @defectCodeFormParent.
  ///
  /// In en, this message translates to:
  /// **'Parent'**
  String get defectCodeFormParent;

  /// No description provided for @defectCodeFormNoParentTopLevel.
  ///
  /// In en, this message translates to:
  /// **'No parent — top level'**
  String get defectCodeFormNoParentTopLevel;

  /// No description provided for @defectCodesTheDefectCodeCatalogueCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The Defect code catalogue could not be read'**
  String get defectCodesTheDefectCodeCatalogueCouldNotBe;

  /// No description provided for @defectCodesTheKindsOfThingFoundWrongOne.
  ///
  /// In en, this message translates to:
  /// **'The kinds of thing found wrong — one list shared by every Site, and the severity each starts a Non-conformance at.'**
  String get defectCodesTheKindsOfThingFoundWrongOne;

  /// A Defect code that hangs under nothing, said on its register row.
  ///
  /// In en, this message translates to:
  /// **'Top level'**
  String get defectCodesTopLevel;

  /// A Defect code's place in the tree, named by its parent.
  ///
  /// In en, this message translates to:
  /// **'Under {parentName}'**
  String defectCodesUnder(Object parentName);

  /// The severity a Non-conformance recorded against this Defect code starts at.
  ///
  /// In en, this message translates to:
  /// **'starts at {severity}'**
  String defectCodesStartsAt(Object severity);

  /// No description provided for @defectCodesNoDefectCodesYet.
  ///
  /// In en, this message translates to:
  /// **'No Defect codes yet'**
  String get defectCodesNoDefectCodesYet;

  /// The way out of the remove-this-picture confirmation that leaves the picture where it is.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get issueImagesKeepIt;

  /// No description provided for @issueImagesRemoveThisPicture.
  ///
  /// In en, this message translates to:
  /// **'Remove this picture?'**
  String get issueImagesRemoveThisPicture;

  /// No description provided for @issueImagesThePictureIsTakenOffTheRecord.
  ///
  /// In en, this message translates to:
  /// **'The picture is taken off the record. A slide needs one, so the issue may leave the show until another is added.'**
  String get issueImagesThePictureIsTakenOffTheRecord;

  /// No description provided for @issueImagesAddPicture.
  ///
  /// In en, this message translates to:
  /// **'Add picture'**
  String get issueImagesAddPicture;

  /// No description provided for @issueImagesPictures.
  ///
  /// In en, this message translates to:
  /// **'Pictures'**
  String get issueImagesPictures;

  /// No description provided for @issueImagesThePicturesCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The pictures could not be read'**
  String get issueImagesThePicturesCouldNotBeRead;

  /// No description provided for @issueImagesNoPictureYetASlideNeedsAt.
  ///
  /// In en, this message translates to:
  /// **'No picture yet. A slide needs at least one: add the photo that shows the problem.'**
  String get issueImagesNoPictureYetASlideNeedsAt;

  /// No description provided for @commonThePictureCouldNotBeLoaded.
  ///
  /// In en, this message translates to:
  /// **'The picture could not be loaded'**
  String get commonThePictureCouldNotBeLoaded;

  /// No description provided for @issueImagesAPictureOfTheIssue.
  ///
  /// In en, this message translates to:
  /// **'A picture of the issue'**
  String get issueImagesAPictureOfTheIssue;

  /// No description provided for @issueImagesRemoveThisPicture2.
  ///
  /// In en, this message translates to:
  /// **'Remove this picture'**
  String get issueImagesRemoveThisPicture2;

  /// No description provided for @issueImagesAddThisPicture.
  ///
  /// In en, this message translates to:
  /// **'Add this picture'**
  String get issueImagesAddThisPicture;

  /// No description provided for @issueImagesTheCaptionIsWhatTheSlideSays.
  ///
  /// In en, this message translates to:
  /// **'The caption is what the slide says under it. It is optional.'**
  String get issueImagesTheCaptionIsWhatTheSlideSays;

  /// No description provided for @issueImagesAddIt.
  ///
  /// In en, this message translates to:
  /// **'Add it'**
  String get issueImagesAddIt;

  /// No description provided for @issueImagesCaptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Caption (optional)'**
  String get issueImagesCaptionOptional;

  /// No description provided for @issueImagesBurrOnTheFlangeNearTheLocating.
  ///
  /// In en, this message translates to:
  /// **'Burr on the flange, near the locating lug'**
  String get issueImagesBurrOnTheFlangeNearTheLocating;

  /// No description provided for @nonconformanceCancelCannotCancelIt.
  ///
  /// In en, this message translates to:
  /// **'Cannot cancel it'**
  String get nonconformanceCancelCannotCancelIt;

  /// No description provided for @nonconformanceCancelCancellingANonConformanceNeedsQualityAuthority.
  ///
  /// In en, this message translates to:
  /// **'Cancelling a Non-conformance needs Quality authority at its Org Unit.'**
  String get nonconformanceCancelCancellingANonConformanceNeedsQualityAuthority;

  /// No description provided for @nonconformanceCancelANonConformanceThatIsClosedOr.
  ///
  /// In en, this message translates to:
  /// **'A Non-conformance that is closed or already cancelled cannot be cancelled.'**
  String get nonconformanceCancelANonConformanceThatIsClosedOr;

  /// No description provided for @nonconformanceCancelCancelThisNonConformance.
  ///
  /// In en, this message translates to:
  /// **'Cancel this Non-conformance'**
  String get nonconformanceCancelCancelThisNonConformance;

  /// No description provided for @nonconformanceCancelCancelIt.
  ///
  /// In en, this message translates to:
  /// **'Cancel it'**
  String get nonconformanceCancelCancelIt;

  /// No description provided for @nonconformanceCancelWillBeCancelledRatherThanDealtWith.
  ///
  /// In en, this message translates to:
  /// **'{issueNo} will be cancelled rather than dealt with. A cancelled Non-conformance accepts no further Dispositions or quantity changes.'**
  String nonconformanceCancelWillBeCancelledRatherThanDealtWith(Object issueNo);

  /// No description provided for @commonNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get commonNote;

  /// No description provided for @nonconformanceCancelWhyItShouldNeverHaveBeenRecorded.
  ///
  /// In en, this message translates to:
  /// **'Why it should never have been recorded.'**
  String get nonconformanceCancelWhyItShouldNeverHaveBeenRecorded;

  /// No description provided for @nonconformanceConcessionCannotGrantIt.
  ///
  /// In en, this message translates to:
  /// **'Cannot grant it'**
  String get nonconformanceConcessionCannotGrantIt;

  /// No description provided for @nonconformanceConcessionGrantingAConcessionNeedsQualityAuthorityAt.
  ///
  /// In en, this message translates to:
  /// **'Granting a Concession needs Quality authority at this Non-conformance\'s Org Unit.'**
  String get nonconformanceConcessionGrantingAConcessionNeedsQualityAuthorityAt;

  /// No description provided for @nonconformanceConcessionGrantIt.
  ///
  /// In en, this message translates to:
  /// **'Grant it'**
  String get nonconformanceConcessionGrantIt;

  /// No description provided for @nonconformanceConcessionAcceptingTheProductAsItIsNeeds.
  ///
  /// In en, this message translates to:
  /// **'Accepting the product as it is needs Quality authority, and your name stays on {issueNo}.'**
  String nonconformanceConcessionAcceptingTheProductAsItIsNeeds(Object issueNo);

  /// No description provided for @nonconformanceConcessionQuantityAcceptedAsItIs.
  ///
  /// In en, this message translates to:
  /// **'Quantity accepted as it is'**
  String get nonconformanceConcessionQuantityAcceptedAsItIs;

  /// No description provided for @nonconformanceConcessionAtMost.
  ///
  /// In en, this message translates to:
  /// **'At most {value} {unit}.'**
  String nonconformanceConcessionAtMost(Object value, Object unit);

  /// No description provided for @nonconformanceConcessionReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get nonconformanceConcessionReference;

  /// No description provided for @nonconformanceConcessionTheDeviationOrApprovalNumberItIs.
  ///
  /// In en, this message translates to:
  /// **'The deviation or approval number it is granted under.'**
  String get nonconformanceConcessionTheDeviationOrApprovalNumberItIs;

  /// No description provided for @nonconformanceConcessionWhyTheProductIsAcceptableAsIt.
  ///
  /// In en, this message translates to:
  /// **'Why the product is acceptable as it is.'**
  String get nonconformanceConcessionWhyTheProductIsAcceptableAsIt;

  /// No description provided for @nonconformanceDispositionHasStillUndecidedDealWithSomeOf.
  ///
  /// In en, this message translates to:
  /// **'{issueNo} has {value} {unit} still undecided. Deal with some of it here.'**
  String nonconformanceDispositionHasStillUndecidedDealWithSomeOf(
    Object issueNo,
    Object value,
    Object unit,
  );

  /// No description provided for @commonDisposition.
  ///
  /// In en, this message translates to:
  /// **'Disposition'**
  String get commonDisposition;

  /// No description provided for @nonconformanceDispositionScrapReworkOrBackToTheSupplier.
  ///
  /// In en, this message translates to:
  /// **'Scrap, rework, or back to the supplier.'**
  String get nonconformanceDispositionScrapReworkOrBackToTheSupplier;

  /// No description provided for @nonconformanceDispositionAtMost.
  ///
  /// In en, this message translates to:
  /// **'At most {value} {unit}.'**
  String nonconformanceDispositionAtMost(Object value, Object unit);

  /// No description provided for @nonconformanceDispositionReworkMinutes.
  ///
  /// In en, this message translates to:
  /// **'Rework minutes'**
  String get nonconformanceDispositionReworkMinutes;

  /// No description provided for @nonconformanceDispositionHowLongTheReworkTookForCost.
  ///
  /// In en, this message translates to:
  /// **'How long the rework took, for cost of poor quality.'**
  String get nonconformanceDispositionHowLongTheReworkTookForCost;

  /// No description provided for @nonconformanceDispositionWhatWasDoneWithIt.
  ///
  /// In en, this message translates to:
  /// **'What was done with it.'**
  String get nonconformanceDispositionWhatWasDoneWithIt;

  /// No description provided for @nonconformanceLinkConcernBecomesOneOfTheOccurrencesThisConcern.
  ///
  /// In en, this message translates to:
  /// **'{issueNo} becomes one of the occurrences this Concern answers. The Concern keeps the Non-conformance it was raised from.'**
  String nonconformanceLinkConcernBecomesOneOfTheOccurrencesThisConcern(
    Object issueNo,
  );

  /// No description provided for @nonconformanceLinkConcernThisSiteHasNoOpenConcernTo.
  ///
  /// In en, this message translates to:
  /// **'This Site has no open Concern to link it to. Raise one instead.'**
  String get nonconformanceLinkConcernThisSiteHasNoOpenConcernTo;

  /// No description provided for @nonconformanceLinkConcernConcern.
  ///
  /// In en, this message translates to:
  /// **'Concern'**
  String get nonconformanceLinkConcernConcern;

  /// No description provided for @nonconformanceLinkConcernByItsNumberOrItsTitle.
  ///
  /// In en, this message translates to:
  /// **'By its number or its title.'**
  String get nonconformanceLinkConcernByItsNumberOrItsTitle;

  /// No description provided for @nonconformanceLowerSeverityCannotLowerIt.
  ///
  /// In en, this message translates to:
  /// **'Cannot lower it'**
  String get nonconformanceLowerSeverityCannotLowerIt;

  /// No description provided for @nonconformanceLowerSeverityLoweringASeverityNeedsQualityAuthorityAt.
  ///
  /// In en, this message translates to:
  /// **'Lowering a severity needs Quality authority at this Non-conformance\'s Org Unit.'**
  String
  get nonconformanceLowerSeverityLoweringASeverityNeedsQualityAuthorityAt;

  /// No description provided for @nonconformanceLowerSeverityLowerIt.
  ///
  /// In en, this message translates to:
  /// **'Lower it'**
  String get nonconformanceLowerSeverityLowerIt;

  /// No description provided for @nonconformanceLowerSeverityIsSeverityAndItsDefectCodeStarts.
  ///
  /// In en, this message translates to:
  /// **'{issueNo} is {value} severity, and its Defect code starts at {value2}.'**
  String nonconformanceLowerSeverityIsSeverityAndItsDefectCodeStarts(
    Object issueNo,
    Object value,
    Object value2,
  );

  /// No description provided for @nonconformanceLowerSeverityThisNonConformanceIsAlreadyAtThe.
  ///
  /// In en, this message translates to:
  /// **'This Non-conformance is already at the lightest severity.'**
  String get nonconformanceLowerSeverityThisNonConformanceIsAlreadyAtThe;

  /// No description provided for @nonconformanceLowerSeverityLowerTheSeverityTo.
  ///
  /// In en, this message translates to:
  /// **'Lower the severity to'**
  String get nonconformanceLowerSeverityLowerTheSeverityTo;

  /// No description provided for @nonconformanceLowerSeverityLoweringWhatTheDefectCodeSaysNeeds.
  ///
  /// In en, this message translates to:
  /// **'Lowering what the Defect code says needs Quality authority.'**
  String get nonconformanceLowerSeverityLoweringWhatTheDefectCodeSaysNeeds;

  /// No description provided for @commonLeaveTheSeverityAlone.
  ///
  /// In en, this message translates to:
  /// **'Leave the severity alone'**
  String get commonLeaveTheSeverityAlone;

  /// No description provided for @nonconformanceLowerSeverityWhyItIsLessBadThanThe.
  ///
  /// In en, this message translates to:
  /// **'Why it is less bad than the Defect code says.'**
  String get nonconformanceLowerSeverityWhyItIsLessBadThanThe;

  /// No description provided for @nonconformanceOrgUnitFilterChooseTheOrgUnitWhoseNonConformances.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit whose Non-conformances and everything beneath it you want to read, or clear back to the whole Site.'**
  String get nonconformanceOrgUnitFilterChooseTheOrgUnitWhoseNonConformances;

  /// No description provided for @nonconformanceQuantityIncreaseTheAffectedQuantity.
  ///
  /// In en, this message translates to:
  /// **'Increase the affected quantity'**
  String get nonconformanceQuantityIncreaseTheAffectedQuantity;

  /// No description provided for @nonconformanceQuantityIncreaseIt.
  ///
  /// In en, this message translates to:
  /// **'Increase it'**
  String get nonconformanceQuantityIncreaseIt;

  /// No description provided for @nonconformanceQuantityCurrentlyCoversItCanOnlyGrow.
  ///
  /// In en, this message translates to:
  /// **'{issueNo} currently covers {value} {unit}. It can only grow.'**
  String nonconformanceQuantityCurrentlyCoversItCanOnlyGrow(
    Object issueNo,
    Object value,
    Object unit,
  );

  /// No description provided for @nonconformanceQuantityNewAffectedQuantity.
  ///
  /// In en, this message translates to:
  /// **'New affected quantity'**
  String get nonconformanceQuantityNewAffectedQuantity;

  /// No description provided for @nonconformanceQuantityMoreThanOrNothingAtAll.
  ///
  /// In en, this message translates to:
  /// **'More than {value} {unit}, or nothing at all.'**
  String nonconformanceQuantityMoreThanOrNothingAtAll(
    Object value,
    Object unit,
  );

  /// No description provided for @nonconformanceQuantityWhyItChangedSortingTheBinFound.
  ///
  /// In en, this message translates to:
  /// **'Why it changed — \"sorting the bin found eight more\".'**
  String get nonconformanceQuantityWhyItChangedSortingTheBinFound;

  /// No description provided for @nonconformanceRaiseConcernIsRecordedAtAndTheConcernIs.
  ///
  /// In en, this message translates to:
  /// **'{issueNo} is recorded at {orgUnitName}, and the Concern is raised there — a problem is solved where it happened.'**
  String nonconformanceRaiseConcernIsRecordedAtAndTheConcernIs(
    Object issueNo,
    Object orgUnitName,
  );

  /// No description provided for @nonconformanceRaiseConcernWhatIsTheProblemToSolve.
  ///
  /// In en, this message translates to:
  /// **'What is the problem to solve?'**
  String get nonconformanceRaiseConcernWhatIsTheProblemToSolve;

  /// No description provided for @nonconformanceRaiseConcernTheConcernIsReadInTheAction.
  ///
  /// In en, this message translates to:
  /// **'The Concern is read in the action log, so say the problem, not the product.'**
  String get nonconformanceRaiseConcernTheConcernIsReadInTheAction;

  /// No description provided for @commonAnythingKnownYet.
  ///
  /// In en, this message translates to:
  /// **'Anything known yet'**
  String get commonAnythingKnownYet;

  /// No description provided for @nonconformanceRaiseConcernOptionalTheNonConformanceItselfIsAlready.
  ///
  /// In en, this message translates to:
  /// **'Optional. The Non-conformance itself is already linked as evidence.'**
  String get nonconformanceRaiseConcernOptionalTheNonConformanceItselfIsAlready;

  /// No description provided for @common1IsWorst.
  ///
  /// In en, this message translates to:
  /// **'1 is worst.'**
  String get common1IsWorst;

  /// No description provided for @nonconformanceReopenCannotReopenIt.
  ///
  /// In en, this message translates to:
  /// **'Cannot reopen it'**
  String get nonconformanceReopenCannotReopenIt;

  /// No description provided for @nonconformanceReopenReopeningANonConformanceNeedsQualityAuthority.
  ///
  /// In en, this message translates to:
  /// **'Reopening a Non-conformance needs Quality authority at its Org Unit.'**
  String get nonconformanceReopenReopeningANonConformanceNeedsQualityAuthority;

  /// No description provided for @nonconformanceReopenOnlyAClosedNonConformanceCanBe.
  ///
  /// In en, this message translates to:
  /// **'Only a closed Non-conformance can be reopened.'**
  String get nonconformanceReopenOnlyAClosedNonConformanceCanBe;

  /// No description provided for @nonconformanceReopenReopenThisNonConformance.
  ///
  /// In en, this message translates to:
  /// **'Reopen this Non-conformance'**
  String get nonconformanceReopenReopenThisNonConformance;

  /// No description provided for @nonconformanceReopenIsClosedReopeningItPutsItBack.
  ///
  /// In en, this message translates to:
  /// **'{issueNo} is closed. Reopening it puts it back to dispositioned, and its closing time goes with it.'**
  String nonconformanceReopenIsClosedReopeningItPutsItBack(Object issueNo);

  /// No description provided for @nonconformanceReopenWhyItIsBeingReopened.
  ///
  /// In en, this message translates to:
  /// **'Why it is being reopened.'**
  String get nonconformanceReopenWhyItIsBeingReopened;

  /// No description provided for @nonconformanceUpdateIsSeverityAnd.
  ///
  /// In en, this message translates to:
  /// **'{issueNo} is {value} severity and {value2}.'**
  String nonconformanceUpdateIsSeverityAnd(
    Object issueNo,
    Object value,
    Object value2,
  );

  /// No description provided for @nonconformanceUpdateThisNonConformanceIsAlreadyAtThe.
  ///
  /// In en, this message translates to:
  /// **'This Non-conformance is already at the worst severity, so there is nothing to raise it to.'**
  String get nonconformanceUpdateThisNonConformanceIsAlreadyAtThe;

  /// No description provided for @nonconformanceUpdateRaiseTheSeverityTo.
  ///
  /// In en, this message translates to:
  /// **'Raise the severity to'**
  String get nonconformanceUpdateRaiseTheSeverityTo;

  /// No description provided for @nonconformanceUpdateSeverityCanBeRaisedHereLoweringIt.
  ///
  /// In en, this message translates to:
  /// **'Severity can be raised here; lowering it is a later decision.'**
  String get nonconformanceUpdateSeverityCanBeRaisedHereLoweringIt;

  /// No description provided for @nonconformanceUpdateRecordContainment.
  ///
  /// In en, this message translates to:
  /// **'Record containment'**
  String get nonconformanceUpdateRecordContainment;

  /// No description provided for @nonconformancesNcHcm202600001.
  ///
  /// In en, this message translates to:
  /// **'NC-HCM-2026-00001'**
  String get nonconformancesNcHcm202600001;

  /// No description provided for @productFormCorrectProduct.
  ///
  /// In en, this message translates to:
  /// **'Correct Product'**
  String get productFormCorrectProduct;

  /// No description provided for @commonAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get commonAddProduct;

  /// No description provided for @productFormAProductSCodeCannotBeCorrected.
  ///
  /// In en, this message translates to:
  /// **'A Product\'s code cannot be corrected'**
  String get productFormAProductSCodeCannotBeCorrected;

  /// No description provided for @productFormAProductSUnitOfMeasureCannot.
  ///
  /// In en, this message translates to:
  /// **'A Product\'s unit of measure cannot be corrected'**
  String get productFormAProductSUnitOfMeasureCannot;

  /// No description provided for @productFormTheUnitsOfMeasureCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The units of measure could not be read'**
  String get productFormTheUnitsOfMeasureCouldNotBe;

  /// No description provided for @productsTheProductCatalogueCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Product catalogue could not be read'**
  String get productsTheProductCatalogueCouldNotBeRead;

  /// No description provided for @productsWhatThePlantMakesOneCatalogueShared.
  ///
  /// In en, this message translates to:
  /// **'What the plant makes — one catalogue shared by every Site, and what each Product is measured in.'**
  String get productsWhatThePlantMakesOneCatalogueShared;

  /// No description provided for @productsNoProductsYet.
  ///
  /// In en, this message translates to:
  /// **'No Products yet'**
  String get productsNoProductsYet;

  /// No description provided for @slideShowTheSlideShowCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The slide show could not be read'**
  String get slideShowTheSlideShowCouldNotBeRead;

  /// No description provided for @slideShowTheQualityIssuesChosenForThisSite.
  ///
  /// In en, this message translates to:
  /// **'The Quality issues chosen for this Site, one picture at a time. Choose an issue from its register or its own Screen, and set the order here.'**
  String get slideShowTheQualityIssuesChosenForThisSite;

  /// No description provided for @slideShowPauseTheShow.
  ///
  /// In en, this message translates to:
  /// **'Pause the show'**
  String get slideShowPauseTheShow;

  /// No description provided for @slideShowPlayTheShow.
  ///
  /// In en, this message translates to:
  /// **'Play the show'**
  String get slideShowPlayTheShow;

  /// No description provided for @slideShowChooseTheOrder.
  ///
  /// In en, this message translates to:
  /// **'Choose the order'**
  String get slideShowChooseTheOrder;

  /// No description provided for @slideShowNothingIsOnTheWallYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing is on the wall yet'**
  String get slideShowNothingIsOnTheWallYet;

  /// No description provided for @slideShowChooseACustomerComplaintOrANon.
  ///
  /// In en, this message translates to:
  /// **'Choose a Customer complaint or a Non-conformance in its register, and add at least one picture to it. The chosen issues appear here.'**
  String get slideShowChooseACustomerComplaintOrANon;

  /// No description provided for @slideShowChosenNoneWithAPicture.
  ///
  /// In en, this message translates to:
  /// **'{length} chosen, none with a picture'**
  String slideShowChosenNoneWithAPicture(Object length);

  /// No description provided for @slideShowASlideNeedsAPictureOpenAnd.
  ///
  /// In en, this message translates to:
  /// **'A slide needs a picture. Open {value} and add one, and {value2} will appear here.'**
  String slideShowASlideNeedsAPictureOpenAnd(Object value, Object value2);

  /// No description provided for @slideShowAPictureOf.
  ///
  /// In en, this message translates to:
  /// **'A picture of {value}'**
  String slideShowAPictureOf(Object value);

  /// No description provided for @slideShowPreviousSlide.
  ///
  /// In en, this message translates to:
  /// **'Previous slide'**
  String get slideShowPreviousSlide;

  /// No description provided for @slideShowNoSlides.
  ///
  /// In en, this message translates to:
  /// **'No slides'**
  String get slideShowNoSlides;

  /// No description provided for @slideShowNextSlide.
  ///
  /// In en, this message translates to:
  /// **'Next slide'**
  String get slideShowNextSlide;

  /// No description provided for @slideShowChosenWithoutAPicture.
  ///
  /// In en, this message translates to:
  /// **'{length} chosen without a picture'**
  String slideShowChosenWithoutAPicture(Object length);

  /// No description provided for @slideShowTheOrderTheShowPlaysIn.
  ///
  /// In en, this message translates to:
  /// **'The order the show plays in'**
  String get slideShowTheOrderTheShowPlaysIn;

  /// No description provided for @slideShowNothingIsChosenYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing is chosen yet.'**
  String get slideShowNothingIsChosenYet;

  /// No description provided for @slideShowPicture.
  ///
  /// In en, this message translates to:
  /// **'{value} picture{value2}'**
  String slideShowPicture(Object value, Object value2);

  /// No description provided for @slideShowNoPictureYetItWillNotAppear.
  ///
  /// In en, this message translates to:
  /// **'No picture yet — it will not appear until one is added'**
  String get slideShowNoPictureYetItWillNotAppear;

  /// No description provided for @slideShowMoveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get slideShowMoveEarlier;

  /// No description provided for @slideShowMoveLater.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get slideShowMoveLater;

  /// No description provided for @slideShowTakeOffTheWall.
  ///
  /// In en, this message translates to:
  /// **'Take off the wall'**
  String get slideShowTakeOffTheWall;

  /// No description provided for @slideShowToggleOnTheSlideShow.
  ///
  /// In en, this message translates to:
  /// **'On the slide show'**
  String get slideShowToggleOnTheSlideShow;

  /// No description provided for @slideShowToggleNotOnTheSlideShow.
  ///
  /// In en, this message translates to:
  /// **'Not on the slide show'**
  String get slideShowToggleNotOnTheSlideShow;

  /// No description provided for @slideShowToggleChosenIssuesPlayInTheQualitySlide.
  ///
  /// In en, this message translates to:
  /// **'Chosen issues play in the Quality slide show, one picture at a time.'**
  String get slideShowToggleChosenIssuesPlayInTheQualitySlide;

  /// No description provided for @supplierFormCorrectSupplier.
  ///
  /// In en, this message translates to:
  /// **'Correct Supplier'**
  String get supplierFormCorrectSupplier;

  /// No description provided for @commonAddSupplier.
  ///
  /// In en, this message translates to:
  /// **'Add Supplier'**
  String get commonAddSupplier;

  /// No description provided for @supplierFormASupplierSCodeCannotBeCorrected.
  ///
  /// In en, this message translates to:
  /// **'A Supplier\'s code cannot be corrected'**
  String get supplierFormASupplierSCodeCannotBeCorrected;

  /// No description provided for @supplierNcrDetailThatSupplierNcrCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That supplier NCR could not be read'**
  String get supplierNcrDetailThatSupplierNcrCouldNotBeRead;

  /// No description provided for @supplierNcrDetailBackToSupplierNcrs.
  ///
  /// In en, this message translates to:
  /// **'Back to Supplier NCRs'**
  String get supplierNcrDetailBackToSupplierNcrs;

  /// No description provided for @supplierNcrDetailNothingWasWrittenDownAboutIt.
  ///
  /// In en, this message translates to:
  /// **'Nothing was written down about it.'**
  String get supplierNcrDetailNothingWasWrittenDownAboutIt;

  /// No description provided for @supplierNcrDetailTheMaterialThisIsAbout.
  ///
  /// In en, this message translates to:
  /// **'The material this is about'**
  String get supplierNcrDetailTheMaterialThisIsAbout;

  /// No description provided for @supplierNcrDetailNothingControlsTheMaterialThisNcrIs.
  ///
  /// In en, this message translates to:
  /// **'Nothing controls the material this NCR is about yet. Record a Non-conformance from this NCR, or link one that already exists for the same lot.'**
  String get supplierNcrDetailNothingControlsTheMaterialThisNcrIs;

  /// No description provided for @supplierNcrDetailFoundAtGoodsInSoThisNcr.
  ///
  /// In en, this message translates to:
  /// **'Found at goods-in, so this NCR is where it started.'**
  String get supplierNcrDetailFoundAtGoodsInSoThisNcr;

  /// No description provided for @supplierNcrDetailRecordedAtAndLinkedToThisNcr.
  ///
  /// In en, this message translates to:
  /// **'Recorded at {value}, and linked to this NCR.'**
  String supplierNcrDetailRecordedAtAndLinkedToThisNcr(Object value);

  /// No description provided for @supplierNcrDetailTheSupplierSDisposition.
  ///
  /// In en, this message translates to:
  /// **'The Supplier\'s disposition'**
  String get supplierNcrDetailTheSupplierSDisposition;

  /// No description provided for @supplierNcrDetailNothingHasBeenRecoveredFromThisSupplier.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recovered from this Supplier.'**
  String get supplierNcrDetailNothingHasBeenRecoveredFromThisSupplier;

  /// No description provided for @supplierNcrDetailRecovered.
  ///
  /// In en, this message translates to:
  /// **'Recovered {costRecoveredLabel}.'**
  String supplierNcrDetailRecovered(Object costRecoveredLabel);

  /// No description provided for @supplierNcrDetailClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed {closedAt}'**
  String supplierNcrDetailClosed(Object closedAt);

  /// No description provided for @commonRecordTheDisposition.
  ///
  /// In en, this message translates to:
  /// **'Record the disposition'**
  String get commonRecordTheDisposition;

  /// No description provided for @supplierNcrDetailCorrectTheDisposition.
  ///
  /// In en, this message translates to:
  /// **'Correct the disposition'**
  String get supplierNcrDetailCorrectTheDisposition;

  /// No description provided for @supplierNcrDetailCloseTheNcr.
  ///
  /// In en, this message translates to:
  /// **'Close the NCR'**
  String get supplierNcrDetailCloseTheNcr;

  /// No description provided for @supplierNcrDispositionDecideTheMaterial.
  ///
  /// In en, this message translates to:
  /// **'Decide the material'**
  String get supplierNcrDispositionDecideTheMaterial;

  /// No description provided for @supplierNcrDispositionWhatHappensToThatCameFromOn.
  ///
  /// In en, this message translates to:
  /// **'What happens to {quantityLabel} that came from {supplierName} on {ncrNo}.'**
  String supplierNcrDispositionWhatHappensToThatCameFromOn(
    Object quantityLabel,
    Object supplierName,
    Object ncrNo,
  );

  /// No description provided for @supplierNcrDispositionWhatThePlantDecidedHappensToThe.
  ///
  /// In en, this message translates to:
  /// **'What the plant decided happens to the received material.'**
  String get supplierNcrDispositionWhatThePlantDecidedHappensToThe;

  /// No description provided for @supplierNcrDispositionCostRecoveredOptional.
  ///
  /// In en, this message translates to:
  /// **'Cost recovered (optional)'**
  String get supplierNcrDispositionCostRecoveredOptional;

  /// No description provided for @supplierNcrDispositionWhatWasClawedBackFromTheSupplier.
  ///
  /// In en, this message translates to:
  /// **'What was clawed back from the Supplier. Leave it blank when nothing was claimed.'**
  String get supplierNcrDispositionWhatWasClawedBackFromTheSupplier;

  /// No description provided for @supplierNcrDispositionThreeLettersTheCurrencyTheCostRecovered.
  ///
  /// In en, this message translates to:
  /// **'Three letters, the currency the cost recovered is in.'**
  String get supplierNcrDispositionThreeLettersTheCurrencyTheCostRecovered;

  /// No description provided for @commonRecordASupplierNcr.
  ///
  /// In en, this message translates to:
  /// **'Record a supplier NCR'**
  String get commonRecordASupplierNcr;

  /// No description provided for @commonSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get commonSupplier;

  /// No description provided for @supplierNcrFormProductOptional.
  ///
  /// In en, this message translates to:
  /// **'Product (optional)'**
  String get supplierNcrFormProductOptional;

  /// No description provided for @supplierNcrFormWhatTheLotIsWhenThatIs.
  ///
  /// In en, this message translates to:
  /// **'What the lot is, when that is known. A Non-conformance recorded from this NCR needs one.'**
  String get supplierNcrFormWhatTheLotIsWhenThatIs;

  /// No description provided for @supplierNcrFormNotNamedYet.
  ///
  /// In en, this message translates to:
  /// **'Not named yet'**
  String get supplierNcrFormNotNamedYet;

  /// No description provided for @supplierNcrFormWhatIsWrongWithItANon.
  ///
  /// In en, this message translates to:
  /// **'What is wrong with it. A Non-conformance recorded from this NCR carries it.'**
  String get supplierNcrFormWhatIsWrongWithItANon;

  /// No description provided for @supplierNcrFormHowMuchCameInWrong.
  ///
  /// In en, this message translates to:
  /// **'How much came in wrong.'**
  String get supplierNcrFormHowMuchCameInWrong;

  /// No description provided for @supplierNcrFormWhatTheQuantityIsCountedInTaken.
  ///
  /// In en, this message translates to:
  /// **'What the quantity is counted in. Taken from the Product when one is named.'**
  String get supplierNcrFormWhatTheQuantityIsCountedInTaken;

  /// No description provided for @supplierNcrFormIncomingLotReferenceOptional.
  ///
  /// In en, this message translates to:
  /// **'Incoming lot reference (optional)'**
  String get supplierNcrFormIncomingLotReferenceOptional;

  /// No description provided for @supplierNcrFormTheLotTheDeliveryNoteSays.
  ///
  /// In en, this message translates to:
  /// **'The lot the delivery note says.'**
  String get supplierNcrFormTheLotTheDeliveryNoteSays;

  /// No description provided for @supplierNcrFormPurchaseReferenceOptional.
  ///
  /// In en, this message translates to:
  /// **'Purchase reference (optional)'**
  String get supplierNcrFormPurchaseReferenceOptional;

  /// No description provided for @supplierNcrFormTheOrderItArrivedAgainst.
  ///
  /// In en, this message translates to:
  /// **'The order it arrived against.'**
  String get supplierNcrFormTheOrderItArrivedAgainst;

  /// No description provided for @supplierNcrFormAnswerDueOptional.
  ///
  /// In en, this message translates to:
  /// **'Answer due (optional)'**
  String get supplierNcrFormAnswerDueOptional;

  /// No description provided for @supplierNcrFormTheDayTheSupplierWasGivenTo.
  ///
  /// In en, this message translates to:
  /// **'The day the Supplier was given to answer.'**
  String get supplierNcrFormTheDayTheSupplierWasGivenTo;

  /// No description provided for @supplierNcrFormWhatIsWrongWithItOptional.
  ///
  /// In en, this message translates to:
  /// **'What is wrong with it (optional)'**
  String get supplierNcrFormWhatIsWrongWithItOptional;

  /// No description provided for @supplierNcrFormWhoWorksIt.
  ///
  /// In en, this message translates to:
  /// **'Who works it'**
  String get supplierNcrFormWhoWorksIt;

  /// No description provided for @supplierNcrFormChooseTheOrgUnitThatWillWork.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit that will work this supplier NCR. This is what decides who may act on it.'**
  String get supplierNcrFormChooseTheOrgUnitThatWillWork;

  /// No description provided for @supplierNcrFormThisSupplierNcrWillBeFiledAt.
  ///
  /// In en, this message translates to:
  /// **'This supplier NCR will be filed at {value}.'**
  String supplierNcrFormThisSupplierNcrWillBeFiledAt(Object value);

  /// No description provided for @supplierNcrLinkANonConformanceThatAlreadyExistsCan.
  ///
  /// In en, this message translates to:
  /// **'A Non-conformance that already exists{value} can be linked to this supplier NCR, instead of recording a second one for the same problem.'**
  String supplierNcrLinkANonConformanceThatAlreadyExistsCan(Object value);

  /// No description provided for @supplierNcrLinkNoNonConformanceHasBeenRecordedFor.
  ///
  /// In en, this message translates to:
  /// **'No Non-conformance has been recorded for this Product yet, so there is nothing to link. Record one from this supplier NCR instead.'**
  String get supplierNcrLinkNoNonConformanceHasBeenRecordedFor;

  /// No description provided for @supplierNcrNonconformanceControlTheMaterial.
  ///
  /// In en, this message translates to:
  /// **'Control the material'**
  String get supplierNcrNonconformanceControlTheMaterial;

  /// No description provided for @supplierNcrNonconformanceANonConformanceIsRecordedAtFound.
  ///
  /// In en, this message translates to:
  /// **'A Non-conformance is recorded at {orgUnitName}{value}, found at goods-in.'**
  String supplierNcrNonconformanceANonConformanceIsRecordedAtFound(
    Object orgUnitName,
    Object value,
  );

  /// No description provided for @supplierNcrNonconformanceHowMuchMaterialIsInQuestionIn.
  ///
  /// In en, this message translates to:
  /// **'How much material is in question, in the unit it came in.'**
  String get supplierNcrNonconformanceHowMuchMaterialIsInQuestionIn;

  /// No description provided for @supplierNcrNonconformanceTheSupplierNcrSOwnProductIs.
  ///
  /// In en, this message translates to:
  /// **'The supplier NCR\'s own Product is carried onto the record.'**
  String get supplierNcrNonconformanceTheSupplierNcrSOwnProductIs;

  /// No description provided for @supplierNcrNonconformanceTheProductsCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Products could not be read'**
  String get supplierNcrNonconformanceTheProductsCouldNotBeRead;

  /// No description provided for @supplierNcrNonconformanceThisSupplierNcrNamesNoneSoChoose.
  ///
  /// In en, this message translates to:
  /// **'This supplier NCR names none, so choose what the lot was for.'**
  String get supplierNcrNonconformanceThisSupplierNcrNamesNoneSoChoose;

  /// No description provided for @supplierNcrNonconformanceTheSupplierNcrSOwnDefectCode.
  ///
  /// In en, this message translates to:
  /// **'The supplier NCR\'s own Defect code is carried onto the record.'**
  String get supplierNcrNonconformanceTheSupplierNcrSOwnDefectCode;

  /// No description provided for @supplierNcrNonconformanceThisSupplierNcrCarriesNoneSoChoose.
  ///
  /// In en, this message translates to:
  /// **'This supplier NCR carries none, so choose the one to record it against.'**
  String get supplierNcrNonconformanceThisSupplierNcrCarriesNoneSoChoose;

  /// No description provided for @supplierNcrOrgUnitFilterChooseTheOrgUnitWhoseSupplierNcrs.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit whose supplier NCRs, and everything beneath it, you want to read — or clear back to the whole Site.'**
  String get supplierNcrOrgUnitFilterChooseTheOrgUnitWhoseSupplierNcrs;

  /// No description provided for @supplierNcrSupplierFilterFilterBySupplier.
  ///
  /// In en, this message translates to:
  /// **'Filter by Supplier'**
  String get supplierNcrSupplierFilterFilterBySupplier;

  /// No description provided for @commonAllSuppliers.
  ///
  /// In en, this message translates to:
  /// **'All Suppliers'**
  String get commonAllSuppliers;

  /// No description provided for @supplierNcrSupplierFilterChooseTheSupplierWhoseSupplierNcrsYou.
  ///
  /// In en, this message translates to:
  /// **'Choose the Supplier whose supplier NCRs you want to read, or clear back to every Supplier.'**
  String get supplierNcrSupplierFilterChooseTheSupplierWhoseSupplierNcrsYou;

  /// No description provided for @supplierNcrsTheSupplierNcrRegisterCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The supplier NCR register could not be read'**
  String get supplierNcrsTheSupplierNcrRegisterCouldNotBe;

  /// No description provided for @supplierNcrsWhatArrivedWrongFromASupplierAt.
  ///
  /// In en, this message translates to:
  /// **'What arrived wrong from a Supplier at this Site, and whether the material it came in with is under control.'**
  String get supplierNcrsWhatArrivedWrongFromASupplierAt;

  /// No description provided for @supplierNcrsThereAreMoreSupplierNcrsThanThis.
  ///
  /// In en, this message translates to:
  /// **'There are more supplier NCRs than this list shows. Narrow it by Supplier or by status to see the rest.'**
  String get supplierNcrsThereAreMoreSupplierNcrsThanThis;

  /// No description provided for @supplierNcrsTheRegisterHasSupplierNcrsButNone.
  ///
  /// In en, this message translates to:
  /// **'The register has supplier NCRs, but none of them is in the area, the Supplier or the state you picked.'**
  String get supplierNcrsTheRegisterHasSupplierNcrsButNone;

  /// No description provided for @supplierNcrsNoSupplierNcrs.
  ///
  /// In en, this message translates to:
  /// **'No supplier NCRs'**
  String get supplierNcrsNoSupplierNcrs;

  /// No description provided for @supplierNcrsNothingHasComeInWrongFromA.
  ///
  /// In en, this message translates to:
  /// **'Nothing has come in wrong from a Supplier at this Site.'**
  String get supplierNcrsNothingHasComeInWrongFromA;

  /// No description provided for @supplierNcrsNcr.
  ///
  /// In en, this message translates to:
  /// **'NCR'**
  String get supplierNcrsNcr;

  /// No description provided for @supplierNcrsSupplierAndProduct.
  ///
  /// In en, this message translates to:
  /// **'Supplier and product'**
  String get supplierNcrsSupplierAndProduct;

  /// No description provided for @supplierNcrsAnswerDue.
  ///
  /// In en, this message translates to:
  /// **'Answer due'**
  String get supplierNcrsAnswerDue;

  /// No description provided for @suppliersTheSupplierListCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Supplier list could not be read'**
  String get suppliersTheSupplierListCouldNotBeRead;

  /// No description provided for @suppliersWhoThePlantBuysFromSoAn.
  ///
  /// In en, this message translates to:
  /// **'Who the plant buys from, so an incoming lot that is wrong has someone to belong to and a claim has somewhere to go.'**
  String get suppliersWhoThePlantBuysFromSoAn;

  /// No description provided for @suppliersNoSuppliersYet.
  ///
  /// In en, this message translates to:
  /// **'No Suppliers yet'**
  String get suppliersNoSuppliersYet;

  /// No description provided for @suppliersFilterSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Filter Suppliers'**
  String get suppliersFilterSuppliers;

  /// No description provided for @suppliersNoSuppliersMatch.
  ///
  /// In en, this message translates to:
  /// **'No Suppliers match'**
  String get suppliersNoSuppliersMatch;

  /// No description provided for @bodyPartFormCorrectBodyPart.
  ///
  /// In en, this message translates to:
  /// **'Correct Body part'**
  String get bodyPartFormCorrectBodyPart;

  /// No description provided for @commonAddBodyPart.
  ///
  /// In en, this message translates to:
  /// **'Add Body part'**
  String get commonAddBodyPart;

  /// No description provided for @bodyPartFormABodyPartSCodeCannotBe.
  ///
  /// In en, this message translates to:
  /// **'A Body part\'s code cannot be corrected'**
  String get bodyPartFormABodyPartSCodeCannotBe;

  /// No description provided for @bodyPartFormRegion.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get bodyPartFormRegion;

  /// No description provided for @bodyPartFormARetiredBodyPartIsNoLonger.
  ///
  /// In en, this message translates to:
  /// **'A retired Body part is no longer offered while classifying, and stays on every incident that already names it.'**
  String get bodyPartFormARetiredBodyPartIsNoLonger;

  /// No description provided for @bodyPartsTheBodyPartCatalogueCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The Body part catalogue could not be read'**
  String get bodyPartsTheBodyPartCatalogueCouldNotBe;

  /// No description provided for @bodyPartsWhereOnTheBodyAnInjuryWas.
  ///
  /// In en, this message translates to:
  /// **'Where on the body an injury was — one catalogue shared by every Site, filed under the region each part belongs to.'**
  String get bodyPartsWhereOnTheBodyAnInjuryWas;

  /// No description provided for @bodyPartsNoBodyPartsYet.
  ///
  /// In en, this message translates to:
  /// **'No Body parts yet'**
  String get bodyPartsNoBodyPartsYet;

  /// No description provided for @commonClassifyTheInjury.
  ///
  /// In en, this message translates to:
  /// **'Classify the injury'**
  String get commonClassifyTheInjury;

  /// No description provided for @incidentClassifyClassifyingTheInjuryNeedsSafetyAuthorityAt.
  ///
  /// In en, this message translates to:
  /// **'Classifying the injury needs Safety authority at this Safety incident\'s Org Unit.'**
  String get incidentClassifyClassifyingTheInjuryNeedsSafetyAuthorityAt;

  /// No description provided for @incidentClassifySitsOnTheNoInjuryRungNobody.
  ///
  /// In en, this message translates to:
  /// **'{incidentNo} sits on the no-injury rung. Nobody was hurt, so there is nothing to classify — correct the severity first if that is wrong.'**
  String incidentClassifySitsOnTheNoInjuryRungNobody(Object incidentNo);

  /// No description provided for @incidentClassifyWhoWasHurtWhatTheInjuryWas.
  ///
  /// In en, this message translates to:
  /// **'Who was hurt, what the injury was and where on the body. These three are read only by a holder of Safety authority for this area and by the injured person\'s own Account.'**
  String get incidentClassifyWhoWasHurtWhatTheInjuryWas;

  /// No description provided for @incidentClassifySaveTheClassification.
  ///
  /// In en, this message translates to:
  /// **'Save the classification'**
  String get incidentClassifySaveTheClassification;

  /// No description provided for @commonInjuredEmployee.
  ///
  /// In en, this message translates to:
  /// **'Injured Employee'**
  String get commonInjuredEmployee;

  /// No description provided for @incidentClassifyWhoWasHurt.
  ///
  /// In en, this message translates to:
  /// **'Who was hurt.'**
  String get incidentClassifyWhoWasHurt;

  /// No description provided for @incidentClassifyClearTheInjuredEmployee.
  ///
  /// In en, this message translates to:
  /// **'Clear the injured Employee'**
  String get incidentClassifyClearTheInjuredEmployee;

  /// No description provided for @incidentClassifyTheInjuryTypeAndBodyPartCatalogues.
  ///
  /// In en, this message translates to:
  /// **'The Injury type and Body part catalogues could not be read'**
  String get incidentClassifyTheInjuryTypeAndBodyPartCatalogues;

  /// No description provided for @commonInjuryType.
  ///
  /// In en, this message translates to:
  /// **'Injury type'**
  String get commonInjuryType;

  /// No description provided for @incidentClassifyWhatTheInjuryWas.
  ///
  /// In en, this message translates to:
  /// **'What the injury was.'**
  String get incidentClassifyWhatTheInjuryWas;

  /// No description provided for @incidentClassifyClearTheInjuryType.
  ///
  /// In en, this message translates to:
  /// **'Clear the Injury type'**
  String get incidentClassifyClearTheInjuryType;

  /// No description provided for @commonBodyPart.
  ///
  /// In en, this message translates to:
  /// **'Body part'**
  String get commonBodyPart;

  /// No description provided for @incidentClassifyWhereOnTheBody.
  ///
  /// In en, this message translates to:
  /// **'Where on the body.'**
  String get incidentClassifyWhereOnTheBody;

  /// No description provided for @incidentClassifyClearTheBodyPart.
  ///
  /// In en, this message translates to:
  /// **'Clear the Body part'**
  String get incidentClassifyClearTheBodyPart;

  /// No description provided for @incidentCloseCloseThisSafetyIncident.
  ///
  /// In en, this message translates to:
  /// **'Close this Safety incident'**
  String get incidentCloseCloseThisSafetyIncident;

  /// No description provided for @incidentCloseClosingASafetyIncidentNeedsSafetyAuthority.
  ///
  /// In en, this message translates to:
  /// **'Closing a Safety incident needs Safety authority at its Org Unit.'**
  String get incidentCloseClosingASafetyIncidentNeedsSafetyAuthority;

  /// No description provided for @incidentCloseThisSafetyIncidentIsAlreadyClosed.
  ///
  /// In en, this message translates to:
  /// **'This Safety incident is already closed.'**
  String get incidentCloseThisSafetyIncidentIsAlreadyClosed;

  /// No description provided for @incidentCloseWillBeClosedAConcernRaisedFrom.
  ///
  /// In en, this message translates to:
  /// **'{incidentNo} will be closed. A Concern raised from it, if any, keeps working the cause on its own.'**
  String incidentCloseWillBeClosedAConcernRaisedFrom(Object incidentNo);

  /// No description provided for @incidentCloseLeaveItOpen.
  ///
  /// In en, this message translates to:
  /// **'Leave it open'**
  String get incidentCloseLeaveItOpen;

  /// No description provided for @commonCloseIt.
  ///
  /// In en, this message translates to:
  /// **'Close it'**
  String get commonCloseIt;

  /// No description provided for @incidentCloseWhyThisIncidentIsBeingClosed.
  ///
  /// In en, this message translates to:
  /// **'Why this incident is being closed.'**
  String get incidentCloseWhyThisIncidentIsBeingClosed;

  /// No description provided for @commonRecordTheDays.
  ///
  /// In en, this message translates to:
  /// **'Record the days'**
  String get commonRecordTheDays;

  /// No description provided for @incidentDaysRecordingTheDaysNeedsSafetyAuthorityAt.
  ///
  /// In en, this message translates to:
  /// **'Recording the days needs Safety authority at this Safety incident\'s Org Unit.'**
  String get incidentDaysRecordingTheDaysNeedsSafetyAuthorityAt;

  /// No description provided for @incidentDaysThisSafetyIncidentIsClosedItsDays.
  ///
  /// In en, this message translates to:
  /// **'This Safety incident is closed; its days cannot be changed.'**
  String get incidentDaysThisSafetyIncidentIsClosedItsDays;

  /// No description provided for @incidentDaysWhatCostZeroIsARealAnswer.
  ///
  /// In en, this message translates to:
  /// **'What {incidentNo} cost — zero is a real answer, and settles it.'**
  String incidentDaysWhatCostZeroIsARealAnswer(Object incidentNo);

  /// No description provided for @commonLostTimeDays.
  ///
  /// In en, this message translates to:
  /// **'Lost-time days'**
  String get commonLostTimeDays;

  /// No description provided for @commonRestrictedDays.
  ///
  /// In en, this message translates to:
  /// **'Restricted days'**
  String get commonRestrictedDays;

  /// No description provided for @incidentDetailNoSuchSafetyIncident.
  ///
  /// In en, this message translates to:
  /// **'No such Safety incident'**
  String get incidentDetailNoSuchSafetyIncident;

  /// No description provided for @incidentDetailBackToSafetyIncidents.
  ///
  /// In en, this message translates to:
  /// **'Back to Safety incidents'**
  String get incidentDetailBackToSafetyIncidents;

  /// No description provided for @incidentDetailTheSafetyIncidentCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Safety incident could not be read'**
  String get incidentDetailTheSafetyIncidentCouldNotBeRead;

  /// No description provided for @incidentDetailReportedAt.
  ///
  /// In en, this message translates to:
  /// **'Reported at'**
  String get incidentDetailReportedAt;

  /// No description provided for @incidentDetailImmediateAction.
  ///
  /// In en, this message translates to:
  /// **'Immediate action'**
  String get incidentDetailImmediateAction;

  /// No description provided for @commonInvestigationDueDate.
  ///
  /// In en, this message translates to:
  /// **'Investigation due date'**
  String get commonInvestigationDueDate;

  /// No description provided for @incidentDetailMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to {value}'**
  String incidentDetailMoveTo(Object value);

  /// No description provided for @commonCorrectTheSeverity.
  ///
  /// In en, this message translates to:
  /// **'Correct the severity'**
  String get commonCorrectTheSeverity;

  /// No description provided for @incidentDetailClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed {closedAt}'**
  String incidentDetailClosed(Object closedAt);

  /// No description provided for @commonInvestigationDueAt.
  ///
  /// In en, this message translates to:
  /// **'Investigation due at'**
  String get commonInvestigationDueAt;

  /// No description provided for @incidentDetailTheInjury.
  ///
  /// In en, this message translates to:
  /// **'The injury'**
  String get incidentDetailTheInjury;

  /// No description provided for @incidentDetailRestrictedVisibleToSafetyAuthorityForThis.
  ///
  /// In en, this message translates to:
  /// **'Restricted — visible to Safety authority for this area.'**
  String get incidentDetailRestrictedVisibleToSafetyAuthorityForThis;

  /// No description provided for @incidentDetailNotClassifiedYetWhoWasHurtWhat.
  ///
  /// In en, this message translates to:
  /// **'Not classified yet. Who was hurt, what the injury was and where on the body have not been recorded.'**
  String get incidentDetailNotClassifiedYetWhoWasHurtWhat;

  /// No description provided for @incidentDetailTheIncidentItselfIsRecordedHereThe.
  ///
  /// In en, this message translates to:
  /// **'The incident itself is recorded here; the cause behind it is solved in the action log, as a Concern.'**
  String get incidentDetailTheIncidentItselfIsRecordedHereThe;

  /// No description provided for @incidentDetailEventHistory.
  ///
  /// In en, this message translates to:
  /// **'Event history'**
  String get incidentDetailEventHistory;

  /// No description provided for @incidentDetailEverySeverityChangeStatusMoveDaysChange.
  ///
  /// In en, this message translates to:
  /// **'Every severity change, status move, days change, closure and classification change, kept with who and when.'**
  String get incidentDetailEverySeverityChangeStatusMoveDaysChange;

  /// No description provided for @incidentDetailNothingHasChangedAboutThisRecordSince.
  ///
  /// In en, this message translates to:
  /// **'Nothing has changed about this record since it was recorded.'**
  String get incidentDetailNothingHasChangedAboutThisRecordSince;

  /// No description provided for @incidentDueDateThisSafetyIncidentIsClosedItsInvestigation.
  ///
  /// In en, this message translates to:
  /// **'This Safety incident is closed; its investigation due date cannot be changed.'**
  String get incidentDueDateThisSafetyIncidentIsClosedItsInvestigation;

  /// No description provided for @incidentDueDateSInvestigationDeadline.
  ///
  /// In en, this message translates to:
  /// **'{incidentNo}\'s investigation deadline.'**
  String incidentDueDateSInvestigationDeadline(Object incidentNo);

  /// No description provided for @incidentFormWhatKindOfEventThisWas.
  ///
  /// In en, this message translates to:
  /// **'What kind of event this was.'**
  String get incidentFormWhatKindOfEventThisWas;

  /// No description provided for @incidentFormTheWorstActualOutcomeToAPerson.
  ///
  /// In en, this message translates to:
  /// **'The worst actual outcome to a person. Ladder order.'**
  String get incidentFormTheWorstActualOutcomeToAPerson;

  /// No description provided for @incidentFormWhatHappened.
  ///
  /// In en, this message translates to:
  /// **'What happened.'**
  String get incidentFormWhatHappened;

  /// No description provided for @incidentFormWhatWasDoneAtOnce.
  ///
  /// In en, this message translates to:
  /// **'What was done at once.'**
  String get incidentFormWhatWasDoneAtOnce;

  /// No description provided for @incidentFormInjuredEmployeeOptional.
  ///
  /// In en, this message translates to:
  /// **'Injured Employee (optional)'**
  String get incidentFormInjuredEmployeeOptional;

  /// No description provided for @incidentFormWhoWasHurtIfAnyoneReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Who was hurt, if anyone. Read only by Safety authority for this area and by the injured person\'s own Account.'**
  String get incidentFormWhoWasHurtIfAnyoneReadOnly;

  /// No description provided for @incidentFormWhenItHappenedThisIsWhatDecides.
  ///
  /// In en, this message translates to:
  /// **'When it happened. This is what decides the production day and shift it is filed against.'**
  String get incidentFormWhenItHappenedThisIsWhatDecides;

  /// No description provided for @incidentFormReportedAtOptional.
  ///
  /// In en, this message translates to:
  /// **'Reported at (optional)'**
  String get incidentFormReportedAtOptional;

  /// No description provided for @incidentFormWhenItWasReportedIfThatIs.
  ///
  /// In en, this message translates to:
  /// **'When it was reported, if that is not now.'**
  String get incidentFormWhenItWasReportedIfThatIs;

  /// No description provided for @incidentFormWhereItHappened.
  ///
  /// In en, this message translates to:
  /// **'Where it happened'**
  String get incidentFormWhereItHappened;

  /// No description provided for @incidentFormChooseTheOrgUnitTheIncidentOccurred.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit the incident occurred at. This is what decides who may act on it.'**
  String get incidentFormChooseTheOrgUnitTheIncidentOccurred;

  /// No description provided for @incidentFormThisSafetyIncidentWillBeRecordedAt.
  ///
  /// In en, this message translates to:
  /// **'This Safety incident will be recorded at {value}.'**
  String incidentFormThisSafetyIncidentWillBeRecordedAt(Object value);

  /// No description provided for @incidentFormWhichMachineIfTheIncidentWasOn.
  ///
  /// In en, this message translates to:
  /// **'Which machine, if the incident was on one. It must sit at that Org Unit.'**
  String get incidentFormWhichMachineIfTheIncidentWasOn;

  /// No description provided for @incidentRaiseConcernIsRecordedAtAndTheConcernIs.
  ///
  /// In en, this message translates to:
  /// **'{incidentNo} is recorded at {orgUnitName}, and the Concern is raised there — a problem is solved where it happened.'**
  String incidentRaiseConcernIsRecordedAtAndTheConcernIs(
    Object incidentNo,
    Object orgUnitName,
  );

  /// No description provided for @incidentRaiseConcernWhatIsTheCauseToSolve.
  ///
  /// In en, this message translates to:
  /// **'What is the cause to solve?'**
  String get incidentRaiseConcernWhatIsTheCauseToSolve;

  /// No description provided for @incidentRaiseConcernTheConcernIsReadInTheAction.
  ///
  /// In en, this message translates to:
  /// **'The Concern is read in the action log, so say the problem, not the injury.'**
  String get incidentRaiseConcernTheConcernIsReadInTheAction;

  /// No description provided for @incidentRaiseConcernOptionalTheSafetyIncidentItselfIsAlready.
  ///
  /// In en, this message translates to:
  /// **'Optional. The Safety incident itself is already linked as evidence.'**
  String get incidentRaiseConcernOptionalTheSafetyIncidentItselfIsAlready;

  /// No description provided for @incidentSeverityCorrectingTheSeverityNeedsSafetyAuthorityAt.
  ///
  /// In en, this message translates to:
  /// **'Correcting the severity needs Safety authority at this Safety incident\'s Org Unit.'**
  String get incidentSeverityCorrectingTheSeverityNeedsSafetyAuthorityAt;

  /// No description provided for @incidentSeverityIsCorrectingItRestatesThePeriodIt.
  ///
  /// In en, this message translates to:
  /// **'{incidentNo} is {value}. Correcting it restates the period it occurred in.'**
  String incidentSeverityIsCorrectingItRestatesThePeriodIt(
    Object incidentNo,
    Object value,
  );

  /// No description provided for @incidentSeverityCorrectIt.
  ///
  /// In en, this message translates to:
  /// **'Correct it'**
  String get incidentSeverityCorrectIt;

  /// No description provided for @incidentSeverityCorrectTheSeverityTo.
  ///
  /// In en, this message translates to:
  /// **'Correct the severity to'**
  String get incidentSeverityCorrectTheSeverityTo;

  /// No description provided for @incidentSeverityWhyTheSeverityIsBeingCorrected.
  ///
  /// In en, this message translates to:
  /// **'Why the severity is being corrected.'**
  String get incidentSeverityWhyTheSeverityIsBeingCorrected;

  /// No description provided for @incidentStatusMoveTheStatus.
  ///
  /// In en, this message translates to:
  /// **'Move the status'**
  String get incidentStatusMoveTheStatus;

  /// No description provided for @incidentStatusThisSafetyIncidentIsClosedItsStatus.
  ///
  /// In en, this message translates to:
  /// **'This Safety incident is closed; its status cannot be moved.'**
  String get incidentStatusThisSafetyIncidentIsClosedItsStatus;

  /// No description provided for @incidentStatusThisSafetyIncidentIsAlreadyOnlyClosing.
  ///
  /// In en, this message translates to:
  /// **'This Safety incident is already {value}; only closing moves it further.'**
  String incidentStatusThisSafetyIncidentIsAlreadyOnlyClosing(Object value);

  /// No description provided for @incidentStatusMovesFromTo.
  ///
  /// In en, this message translates to:
  /// **'{incidentNo} moves from {statusLabel} to {value}.'**
  String incidentStatusMovesFromTo(
    Object incidentNo,
    Object statusLabel,
    Object value,
  );

  /// No description provided for @incidentStatusMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to {value}'**
  String incidentStatusMoveTo(Object value);

  /// No description provided for @incidents1SafetyIncident.
  ///
  /// In en, this message translates to:
  /// **'1 Safety incident'**
  String get incidents1SafetyIncident;

  /// No description provided for @incidentsSafetyIncidents.
  ///
  /// In en, this message translates to:
  /// **'{length} Safety incidents'**
  String incidentsSafetyIncidents(Object length);

  /// No description provided for @incidentsSiHcm202600001.
  ///
  /// In en, this message translates to:
  /// **'SI-HCM-2026-00001'**
  String get incidentsSiHcm202600001;

  /// No description provided for @injuryTypeFormCorrectInjuryType.
  ///
  /// In en, this message translates to:
  /// **'Correct Injury type'**
  String get injuryTypeFormCorrectInjuryType;

  /// No description provided for @commonAddInjuryType.
  ///
  /// In en, this message translates to:
  /// **'Add Injury type'**
  String get commonAddInjuryType;

  /// No description provided for @injuryTypeFormAnInjuryTypeSCodeCannotBe.
  ///
  /// In en, this message translates to:
  /// **'An Injury type\'s code cannot be corrected'**
  String get injuryTypeFormAnInjuryTypeSCodeCannotBe;

  /// No description provided for @injuryTypeFormARetiredInjuryTypeIsNoLonger.
  ///
  /// In en, this message translates to:
  /// **'A retired Injury type is no longer offered while classifying, and stays on every incident that already names it.'**
  String get injuryTypeFormARetiredInjuryTypeIsNoLonger;

  /// No description provided for @injuryTypesTheInjuryTypeCatalogueCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The Injury type catalogue could not be read'**
  String get injuryTypesTheInjuryTypeCatalogueCouldNotBe;

  /// No description provided for @injuryTypesWhatAnInjuryWasOneCatalogueShared.
  ///
  /// In en, this message translates to:
  /// **'What an injury was — one catalogue shared by every Site, and what a Safety incident is classified against.'**
  String get injuryTypesWhatAnInjuryWasOneCatalogueShared;

  /// No description provided for @injuryTypesNoInjuryTypesYet.
  ///
  /// In en, this message translates to:
  /// **'No Injury types yet'**
  String get injuryTypesNoInjuryTypesYet;

  /// No description provided for @observationDetailNoSuchSafetyObservation.
  ///
  /// In en, this message translates to:
  /// **'No such Safety observation'**
  String get observationDetailNoSuchSafetyObservation;

  /// No description provided for @observationDetailBackToSafetyObservations.
  ///
  /// In en, this message translates to:
  /// **'Back to Safety observations'**
  String get observationDetailBackToSafetyObservations;

  /// No description provided for @observationDetailTheSafetyObservationCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Safety observation could not be read'**
  String get observationDetailTheSafetyObservationCouldNotBeRead;

  /// No description provided for @observationDetailActionTaken.
  ///
  /// In en, this message translates to:
  /// **'Action taken'**
  String get observationDetailActionTaken;

  /// No description provided for @observationDetailRecordedBy.
  ///
  /// In en, this message translates to:
  /// **'Recorded by'**
  String get observationDetailRecordedBy;

  /// No description provided for @observationDetailObservedAt.
  ///
  /// In en, this message translates to:
  /// **'Observed at'**
  String get observationDetailObservedAt;

  /// No description provided for @observationDetailClosingTheLoop.
  ///
  /// In en, this message translates to:
  /// **'Closing the loop'**
  String get observationDetailClosingTheLoop;

  /// No description provided for @observationDetailTheObservationItselfIsRecordedHereWhat.
  ///
  /// In en, this message translates to:
  /// **'The observation itself is recorded here; what somebody does about it is owned in the action log, as an Action.'**
  String get observationDetailTheObservationItselfIsRecordedHereWhat;

  /// No description provided for @observationDetailNothingIsBeingDoneAboutThisYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing is being done about this yet.'**
  String get observationDetailNothingIsBeingDoneAboutThisYet;

  /// No description provided for @commonRaiseAnAction.
  ///
  /// In en, this message translates to:
  /// **'Raise an Action'**
  String get commonRaiseAnAction;

  /// No description provided for @observationFormASafeActAnUnsafeActOr.
  ///
  /// In en, this message translates to:
  /// **'A safe act, an unsafe act, or an unsafe condition.'**
  String get observationFormASafeActAnUnsafeActOr;

  /// No description provided for @observationFormTheWorstCredibleOutcomeNotWhatActually.
  ///
  /// In en, this message translates to:
  /// **'The worst credible outcome, not what actually happened.'**
  String get observationFormTheWorstCredibleOutcomeNotWhatActually;

  /// No description provided for @observationFormWhatWasSeen.
  ///
  /// In en, this message translates to:
  /// **'What was seen.'**
  String get observationFormWhatWasSeen;

  /// No description provided for @observationFormWhatWasDoneOnTheSpot.
  ///
  /// In en, this message translates to:
  /// **'What was done on the spot.'**
  String get observationFormWhatWasDoneOnTheSpot;

  /// No description provided for @observationFormRareAndTheSingleStrongestSignalThat.
  ///
  /// In en, this message translates to:
  /// **'Rare, and the single strongest signal that the safety culture is real.'**
  String get observationFormRareAndTheSingleStrongestSignalThat;

  /// No description provided for @observationFormObservedAtOptional.
  ///
  /// In en, this message translates to:
  /// **'Observed at (optional)'**
  String get observationFormObservedAtOptional;

  /// No description provided for @observationFormWhenItWasSeenIfNotNow.
  ///
  /// In en, this message translates to:
  /// **'When it was seen, if not now. This is what decides the production day and shift it is filed against.'**
  String get observationFormWhenItWasSeenIfNotNow;

  /// No description provided for @observationFormWhereItWasSeen.
  ///
  /// In en, this message translates to:
  /// **'Where it was seen'**
  String get observationFormWhereItWasSeen;

  /// No description provided for @observationFormChooseTheOrgUnitTheObservationWas.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit the observation was made at. This is what decides who may act on it.'**
  String get observationFormChooseTheOrgUnitTheObservationWas;

  /// No description provided for @observationFormThisSafetyObservationWillBeRecordedAt.
  ///
  /// In en, this message translates to:
  /// **'This Safety observation will be recorded at {value}.'**
  String observationFormThisSafetyObservationWillBeRecordedAt(Object value);

  /// No description provided for @observationRaiseActionThisObservationIsRecordedAtAndThe.
  ///
  /// In en, this message translates to:
  /// **'This observation is recorded at {orgUnitName}, and the Action is raised there — a problem is owned where it was seen.'**
  String observationRaiseActionThisObservationIsRecordedAtAndThe(
    Object orgUnitName,
  );

  /// No description provided for @observationRaiseActionChooseWhatThisIs.
  ///
  /// In en, this message translates to:
  /// **'Choose what this is.'**
  String get observationRaiseActionChooseWhatThisIs;

  /// No description provided for @observationRaiseActionChooseAKind.
  ///
  /// In en, this message translates to:
  /// **'Choose a kind'**
  String get observationRaiseActionChooseAKind;

  /// No description provided for @observationRaiseActionWhatNeedsDoing.
  ///
  /// In en, this message translates to:
  /// **'What needs doing?'**
  String get observationRaiseActionWhatNeedsDoing;

  /// No description provided for @observationRaiseActionTheActionIsReadInTheAction.
  ///
  /// In en, this message translates to:
  /// **'The Action is read in the action log, so say the work, not the observation.'**
  String get observationRaiseActionTheActionIsReadInTheAction;

  /// No description provided for @observationRaiseActionOptionalTheSafetyObservationItselfIsAlready.
  ///
  /// In en, this message translates to:
  /// **'Optional. The Safety observation itself is already linked as evidence.'**
  String get observationRaiseActionOptionalTheSafetyObservationItselfIsAlready;

  /// No description provided for @observations1SafetyObservation.
  ///
  /// In en, this message translates to:
  /// **'1 Safety observation'**
  String get observations1SafetyObservation;

  /// No description provided for @observationsSafetyObservations.
  ///
  /// In en, this message translates to:
  /// **'{length} Safety observations'**
  String observationsSafetyObservations(Object length);

  /// No description provided for @safetyIncidentRecordable.
  ///
  /// In en, this message translates to:
  /// **'{value} · recordable'**
  String safetyIncidentRecordable(Object value);

  /// No description provided for @safetyObservationOrgUnitFilterChooseTheOrgUnitWhoseSafetyObservations.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit whose Safety observations and everything beneath it you want to read, or clear back to the whole Site.'**
  String
  get safetyObservationOrgUnitFilterChooseTheOrgUnitWhoseSafetyObservations;

  /// No description provided for @safetyOrgUnitFilterChooseTheOrgUnitWhoseSafetyIncidents.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit whose Safety incidents and everything beneath it you want to read, or clear back to the whole Site.'**
  String get safetyOrgUnitFilterChooseTheOrgUnitWhoseSafetyIncidents;

  /// No description provided for @handoverAcknowledgeYouAreAcceptingAndTheShift.
  ///
  /// In en, this message translates to:
  /// **'You are accepting {value} and the shift{value2}.'**
  String handoverAcknowledgeYouAreAcceptingAndTheShift(
    Object value,
    Object value2,
  );

  /// No description provided for @handoverAcknowledgeTheOutgoingShiftDeclaredNoChangePoints.
  ///
  /// In en, this message translates to:
  /// **'The outgoing shift declared no change points.'**
  String get handoverAcknowledgeTheOutgoingShiftDeclaredNoChangePoints;

  /// No description provided for @handoverAcknowledgeThereAreNoChangePointsToWatch.
  ///
  /// In en, this message translates to:
  /// **'There are no change points to watch.'**
  String get handoverAcknowledgeThereAreNoChangePointsToWatch;

  /// No description provided for @handoverAcknowledgeWhatEachWatchShowed.
  ///
  /// In en, this message translates to:
  /// **'What each watch showed'**
  String get handoverAcknowledgeWhatEachWatchShowed;

  /// No description provided for @handoverAcknowledgeWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch: {watchNote}'**
  String handoverAcknowledgeWatch(Object watchNote);

  /// No description provided for @handoverAcknowledgeFound.
  ///
  /// In en, this message translates to:
  /// **'Found'**
  String get handoverAcknowledgeFound;

  /// No description provided for @handoverAcknowledgeNotAnswered.
  ///
  /// In en, this message translates to:
  /// **'Not answered'**
  String get handoverAcknowledgeNotAnswered;

  /// No description provided for @handoverAcknowledgeNoteOnTheHandoverOptional.
  ///
  /// In en, this message translates to:
  /// **'Note on the handover (optional)'**
  String get handoverAcknowledgeNoteOnTheHandoverOptional;

  /// No description provided for @handoverAcknowledgeAcknowledgeTheHandover.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge the handover'**
  String get handoverAcknowledgeAcknowledgeTheHandover;

  /// No description provided for @handoverAcknowledgeAcknowledging.
  ///
  /// In en, this message translates to:
  /// **'Acknowledging…'**
  String get handoverAcknowledgeAcknowledging;

  /// No description provided for @commonAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge'**
  String get commonAcknowledge;

  /// No description provided for @sectionThatSectionSDayCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'That Section\'s day could not be read'**
  String get sectionThatSectionSDayCouldNotBe;

  /// No description provided for @sectionChooseAnotherSection.
  ///
  /// In en, this message translates to:
  /// **'Choose another Section'**
  String get sectionChooseAnotherSection;

  /// No description provided for @sectionEveryShiftOfTheProductionDayWith.
  ///
  /// In en, this message translates to:
  /// **'Every shift of the production day, with its handover and what is still open at each shift boundary.'**
  String get sectionEveryShiftOfTheProductionDayWith;

  /// No description provided for @sectionNoShiftsScheduled.
  ///
  /// In en, this message translates to:
  /// **'No shifts scheduled'**
  String get sectionNoShiftsScheduled;

  /// No description provided for @sectionNoShiftsAreScheduledAtThisSection.
  ///
  /// In en, this message translates to:
  /// **'No shifts are scheduled at this Section on that day.'**
  String get sectionNoShiftsAreScheduledAtThisSection;

  /// No description provided for @sectionShift.
  ///
  /// In en, this message translates to:
  /// **'Shift {value}–{value2}'**
  String sectionShift(Object value, Object value2);

  /// No description provided for @commonLate.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get commonLate;

  /// No description provided for @sectionHandedOverBy.
  ///
  /// In en, this message translates to:
  /// **'Handed over by {value}'**
  String sectionHandedOverBy(Object value);

  /// No description provided for @sectionAcknowledgedAfterTheShiftBegan.
  ///
  /// In en, this message translates to:
  /// **'acknowledged {value} after the shift began'**
  String sectionAcknowledgedAfterTheShiftBegan(Object value);

  /// No description provided for @sectionThatSectionTreeCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'That Section tree could not be read'**
  String get sectionThatSectionTreeCouldNotBeRead;

  /// No description provided for @sectionNothingToOpenHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing to open here'**
  String get sectionNothingToOpenHere;

  /// No description provided for @sectionChooseASectionToOpenItsBoard.
  ///
  /// In en, this message translates to:
  /// **'Choose a Section to open its board: the day\'s shifts and the handover at each.'**
  String get sectionChooseASectionToOpenItsBoard;

  /// No description provided for @shiftHandoverThatHandoverCouldNotBeOpened.
  ///
  /// In en, this message translates to:
  /// **'That handover could not be opened'**
  String get shiftHandoverThatHandoverCouldNotBeOpened;

  /// No description provided for @shiftHandoverSubmitTheHandover.
  ///
  /// In en, this message translates to:
  /// **'Submit the handover'**
  String get shiftHandoverSubmitTheHandover;

  /// No description provided for @shiftHandoverBackToTheSectionBoard.
  ///
  /// In en, this message translates to:
  /// **'Back to the Section board'**
  String get shiftHandoverBackToTheSectionBoard;

  /// What a Shift handover's title reads when the record names no Section.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get shiftHandoverSection;

  /// The tail of a Shift handover's header line: who signed it over.
  ///
  /// In en, this message translates to:
  /// **'handed over by {authorDisplayName}'**
  String shiftHandoverHandedOverBy(Object authorDisplayName);

  /// No description provided for @shiftHandoverShiftHandover.
  ///
  /// In en, this message translates to:
  /// **'Shift handover · {value}'**
  String shiftHandoverShiftHandover(Object value);

  /// No description provided for @shiftHandoverVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String shiftHandoverVersion(Object version);

  /// No description provided for @shiftHandoverTheNumbersTheShiftClosedOn.
  ///
  /// In en, this message translates to:
  /// **'The numbers the shift closed on'**
  String get shiftHandoverTheNumbersTheShiftClosedOn;

  /// No description provided for @shiftHandoverFrozenWhenTheHandoverIsSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Frozen when the handover is submitted.'**
  String get shiftHandoverFrozenWhenTheHandoverIsSubmitted;

  /// No description provided for @shiftHandoverFrozenAtSubmit.
  ///
  /// In en, this message translates to:
  /// **'Frozen at submit.'**
  String get shiftHandoverFrozenAtSubmit;

  /// No description provided for @shiftHandoverMachines.
  ///
  /// In en, this message translates to:
  /// **'Machines'**
  String get shiftHandoverMachines;

  /// No description provided for @shiftHandoverOneLinePerAssetInTheSection.
  ///
  /// In en, this message translates to:
  /// **'One line per Asset in the Section.'**
  String get shiftHandoverOneLinePerAssetInTheSection;

  /// No description provided for @shiftHandoverThisSectionHasNoActiveAssets.
  ///
  /// In en, this message translates to:
  /// **'This Section has no active Assets.'**
  String get shiftHandoverThisSectionHasNoActiveAssets;

  /// No description provided for @shiftHandoverChangePoints.
  ///
  /// In en, this message translates to:
  /// **'Change points'**
  String get shiftHandoverChangePoints;

  /// No description provided for @shiftHandoverWhatTheIncomingShiftWillMeetThat.
  ///
  /// In en, this message translates to:
  /// **'What the incoming shift will meet that differs, and what to watch.'**
  String get shiftHandoverWhatTheIncomingShiftWillMeetThat;

  /// No description provided for @shiftHandoverCarriedActions.
  ///
  /// In en, this message translates to:
  /// **'Carried actions'**
  String get shiftHandoverCarriedActions;

  /// No description provided for @shiftHandoverEveryOpenActionOfTheSectionIs.
  ///
  /// In en, this message translates to:
  /// **'Every open Action of the Section is carried, reassigned or closed.'**
  String get shiftHandoverEveryOpenActionOfTheSectionIs;

  /// No description provided for @shiftHandoverHandoverEvidence.
  ///
  /// In en, this message translates to:
  /// **'Handover evidence'**
  String get shiftHandoverHandoverEvidence;

  /// No description provided for @shiftHandoverAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged {value}{value2}'**
  String shiftHandoverAcknowledged(Object value, Object value2);

  /// No description provided for @shiftHandoverThisHandoverCannotBeSubmittedYet.
  ///
  /// In en, this message translates to:
  /// **'This handover cannot be submitted yet'**
  String get shiftHandoverThisHandoverCannotBeSubmittedYet;

  /// No description provided for @shiftHandoverNoLineYet.
  ///
  /// In en, this message translates to:
  /// **'No line yet'**
  String get shiftHandoverNoLineYet;

  /// No description provided for @shiftHandoverAbnormality.
  ///
  /// In en, this message translates to:
  /// **'Abnormality'**
  String get shiftHandoverAbnormality;

  /// No description provided for @shiftHandoverNoneFound.
  ///
  /// In en, this message translates to:
  /// **'None found'**
  String get shiftHandoverNoneFound;

  /// No description provided for @shiftHandoverRequiredSayWhyItIsNotRunning.
  ///
  /// In en, this message translates to:
  /// **'Required: say why it is not running normally'**
  String get shiftHandoverRequiredSayWhyItIsNotRunning;

  /// No description provided for @shiftHandoverWhatTheIncomingShiftMustWatch.
  ///
  /// In en, this message translates to:
  /// **'What the incoming shift must watch'**
  String get shiftHandoverWhatTheIncomingShiftMustWatch;

  /// No description provided for @shiftHandoverWalked.
  ///
  /// In en, this message translates to:
  /// **'Walked'**
  String get shiftHandoverWalked;

  /// No description provided for @shiftHandoverSaveLine.
  ///
  /// In en, this message translates to:
  /// **'Save line'**
  String get shiftHandoverSaveLine;

  /// No description provided for @shiftHandoverRecordLine.
  ///
  /// In en, this message translates to:
  /// **'Record line'**
  String get shiftHandoverRecordLine;

  /// No description provided for @shiftHandoverNoChangePointsThisShift.
  ///
  /// In en, this message translates to:
  /// **'No change points this shift'**
  String get shiftHandoverNoChangePointsThisShift;

  /// No description provided for @shiftHandoverNoneRecorded.
  ///
  /// In en, this message translates to:
  /// **'None recorded'**
  String get shiftHandoverNoneRecorded;

  /// No description provided for @shiftHandoverWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch: {watchNote}{value}'**
  String shiftHandoverWatch(Object watchNote, Object value);

  /// No description provided for @shiftHandoverAddAChangePoint.
  ///
  /// In en, this message translates to:
  /// **'Add a change point'**
  String get shiftHandoverAddAChangePoint;

  /// No description provided for @shiftHandoverDimension.
  ///
  /// In en, this message translates to:
  /// **'Dimension'**
  String get shiftHandoverDimension;

  /// No description provided for @shiftHandoverWhatIsDifferent.
  ///
  /// In en, this message translates to:
  /// **'What is different'**
  String get shiftHandoverWhatIsDifferent;

  /// No description provided for @shiftHandoverWhatTheIncomingShiftMustWatchFor.
  ///
  /// In en, this message translates to:
  /// **'What the incoming shift must watch for'**
  String get shiftHandoverWhatTheIncomingShiftMustWatchFor;

  /// No description provided for @shiftHandoverAddChangePoint.
  ///
  /// In en, this message translates to:
  /// **'Add change point'**
  String get shiftHandoverAddChangePoint;

  /// No description provided for @shiftHandoverTheSectionHasNoOpenActionsTo.
  ///
  /// In en, this message translates to:
  /// **'The Section has no open Actions to hand over.'**
  String get shiftHandoverTheSectionHasNoOpenActionsTo;

  /// No description provided for @shiftHandoverOld.
  ///
  /// In en, this message translates to:
  /// **'{value} {value2} old'**
  String shiftHandoverOld(Object value, Object value2);

  /// No description provided for @shiftHandoverOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner {ownerName}'**
  String shiftHandoverOwner(Object ownerName);

  /// No description provided for @shiftHandoverNoDispositionYet.
  ///
  /// In en, this message translates to:
  /// **'no disposition yet'**
  String get shiftHandoverNoDispositionYet;

  /// No description provided for @shiftHandoverNewOwner.
  ///
  /// In en, this message translates to:
  /// **'New owner'**
  String get shiftHandoverNewOwner;

  /// No description provided for @shiftHandoverWhatClosedIt.
  ///
  /// In en, this message translates to:
  /// **'What closed it'**
  String get shiftHandoverWhatClosedIt;

  /// No description provided for @shiftHandoverRecordDisposition.
  ///
  /// In en, this message translates to:
  /// **'Record disposition'**
  String get shiftHandoverRecordDisposition;

  /// No description provided for @shiftHandoverJointWalkDone.
  ///
  /// In en, this message translates to:
  /// **'Joint walk done'**
  String get shiftHandoverJointWalkDone;

  /// No description provided for @shiftHandoverCriticalItems.
  ///
  /// In en, this message translates to:
  /// **'Critical items'**
  String get shiftHandoverCriticalItems;

  /// No description provided for @shiftHandoverDeviationFromTheStandardHandover.
  ///
  /// In en, this message translates to:
  /// **'Deviation from the standard handover'**
  String get shiftHandoverDeviationFromTheStandardHandover;

  /// No description provided for @shiftHandoverSaveEvidence.
  ///
  /// In en, this message translates to:
  /// **'Save evidence'**
  String get shiftHandoverSaveEvidence;

  /// No description provided for @commonAddKpi.
  ///
  /// In en, this message translates to:
  /// **'Add KPI'**
  String get commonAddKpi;

  /// No description provided for @addKpiAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addKpiAdd;

  /// No description provided for @addKpiKpi.
  ///
  /// In en, this message translates to:
  /// **'KPI'**
  String get addKpiKpi;

  /// No description provided for @addKpiTheCodeEGOee.
  ///
  /// In en, this message translates to:
  /// **'The code, e.g. OEE'**
  String get addKpiTheCodeEGOee;

  /// No description provided for @addKpiUnitOptional.
  ///
  /// In en, this message translates to:
  /// **'Unit (optional)'**
  String get addKpiUnitOptional;

  /// No description provided for @addKpiDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get addKpiDirection;

  /// No description provided for @addKpiIsMetAtOrAboveTheTarget.
  ///
  /// In en, this message translates to:
  /// **'>= is met at or above the Target, <= at or below it'**
  String get addKpiIsMetAtOrAboveTheTarget;

  /// No description provided for @addKpiDecimals.
  ///
  /// In en, this message translates to:
  /// **'Decimals'**
  String get addKpiDecimals;

  /// No description provided for @addKpiAWholeNumberFrom0To6.
  ///
  /// In en, this message translates to:
  /// **'A whole number from 0 to 6'**
  String get addKpiAWholeNumberFrom0To6;

  /// No description provided for @addKpiDecimalsMustBeAWholeNumberFrom.
  ///
  /// In en, this message translates to:
  /// **'Decimals must be a whole number from 0 to 6'**
  String get addKpiDecimalsMustBeAWholeNumberFrom;

  /// No description provided for @addKpiValueMeasureOptional.
  ///
  /// In en, this message translates to:
  /// **'Value measure (optional)'**
  String get addKpiValueMeasureOptional;

  /// No description provided for @commonChangeTarget.
  ///
  /// In en, this message translates to:
  /// **'Change Target'**
  String get commonChangeTarget;

  /// No description provided for @changeTargetGrain.
  ///
  /// In en, this message translates to:
  /// **'Grain'**
  String get changeTargetGrain;

  /// No description provided for @changeTargetValidFrom.
  ///
  /// In en, this message translates to:
  /// **'Valid from'**
  String get changeTargetValidFrom;

  /// No description provided for @changeTargetTodayAtThisSiteIsATarget.
  ///
  /// In en, this message translates to:
  /// **'Today at this Site is {siteToday}; a Target starts today or later.'**
  String changeTargetTodayAtThisSiteIsATarget(Object siteToday);

  /// No description provided for @changeTargetTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get changeTargetTarget;

  /// No description provided for @changeTargetLeaveBlankForNoTargetFromThat.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for no target from that date on.'**
  String get changeTargetLeaveBlankForNoTargetFromThat;

  /// No description provided for @changeTargetTheTargetMustBeANumberOr.
  ///
  /// In en, this message translates to:
  /// **'The Target must be a number, or blank for no target'**
  String get changeTargetTheTargetMustBeANumberOr;

  /// No description provided for @kpiCatalogueTheKpiCatalogueCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The KPI catalogue could not be read'**
  String get kpiCatalogueTheKpiCatalogueCouldNotBeRead;

  /// No description provided for @kpiCatalogueTheKpisOfTheMtuLineWith.
  ///
  /// In en, this message translates to:
  /// **'The KPIs of the MTU line, with the Target in force per grain.'**
  String get kpiCatalogueTheKpisOfTheMtuLineWith;

  /// No description provided for @kpiCatalogueTheKpisOfTheMtuLineWith2.
  ///
  /// In en, this message translates to:
  /// **'The KPIs of the MTU line, with the Target in force per grain and the review state for today, {reviewDate}.'**
  String kpiCatalogueTheKpisOfTheMtuLineWith2(Object reviewDate);

  /// No description provided for @kpiCatalogueNoKpisInTheCatalogueYet.
  ///
  /// In en, this message translates to:
  /// **'No KPIs in the catalogue yet'**
  String get kpiCatalogueNoKpisInTheCatalogueYet;

  /// No description provided for @kpiCatalogueNothingHasBeenAddedToTheKpi.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been added to the KPI catalogue.'**
  String get kpiCatalogueNothingHasBeenAddedToTheKpi;

  /// No description provided for @commonFilterKpis.
  ///
  /// In en, this message translates to:
  /// **'Filter KPIs'**
  String get commonFilterKpis;

  /// No description provided for @kpiCatalogueByCodeOrTitle.
  ///
  /// In en, this message translates to:
  /// **'By code or title.'**
  String get kpiCatalogueByCodeOrTitle;

  /// No description provided for @commonNoKpisMatch.
  ///
  /// In en, this message translates to:
  /// **'No KPIs match'**
  String get commonNoKpisMatch;

  /// No description provided for @kpiCatalogueNothingInTheCatalogueMatchesTryA.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the catalogue matches \"{term}\". Try a different code or title, or clear the filter.'**
  String kpiCatalogueNothingInTheCatalogueMatchesTryA(Object term);

  /// No description provided for @kpiCatalogueValueMeasure.
  ///
  /// In en, this message translates to:
  /// **'Value measure: {measure}'**
  String kpiCatalogueValueMeasure(Object measure);

  /// No description provided for @kpiReviewTheKpiReviewCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The KPI Review could not be read'**
  String get kpiReviewTheKpiReviewCouldNotBeRead;

  /// No description provided for @kpiReviewKpiReview.
  ///
  /// In en, this message translates to:
  /// **'KPI Review'**
  String get kpiReviewKpiReview;

  /// No description provided for @kpiReviewKpiReviewFor.
  ///
  /// In en, this message translates to:
  /// **'KPI Review for {reviewDate}'**
  String kpiReviewKpiReviewFor(Object reviewDate);

  /// No description provided for @kpiReviewJudgeEachKpiOfTheMtuLine.
  ///
  /// In en, this message translates to:
  /// **'Judge each KPI of the MTU line against its Daily Target: met, missed or not measured.'**
  String get kpiReviewJudgeEachKpiOfTheMtuLine;

  /// No description provided for @kpiReviewNoKpisToReview.
  ///
  /// In en, this message translates to:
  /// **'No KPIs to review'**
  String get kpiReviewNoKpisToReview;

  /// No description provided for @kpiReviewTheKpiCatalogueHasNoKpiYet.
  ///
  /// In en, this message translates to:
  /// **'The KPI catalogue has no KPI yet.'**
  String get kpiReviewTheKpiCatalogueHasNoKpiYet;

  /// No description provided for @kpiReviewByTitle.
  ///
  /// In en, this message translates to:
  /// **'By title.'**
  String get kpiReviewByTitle;

  /// No description provided for @kpiReviewNoKpiOfTheReviewMatchesTry.
  ///
  /// In en, this message translates to:
  /// **'No KPI of the review matches \"{term}\". Try a different title, or clear the filter.'**
  String kpiReviewNoKpiOfTheReviewMatchesTry(Object term);

  /// No description provided for @kpiReview1ChangedKpiIsHiddenByThe.
  ///
  /// In en, this message translates to:
  /// **'1 changed KPI is hidden by the search.'**
  String get kpiReview1ChangedKpiIsHiddenByThe;

  /// No description provided for @kpiReviewChangedKpisAreHiddenByTheSearch.
  ///
  /// In en, this message translates to:
  /// **'{hiddenChanges} changed KPIs are hidden by the search.'**
  String kpiReviewChangedKpisAreHiddenByTheSearch(Object hiddenChanges);

  /// No description provided for @kpiReviewSavedFor.
  ///
  /// In en, this message translates to:
  /// **'Saved {savedCount} {value} for {reviewDate}.'**
  String kpiReviewSavedFor(Object savedCount, Object value, Object reviewDate);

  /// No description provided for @kpiReviewNoTarget.
  ///
  /// In en, this message translates to:
  /// **'No target'**
  String get kpiReviewNoTarget;

  /// No description provided for @kpiReviewDailyTarget.
  ///
  /// In en, this message translates to:
  /// **'Daily target: {targetText}'**
  String kpiReviewDailyTarget(Object targetText);

  /// No description provided for @kpiReviewReadTheNote.
  ///
  /// In en, this message translates to:
  /// **'Read the note'**
  String get kpiReviewReadTheNote;

  /// No description provided for @kpiReviewWhyWasItMissed.
  ///
  /// In en, this message translates to:
  /// **'Why was it missed?'**
  String get kpiReviewWhyWasItMissed;

  /// No description provided for @kpiReviewWhyWasTheTargetMissed.
  ///
  /// In en, this message translates to:
  /// **'Why was the Target ({targetText}) missed?'**
  String kpiReviewWhyWasTheTargetMissed(Object targetText);

  /// No description provided for @kpiReviewANoteOfAtLeastCharactersIs.
  ///
  /// In en, this message translates to:
  /// **'A note of at least {minNoteLength} characters is required when a KPI is missed ({length} so far).'**
  String kpiReviewANoteOfAtLeastCharactersIs(
    Object minNoteLength,
    Object length,
  );

  /// No description provided for @kpiReviewEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get kpiReviewEdit;

  /// No description provided for @kpiTargetsTheTargetsCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Targets could not be read'**
  String get kpiTargetsTheTargetsCouldNotBeRead;

  /// No description provided for @kpiTargetsKpiTargets.
  ///
  /// In en, this message translates to:
  /// **'KPI Targets, {direction} {unit}'**
  String kpiTargetsKpiTargets(Object direction, Object unit);

  /// No description provided for @kpiTargetsCurrentlyInForce.
  ///
  /// In en, this message translates to:
  /// **'Currently in force'**
  String get kpiTargetsCurrentlyInForce;

  /// No description provided for @kpiTargetsWhatEachGrainIsJudgedAgainstToday.
  ///
  /// In en, this message translates to:
  /// **'What each grain is judged against today, and from when.'**
  String get kpiTargetsWhatEachGrainIsJudgedAgainstToday;

  /// No description provided for @kpiTargetsNoTargetIsInForceToday.
  ///
  /// In en, this message translates to:
  /// **'No Target is in force today.'**
  String get kpiTargetsNoTargetIsInForceToday;

  /// No description provided for @kpiTargetsFrom.
  ///
  /// In en, this message translates to:
  /// **'{grain}: {value} (from {validFrom})'**
  String kpiTargetsFrom(Object grain, Object value, Object validFrom);

  /// No description provided for @kpiTargetsHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get kpiTargetsHistory;

  /// No description provided for @kpiTargetsNewestFirstAnEntryIsNeverEdited.
  ///
  /// In en, this message translates to:
  /// **'Newest first. An entry is never edited — a later one supersedes it.'**
  String get kpiTargetsNewestFirstAnEntryIsNeverEdited;

  /// No description provided for @kpiTargetsNoTargetHasBeenSet.
  ///
  /// In en, this message translates to:
  /// **'No Target has been set'**
  String get kpiTargetsNoTargetHasBeenSet;

  /// No description provided for @kpiTargetsEveryEntryMadeForThisKpiWill.
  ///
  /// In en, this message translates to:
  /// **'Every entry made for this KPI will be listed here.'**
  String get kpiTargetsEveryEntryMadeForThisKpiWill;

  /// No description provided for @assetFormCorrectDetails.
  ///
  /// In en, this message translates to:
  /// **'Correct details'**
  String get assetFormCorrectDetails;

  /// No description provided for @commonAddAnAsset.
  ///
  /// In en, this message translates to:
  /// **'Add an Asset'**
  String get commonAddAnAsset;

  /// No description provided for @assetFormAddAsset.
  ///
  /// In en, this message translates to:
  /// **'Add Asset'**
  String get assetFormAddAsset;

  /// No description provided for @assetFormUniqueAcrossTheWholePlatformNotJust.
  ///
  /// In en, this message translates to:
  /// **'Unique across the whole Platform, not just this Site.'**
  String get assetFormUniqueAcrossTheWholePlatformNotJust;

  /// No description provided for @assetFormKind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get assetFormKind;

  /// No description provided for @commonCriticality.
  ///
  /// In en, this message translates to:
  /// **'Criticality'**
  String get commonCriticality;

  /// No description provided for @assetFormWhereThisAssetSitsIsChangedWith.
  ///
  /// In en, this message translates to:
  /// **'Where this Asset sits is changed with its own \"Change Org Unit…\" action.'**
  String get assetFormWhereThisAssetSitsIsChangedWith;

  /// No description provided for @assetFormThisAssetWillSitAt.
  ///
  /// In en, this message translates to:
  /// **'This Asset will sit at {value}.'**
  String assetFormThisAssetWillSitAt(Object value);

  /// No description provided for @assetMoveChangeWhereThisAssetSits.
  ///
  /// In en, this message translates to:
  /// **'Change where this Asset sits'**
  String get assetMoveChangeWhereThisAssetSits;

  /// No description provided for @assetMoveChangeOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Change Org Unit'**
  String get assetMoveChangeOrgUnit;

  /// No description provided for @assetMoveSitsAtNow.
  ///
  /// In en, this message translates to:
  /// **'{name} ({code}) sits at {orgUnitName} now.'**
  String assetMoveSitsAtNow(Object name, Object code, Object orgUnitName);

  /// No description provided for @assetMoveMoveItTo.
  ///
  /// In en, this message translates to:
  /// **'Move it to'**
  String get assetMoveMoveItTo;

  /// No description provided for @assetMoveWhereThisAssetWillSitItDecides.
  ///
  /// In en, this message translates to:
  /// **'Where this Asset will sit. It decides who may raise and close work against it; work already recorded against it stays where it happened.'**
  String get assetMoveWhereThisAssetWillSitItDecides;

  /// No description provided for @assetMoveThisAssetWillSitAt.
  ///
  /// In en, this message translates to:
  /// **'This Asset will sit at {value}.'**
  String assetMoveThisAssetWillSitAt(Object value);

  /// No description provided for @assetsTheRegisterCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The register could not be read'**
  String get assetsTheRegisterCouldNotBeRead;

  /// No description provided for @assetsNoAssetsOnTheRegisterYet.
  ///
  /// In en, this message translates to:
  /// **'No Assets on the register yet'**
  String get assetsNoAssetsOnTheRegisterYet;

  /// No description provided for @assetsNothingHasBeenRecordedAtThisSite.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been recorded at this Site. Add a machine and it can be worked on the same day.'**
  String get assetsNothingHasBeenRecordedAtThisSite;

  /// No description provided for @assetsEveryMachineOnTheRegisterAtThis.
  ///
  /// In en, this message translates to:
  /// **'Every machine on the register at this Site, and the Org Unit each one sits at.'**
  String get assetsEveryMachineOnTheRegisterAtThis;

  /// No description provided for @assetsShowRetired.
  ///
  /// In en, this message translates to:
  /// **'Show retired'**
  String get assetsShowRetired;

  /// No description provided for @assetsFilterAssets.
  ///
  /// In en, this message translates to:
  /// **'Filter Assets'**
  String get assetsFilterAssets;

  /// No description provided for @assetsNoAssetsMatch.
  ///
  /// In en, this message translates to:
  /// **'No Assets match'**
  String get assetsNoAssetsMatch;

  /// No description provided for @assetsThisSiteHasAssetsOnTheRegister.
  ///
  /// In en, this message translates to:
  /// **'This Site has Assets on the register, but none matches \"{term}\". Try a different name or code, or clear the filter.'**
  String assetsThisSiteHasAssetsOnTheRegister(Object term);

  /// No description provided for @assetsCodeType.
  ///
  /// In en, this message translates to:
  /// **'Code · Type'**
  String get assetsCodeType;

  /// No description provided for @assetsCorrectDetails.
  ///
  /// In en, this message translates to:
  /// **'Correct details…'**
  String get assetsCorrectDetails;

  /// No description provided for @assetsChangeOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Change Org Unit…'**
  String get assetsChangeOrgUnit;

  /// No description provided for @assetsDetach.
  ///
  /// In en, this message translates to:
  /// **'Detach'**
  String get assetsDetach;

  /// No description provided for @assetsNestUnder.
  ///
  /// In en, this message translates to:
  /// **'Nest under…'**
  String get assetsNestUnder;

  /// No description provided for @assetsRetireThisAsset.
  ///
  /// In en, this message translates to:
  /// **'Retire this Asset?'**
  String get assetsRetireThisAsset;

  /// No description provided for @assetsWillNoLongerAppearOnTheActive.
  ///
  /// In en, this message translates to:
  /// **'{name} will no longer appear on the active register. Nothing is deleted, and it can be reinstated at any time.'**
  String assetsWillNoLongerAppearOnTheActive(Object name);

  /// No description provided for @assetsThereIsNothingElseOnThisRegister.
  ///
  /// In en, this message translates to:
  /// **'There is nothing else on this register it could sit beneath.'**
  String get assetsThereIsNothingElseOnThisRegister;

  /// No description provided for @breakdownReportReportABreakdown.
  ///
  /// In en, this message translates to:
  /// **'Report a Breakdown'**
  String get breakdownReportReportABreakdown;

  /// No description provided for @breakdownReportReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get breakdownReportReport;

  /// No description provided for @breakdownReportStartedAtOptional.
  ///
  /// In en, this message translates to:
  /// **'Started at (optional)'**
  String get breakdownReportStartedAtOptional;

  /// No description provided for @commonLeaveBlankToRecordNow.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to record now.'**
  String get commonLeaveBlankToRecordNow;

  /// No description provided for @downtimeClassifyClassifyTheStopFor.
  ///
  /// In en, this message translates to:
  /// **'Classify the stop for {assetName}'**
  String downtimeClassifyClassifyTheStopFor(Object assetName);

  /// No description provided for @downtimeClassifyKeepItUnclassified.
  ///
  /// In en, this message translates to:
  /// **'Keep it unclassified'**
  String get downtimeClassifyKeepItUnclassified;

  /// No description provided for @downtimeClassifyDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Description (required)'**
  String get downtimeClassifyDescriptionRequired;

  /// No description provided for @downtimeClassifyTheDowntimeReasonsCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The Downtime reasons could not be read.'**
  String get downtimeClassifyTheDowntimeReasonsCouldNotBeRead;

  /// No description provided for @downtimeCloseCloseTheStopFor.
  ///
  /// In en, this message translates to:
  /// **'Close the stop for {assetName}?'**
  String downtimeCloseCloseTheStopFor(Object assetName);

  /// No description provided for @commonKeepItOpen.
  ///
  /// In en, this message translates to:
  /// **'Keep it open'**
  String get commonKeepItOpen;

  /// No description provided for @downtimeCloseCloseThisStop.
  ///
  /// In en, this message translates to:
  /// **'Close this stop'**
  String get downtimeCloseCloseThisStop;

  /// No description provided for @downtimeCloseTheMachineIsRunningAgainTheServer.
  ///
  /// In en, this message translates to:
  /// **'The machine is running again. The server records how long it was down.'**
  String get downtimeCloseTheMachineIsRunningAgainTheServer;

  /// No description provided for @downtimeCloseEndedAtOptional.
  ///
  /// In en, this message translates to:
  /// **'Ended at (optional)'**
  String get downtimeCloseEndedAtOptional;

  /// No description provided for @floorTheFloorWorkCouldNotBeLoaded.
  ///
  /// In en, this message translates to:
  /// **'The floor work could not be loaded'**
  String get floorTheFloorWorkCouldNotBeLoaded;

  /// No description provided for @floorNoOpenWork.
  ///
  /// In en, this message translates to:
  /// **'No open work'**
  String get floorNoOpenWork;

  /// No description provided for @floorThereIsNoOpenWorkForRight.
  ///
  /// In en, this message translates to:
  /// **'There is no open work for {orgUnitName} right now.'**
  String floorThereIsNoOpenWorkForRight(Object orgUnitName);

  /// No description provided for @floorRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get floorRefresh;

  /// No description provided for @floorFloorWork.
  ///
  /// In en, this message translates to:
  /// **'Floor work'**
  String get floorFloorWork;

  /// No description provided for @floorObservation.
  ///
  /// In en, this message translates to:
  /// **'Observation'**
  String get floorObservation;

  /// No description provided for @floorMyTraining.
  ///
  /// In en, this message translates to:
  /// **'My training'**
  String get floorMyTraining;

  /// No description provided for @floorTechnicianComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete {workOrderNo}'**
  String floorTechnicianComplete(Object workOrderNo);

  /// No description provided for @floorTechnicianStart.
  ///
  /// In en, this message translates to:
  /// **'Start {workOrderNo}'**
  String floorTechnicianStart(Object workOrderNo);

  /// No description provided for @floorTechnicianWhoIsRecordingThisYourEmployeeNumber.
  ///
  /// In en, this message translates to:
  /// **'Who is recording this? Your Employee number and PIN identify you for this action only.'**
  String get floorTechnicianWhoIsRecordingThisYourEmployeeNumber;

  /// No description provided for @commonWhatWasFound.
  ///
  /// In en, this message translates to:
  /// **'What was found?'**
  String get commonWhatWasFound;

  /// No description provided for @myRequestsYourRequestsCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'Your requests could not be read'**
  String get myRequestsYourRequestsCouldNotBeRead;

  /// No description provided for @myRequestsWhatYouRaisedAndWhatBecameOf.
  ///
  /// In en, this message translates to:
  /// **'What you raised, and what became of each.'**
  String get myRequestsWhatYouRaisedAndWhatBecameOf;

  /// No description provided for @commonRaiseARequest.
  ///
  /// In en, this message translates to:
  /// **'Raise a Request'**
  String get commonRaiseARequest;

  /// No description provided for @myRequestsYouHaveRequestsAtThisSiteBut.
  ///
  /// In en, this message translates to:
  /// **'You have Requests at this Site, but none matches \"{term}\". Try a different description or Asset.'**
  String myRequestsYouHaveRequestsAtThisSiteBut(Object term);

  /// No description provided for @myRequestsOutcome.
  ///
  /// In en, this message translates to:
  /// **'Outcome'**
  String get myRequestsOutcome;

  /// No description provided for @myRequestsBecameWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Became Work order {workOrderNo}'**
  String myRequestsBecameWorkOrder(Object workOrderNo);

  /// No description provided for @myRequestsDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined: {rejectionReason}'**
  String myRequestsDeclined(Object rejectionReason);

  /// No description provided for @myRequestsNothingRaisedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing raised yet'**
  String get myRequestsNothingRaisedYet;

  /// No description provided for @myRequestsYouHaveNotRaisedAnyRequestsAt.
  ///
  /// In en, this message translates to:
  /// **'You have not raised any Requests at this Site. Raise one and it will show up here with whatever becomes of it.'**
  String get myRequestsYouHaveNotRaisedAnyRequestsAt;

  /// No description provided for @commonAddPart.
  ///
  /// In en, this message translates to:
  /// **'Add part'**
  String get commonAddPart;

  /// No description provided for @commonPartNumber.
  ///
  /// In en, this message translates to:
  /// **'Part number'**
  String get commonPartNumber;

  /// No description provided for @partsThePartsCatalogueCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The parts catalogue could not be read'**
  String get partsThePartsCatalogueCouldNotBeRead;

  /// No description provided for @partsTheSharedCatalogueDefinedOnceReusedAt.
  ///
  /// In en, this message translates to:
  /// **'The shared catalogue — defined once, reused at every Site.'**
  String get partsTheSharedCatalogueDefinedOnceReusedAt;

  /// No description provided for @partsNoPartsYet.
  ///
  /// In en, this message translates to:
  /// **'No parts yet'**
  String get partsNoPartsYet;

  /// No description provided for @partsFilterParts.
  ///
  /// In en, this message translates to:
  /// **'Filter parts'**
  String get partsFilterParts;

  /// No description provided for @commonByPartNumberOrDescription.
  ///
  /// In en, this message translates to:
  /// **'By part number or description.'**
  String get commonByPartNumberOrDescription;

  /// No description provided for @commonNoPartsMatch.
  ///
  /// In en, this message translates to:
  /// **'No parts match'**
  String get commonNoPartsMatch;

  /// No description provided for @partsNothingInTheCatalogueMatchesTryA.
  ///
  /// In en, this message translates to:
  /// **'Nothing in the catalogue matches \"{term}\". Try a different part number or description, or clear the filter.'**
  String partsNothingInTheCatalogueMatchesTryA(Object term);

  /// No description provided for @commonReceiveStock.
  ///
  /// In en, this message translates to:
  /// **'Receive stock'**
  String get commonReceiveStock;

  /// No description provided for @receiveReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving…'**
  String get receiveReceiving;

  /// No description provided for @receiveReceive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receiveReceive;

  /// No description provided for @receiveReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get receiveReasonOptional;

  /// No description provided for @commonRaise.
  ///
  /// In en, this message translates to:
  /// **'Raise'**
  String get commonRaise;

  /// No description provided for @requestFormProductionIsStoppedRightNow.
  ///
  /// In en, this message translates to:
  /// **'Production is stopped right now'**
  String get requestFormProductionIsStoppedRightNow;

  /// No description provided for @storeStockThisStoreCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'This store could not be read'**
  String get storeStockThisStoreCouldNotBeRead;

  /// No description provided for @storeStockBackToStores.
  ///
  /// In en, this message translates to:
  /// **'Back to Stores'**
  String get storeStockBackToStores;

  /// No description provided for @storeStockNothingOnTheShelf.
  ///
  /// In en, this message translates to:
  /// **'Nothing on the shelf'**
  String get storeStockNothingOnTheShelf;

  /// No description provided for @storeStockNoPartHasMovedInOrOut.
  ///
  /// In en, this message translates to:
  /// **'No part has moved in or out of this store yet.'**
  String get storeStockNoPartHasMovedInOrOut;

  /// No description provided for @storeStockFilterStock.
  ///
  /// In en, this message translates to:
  /// **'Filter stock'**
  String get storeStockFilterStock;

  /// No description provided for @storeStockThisStoreHoldsStockButNothingOn.
  ///
  /// In en, this message translates to:
  /// **'This store holds stock, but nothing on its shelf matches \"{term}\". Try a different part number or description.'**
  String storeStockThisStoreHoldsStockButNothingOn(Object term);

  /// No description provided for @storesTheStoresCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The stores could not be read'**
  String get storesTheStoresCouldNotBeRead;

  /// No description provided for @storesTheShelvesThatHoldPartsAtThis.
  ///
  /// In en, this message translates to:
  /// **'The shelves that hold parts at this Site.'**
  String get storesTheShelvesThatHoldPartsAtThis;

  /// No description provided for @storesNoStoresYet.
  ///
  /// In en, this message translates to:
  /// **'No stores yet'**
  String get storesNoStoresYet;

  /// No description provided for @storesNothingHereHoldsParts.
  ///
  /// In en, this message translates to:
  /// **'Nothing here holds parts.'**
  String get storesNothingHereHoldsParts;

  /// No description provided for @storesFilterStores.
  ///
  /// In en, this message translates to:
  /// **'Filter stores'**
  String get storesFilterStores;

  /// No description provided for @storesNoStoresMatch.
  ///
  /// In en, this message translates to:
  /// **'No stores match'**
  String get storesNoStoresMatch;

  /// No description provided for @storesThisSiteHasStoresButNoneMatches.
  ///
  /// In en, this message translates to:
  /// **'This Site has stores, but none matches \"{term}\". Try a different name or code, or clear the filter.'**
  String storesThisSiteHasStoresButNoneMatches(Object term);

  /// No description provided for @storesTappingAStoreShowsWhatIsOn.
  ///
  /// In en, this message translates to:
  /// **'Tapping a store shows what is on its shelf.'**
  String get storesTappingAStoreShowsWhatIsOn;

  /// No description provided for @storesCodeOrgUnit.
  ///
  /// In en, this message translates to:
  /// **'Code · Org Unit'**
  String get storesCodeOrgUnit;

  /// No description provided for @taskReadingRecordAReadingOn.
  ///
  /// In en, this message translates to:
  /// **'Record a reading on {value}'**
  String taskReadingRecordAReadingOn(Object value);

  /// No description provided for @taskReadingWhatTheMeterReads.
  ///
  /// In en, this message translates to:
  /// **'What the meter reads'**
  String get taskReadingWhatTheMeterReads;

  /// No description provided for @tierBoardOrgUnitFilterNarrowTheBoard.
  ///
  /// In en, this message translates to:
  /// **'Narrow the board'**
  String get tierBoardOrgUnitFilterNarrowTheBoard;

  /// No description provided for @tierBoardOrgUnitFilterChooseTheOrgUnitWhoseNumbersAnd.
  ///
  /// In en, this message translates to:
  /// **'Choose the Org Unit whose numbers and everything beneath it you want to read, or clear back to the whole Site.'**
  String get tierBoardOrgUnitFilterChooseTheOrgUnitWhoseNumbersAnd;

  /// No description provided for @tierTheTierBoardCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The tier board could not be read'**
  String get tierTheTierBoardCouldNotBeRead;

  /// No description provided for @tierTheNumbersThisSiteSWorkProduces.
  ///
  /// In en, this message translates to:
  /// **'The numbers this Site\'s work produces, reported under the five Pillars. Every Pillar is shown whether or not anything reports under it yet.'**
  String get tierTheNumbersThisSiteSWorkProduces;

  /// No description provided for @tierDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get tierDate;

  /// No description provided for @tierNoPillarsToShow.
  ///
  /// In en, this message translates to:
  /// **'No Pillars to show'**
  String get tierNoPillarsToShow;

  /// No description provided for @tierThisSiteHasNoPillarsToReport.
  ///
  /// In en, this message translates to:
  /// **'This Site has no Pillars to report against yet.'**
  String get tierThisSiteHasNoPillarsToReport;

  /// No description provided for @tierNoDataYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get tierNoDataYet;

  /// No description provided for @tierNoKpiIsDefinedUnderThisPillar.
  ///
  /// In en, this message translates to:
  /// **'No KPI is defined under this Pillar yet.'**
  String get tierNoKpiIsDefinedUnderThisPillar;

  /// No description provided for @tierValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get tierValue;

  /// No description provided for @workOrderAssignFindAPerson.
  ///
  /// In en, this message translates to:
  /// **'Find a person'**
  String get workOrderAssignFindAPerson;

  /// No description provided for @workOrderAssignByNameEmployeeNumberOrTheQualification.
  ///
  /// In en, this message translates to:
  /// **'By name, employee number, or the qualification they hold.'**
  String get workOrderAssignByNameEmployeeNumberOrTheQualification;

  /// No description provided for @workOrderAssignTheCandidatesCouldNotBeRead.
  ///
  /// In en, this message translates to:
  /// **'The candidates could not be read.'**
  String get workOrderAssignTheCandidatesCouldNotBeRead;

  /// No description provided for @workOrderAssignNobodyMatchesTryADifferentNameNumber.
  ///
  /// In en, this message translates to:
  /// **'Nobody matches \"{term}\" — try a different name, number, or skill.'**
  String workOrderAssignNobodyMatchesTryADifferentNameNumber(Object term);

  /// No description provided for @workOrderAssignThereIsNobodyThisWorkOrderCould.
  ///
  /// In en, this message translates to:
  /// **'There is nobody this Work order could be given to.'**
  String get workOrderAssignThereIsNobodyThisWorkOrderCould;

  /// No description provided for @workOrderAssignNoQualificationsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No qualifications recorded'**
  String get workOrderAssignNoQualificationsRecorded;

  /// No description provided for @workOrderCancelCancelThisWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel this Work order?'**
  String get workOrderCancelCancelThisWorkOrder;

  /// No description provided for @workOrderCancelCancelThisWorkOrder2.
  ///
  /// In en, this message translates to:
  /// **'Cancel this Work order'**
  String get workOrderCancelCancelThisWorkOrder2;

  /// No description provided for @workOrderCancelWhyIsThisBeingCancelledOptional.
  ///
  /// In en, this message translates to:
  /// **'Why is this being cancelled? (optional)'**
  String get workOrderCancelWhyIsThisBeingCancelledOptional;

  /// No description provided for @workOrderCompleteCompleteThisWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Complete this Work order'**
  String get workOrderCompleteCompleteThisWorkOrder;

  /// No description provided for @workOrderDialogYouDoNotHoldAWriteGrant.
  ///
  /// In en, this message translates to:
  /// **'You do not hold a write Grant that reaches this Work order.'**
  String get workOrderDialogYouDoNotHoldAWriteGrant;

  /// No description provided for @workOrderDialogLoadingThisWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Loading this Work order'**
  String get workOrderDialogLoadingThisWorkOrder;

  /// No description provided for @workOrderDialogThatIsNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'That is no longer available'**
  String get workOrderDialogThatIsNoLongerAvailable;

  /// No description provided for @workOrderDialogThisWorkOrderIsNowWhichNo.
  ///
  /// In en, this message translates to:
  /// **'This Work order is now {statusLabel}, which no longer offers this action.'**
  String workOrderDialogThisWorkOrderIsNowWhichNo(Object statusLabel);

  /// No description provided for @workOrderDialogThatWorkOrderIsNotInThis.
  ///
  /// In en, this message translates to:
  /// **'That Work order is not in this list'**
  String get workOrderDialogThatWorkOrderIsNotInThis;

  /// No description provided for @workOrderDialogItMayHaveBeenCompletedCancelledOr.
  ///
  /// In en, this message translates to:
  /// **'It may have been completed, cancelled, or it is outside the Site or Org Unit the list is currently showing.'**
  String get workOrderDialogItMayHaveBeenCompletedCancelledOr;

  /// No description provided for @workOrdersWoBuc202600001.
  ///
  /// In en, this message translates to:
  /// **'WO-BUC-2026-00001'**
  String get workOrdersWoBuc202600001;

  /// A Work order's status: written down, not yet approved.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get workOrderStatusDraft;

  /// A Work order's status: approved and waiting to be scheduled.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get workOrderStatusApproved;

  /// A Work order's status: on the plan for a day.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get workOrderStatusScheduled;

  /// A Work order's status: work is under way.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get workOrderStatusInProgress;

  /// A Work order's status: stopped, waiting on a decision.
  ///
  /// In en, this message translates to:
  /// **'On hold'**
  String get workOrderStatusOnHold;

  /// A Work order's status: the work is done, not yet closed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get workOrderStatusCompleted;

  /// A Work order's status: finished and closed off.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get workOrderStatusClosed;

  /// A Work order's status: called off on purpose.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get workOrderStatusCancelled;

  /// A step inside a Work order: not started.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get workOrderTaskStatusPending;

  /// A step inside a Work order: carried out.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get workOrderTaskStatusDone;

  /// A step inside a Work order: stepped over on purpose.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get workOrderTaskStatusSkipped;

  /// A step inside a Work order: attempted and it did not work.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get workOrderTaskStatusFailed;

  /// A Work order's type: fixing something that broke.
  ///
  /// In en, this message translates to:
  /// **'Corrective'**
  String get workOrderWorkTypeCorrective;

  /// A Work order's type: planned work that keeps it from breaking.
  ///
  /// In en, this message translates to:
  /// **'Preventive'**
  String get workOrderWorkTypePreventive;

  /// A Work order's type: work triggered by a measured trend.
  ///
  /// In en, this message translates to:
  /// **'Predictive'**
  String get workOrderWorkTypePredictive;

  /// A Work order's type: looking, not repairing.
  ///
  /// In en, this message translates to:
  /// **'Inspection'**
  String get workOrderWorkTypeInspection;

  /// A Work order's type: making something better than it was.
  ///
  /// In en, this message translates to:
  /// **'Improvement'**
  String get workOrderWorkTypeImprovement;

  /// A Work order's type: setting an instrument to a known standard.
  ///
  /// In en, this message translates to:
  /// **'Calibration'**
  String get workOrderWorkTypeCalibration;

  /// How a fitted part reached the job: drawn from the store.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get partSourceStores;

  /// How a fitted part reached the job: bought for it.
  ///
  /// In en, this message translates to:
  /// **'Purchased'**
  String get partSourcePurchased;

  /// How a fitted part reached the job: repaired and reused.
  ///
  /// In en, this message translates to:
  /// **'Refurbished'**
  String get partSourceRefurbished;

  /// How a fitted part reached the job: taken off another machine.
  ///
  /// In en, this message translates to:
  /// **'Cannibalised'**
  String get partSourceCannibalised;

  /// A maintenance Request's urgency: whenever someone can.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get requestUrgencyLow;

  /// A maintenance Request's urgency: the ordinary queue.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get requestUrgencyNormal;

  /// A maintenance Request's urgency: soon, please.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get requestUrgencyHigh;

  /// A maintenance Request's urgency: stop and come now.
  ///
  /// In en, this message translates to:
  /// **'Immediate'**
  String get requestUrgencyImmediate;

  /// A maintenance Request's status: raised, not yet read.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get requestStatusNew;

  /// A maintenance Request's status: maintenance has read it.
  ///
  /// In en, this message translates to:
  /// **'Triaged'**
  String get requestStatusTriaged;

  /// A maintenance Request's status: it became a Work order.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get requestStatusAccepted;

  /// A maintenance Request's status: maintenance said no.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get requestStatusRejected;

  /// A maintenance Request's status: the same problem was already raised.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get requestStatusDuplicate;

  /// A booked labour line's activity: hands on the job.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get labourActivityWork;

  /// A booked labour line's activity: getting to the job.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get labourActivityTravel;

  /// A booked labour line's activity: waiting for a permit or a part.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get labourActivityWaiting;

  /// A booked labour line's activity: working out what is wrong.
  ///
  /// In en, this message translates to:
  /// **'Diagnosis'**
  String get labourActivityDiagnosis;

  /// A booked labour line's activity: writing the job up.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get labourActivityDocumentation;

  /// A meter's type: only ever goes up, so a PM schedule can run off it.
  ///
  /// In en, this message translates to:
  /// **'Cumulative'**
  String get meterTypeCumulative;

  /// A meter's type: may go either way, recorded but never scheduled against.
  ///
  /// In en, this message translates to:
  /// **'Gauge'**
  String get meterTypeGauge;

  /// The help text under the Cumulative meter type.
  ///
  /// In en, this message translates to:
  /// **'Only ever goes up — an hour counter or a cycle count. Only a cumulative meter can drive a PM schedule.'**
  String get meterTypeCumulativeExplanation;

  /// The help text under the Gauge meter type.
  ///
  /// In en, this message translates to:
  /// **'May go either way — a temperature, a pressure, an oil level. Recorded, but never scheduled against.'**
  String get meterTypeGaugeExplanation;

  /// A PM schedule's anchor: the next date rolls from the original due date.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get pmAnchorDueDate;

  /// A PM schedule's anchor: the next date rolls from when the work was done.
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get pmAnchorCompletion;

  /// The help text under the Due date anchor.
  ///
  /// In en, this message translates to:
  /// **'The next date is fixed to the calendar: doing the work late does not push the following one back.'**
  String get pmAnchorDueDateExplanation;

  /// The help text under the Completion anchor.
  ///
  /// In en, this message translates to:
  /// **'The clock starts when the work was actually done, so a service done late simply slides.'**
  String get pmAnchorCompletionExplanation;

  /// An Action's status: raised and live.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionStatusOpen;

  /// An Action's status: someone is working on it.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get actionStatusInProgress;

  /// An Action's status: stopped, waiting on a decision.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get actionStatusBlocked;

  /// An Action's status: finished.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionStatusDone;

  /// An Action's status: called off on purpose.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get actionStatusCancelled;

  /// An Action's type: the problem itself, which measures answer.
  ///
  /// In en, this message translates to:
  /// **'Concern'**
  String get actionTypeConcern;

  /// An Action's type: stopping the problem spreading while it is investigated.
  ///
  /// In en, this message translates to:
  /// **'Containment'**
  String get actionTypeContainment;

  /// An Action's type: the fix that keeps the problem from coming back.
  ///
  /// In en, this message translates to:
  /// **'Countermeasure'**
  String get actionTypeCountermeasure;

  /// An Action's type: work that keeps the problem from starting.
  ///
  /// In en, this message translates to:
  /// **'Preventive action'**
  String get actionTypePreventive;

  /// An Action's type: making something better than it was.
  ///
  /// In en, this message translates to:
  /// **'Improvement'**
  String get actionTypeImprovement;

  /// An Action's type: ordinary work, not answering a Concern.
  ///
  /// In en, this message translates to:
  /// **'Routine action'**
  String get actionTypeRoutine;

  /// A turn of the PDCA cycle: what will be done.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get actionPhasePlan;

  /// A turn of the PDCA cycle: carrying the plan out.
  ///
  /// In en, this message translates to:
  /// **'Do'**
  String get actionPhaseDo;

  /// A turn of the PDCA cycle: did it hold?
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get actionPhaseCheck;

  /// A turn of the PDCA cycle: making the result the standard.
  ///
  /// In en, this message translates to:
  /// **'Act'**
  String get actionPhaseAct;

  /// A Check's verdict: the countermeasure worked.
  ///
  /// In en, this message translates to:
  /// **'It held'**
  String get actionCheckOutcomeHeld;

  /// A Check's verdict: the countermeasure did not work, so the cycle runs again.
  ///
  /// In en, this message translates to:
  /// **'It did not hold'**
  String get actionCheckOutcomeDidNotHold;

  /// The highest Action priority: fix this first.
  ///
  /// In en, this message translates to:
  /// **'P1 — worst'**
  String get actionPriorityWorst;

  /// An Action priority: second of five.
  ///
  /// In en, this message translates to:
  /// **'P2'**
  String get actionPriority2;

  /// An Action priority: the ordinary one.
  ///
  /// In en, this message translates to:
  /// **'P3 — normal'**
  String get actionPriorityNormal;

  /// An Action priority: fourth of five.
  ///
  /// In en, this message translates to:
  /// **'P4'**
  String get actionPriority4;

  /// The lowest Action priority.
  ///
  /// In en, this message translates to:
  /// **'P5 — least'**
  String get actionPriorityLeast;

  /// A CAPA's status: opened, nothing done yet.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get capaStatusOpen;

  /// A CAPA's status: the problem is stopped from spreading.
  ///
  /// In en, this message translates to:
  /// **'Contained'**
  String get capaStatusContainment;

  /// A CAPA's status: working the fishbone to the cause.
  ///
  /// In en, this message translates to:
  /// **'Root cause'**
  String get capaStatusRootCause;

  /// A CAPA's status: the fixes are being decided and carried out.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get capaStatusActions;

  /// A CAPA's status: the fix is in and nobody has proved it held.
  ///
  /// In en, this message translates to:
  /// **'Verifying'**
  String get capaStatusVerifying;

  /// A CAPA's status: the fix held and the investigation is closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get capaStatusClosed;

  /// A CAPA's status: called off on purpose.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get capaStatusCancelled;

  /// The method a CAPA is opened by: the eight disciplines.
  ///
  /// In en, this message translates to:
  /// **'8D'**
  String get capaMethod8d;

  /// The method a CAPA is opened by: asking why five times.
  ///
  /// In en, this message translates to:
  /// **'5 Why'**
  String get capaMethodFiveWhy;

  /// The method a CAPA is opened by: one A3 sheet.
  ///
  /// In en, this message translates to:
  /// **'A3'**
  String get capaMethodA3;

  /// The method a CAPA is opened by: the short form.
  ///
  /// In en, this message translates to:
  /// **'Simple'**
  String get capaMethodSimple;

  /// One 5 Why chain: why the problem happened.
  ///
  /// In en, this message translates to:
  /// **'Why it happened'**
  String get capaChainOccurrence;

  /// One 5 Why chain: why the problem was not caught.
  ///
  /// In en, this message translates to:
  /// **'Why it was not detected'**
  String get capaChainEscape;

  /// An Ishikawa bone: the people doing the work.
  ///
  /// In en, this message translates to:
  /// **'Man'**
  String get capaCauseCategoryMan;

  /// An Ishikawa bone: the equipment.
  ///
  /// In en, this message translates to:
  /// **'Machine'**
  String get capaCauseCategoryMachine;

  /// An Ishikawa bone: how the work is done.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get capaCauseCategoryMethod;

  /// An Ishikawa bone: what the work is done with.
  ///
  /// In en, this message translates to:
  /// **'Material'**
  String get capaCauseCategoryMaterial;

  /// An Ishikawa bone: how it is measured.
  ///
  /// In en, this message translates to:
  /// **'Measurement'**
  String get capaCauseCategoryMeasurement;

  /// An Ishikawa bone: the surroundings.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get capaCauseCategoryEnvironment;

  /// A candidate cause's verdict: not looked at yet.
  ///
  /// In en, this message translates to:
  /// **'Candidate'**
  String get capaCauseVerdictCandidate;

  /// A candidate cause's verdict: the evidence backed it.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get capaCauseVerdictConfirmed;

  /// A candidate cause's verdict: the evidence settled it, and the answer was no.
  ///
  /// In en, this message translates to:
  /// **'Ruled out'**
  String get capaCauseVerdictRuledOut;

  /// An effectiveness check's verdict: the fix worked.
  ///
  /// In en, this message translates to:
  /// **'The fix held'**
  String get capaEffectivenessHeld;

  /// An effectiveness check's verdict: the Concern goes round again.
  ///
  /// In en, this message translates to:
  /// **'The fix did not hold'**
  String get capaEffectivenessDidNotHold;

  /// A Safety incident's status: reported, not yet investigated.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get safetyIncidentStatusOpen;

  /// A Safety incident's status: an investigation is under way.
  ///
  /// In en, this message translates to:
  /// **'Investigating'**
  String get safetyIncidentStatusInvestigating;

  /// A Safety incident's status: the actions it raised are not done.
  ///
  /// In en, this message translates to:
  /// **'Actions pending'**
  String get safetyIncidentStatusActionsPending;

  /// A Safety incident's status: investigated and closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get safetyIncidentStatusClosed;

  /// A Safety incident's type: somebody was hurt.
  ///
  /// In en, this message translates to:
  /// **'Injury'**
  String get safetyIncidentTypeInjury;

  /// A Safety incident's type: it nearly happened.
  ///
  /// In en, this message translates to:
  /// **'Near miss'**
  String get safetyIncidentTypeNearMiss;

  /// A Safety incident's type: something was damaged.
  ///
  /// In en, this message translates to:
  /// **'Property damage'**
  String get safetyIncidentTypePropertyDamage;

  /// A Safety incident's type: a release into the environment.
  ///
  /// In en, this message translates to:
  /// **'Environmental'**
  String get safetyIncidentTypeEnvironmental;

  /// A Safety incident's type: fire or smoke.
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get safetyIncidentTypeFire;

  /// A Safety incident's type: strain from how the work is done.
  ///
  /// In en, this message translates to:
  /// **'Ergonomic'**
  String get safetyIncidentTypeErgonomic;

  /// A Safety incident's type: an intrusion or a threat.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get safetyIncidentTypeSecurity;

  /// An incident's severity: nobody was hurt.
  ///
  /// In en, this message translates to:
  /// **'No injury'**
  String get safetySeverityNoInjury;

  /// An incident's severity: treated on the spot.
  ///
  /// In en, this message translates to:
  /// **'First aid'**
  String get safetySeverityFirstAid;

  /// An incident's severity: treated by a medical professional.
  ///
  /// In en, this message translates to:
  /// **'Medical treatment'**
  String get safetySeverityMedicalTreatment;

  /// An incident's severity: back at work, on lighter duties.
  ///
  /// In en, this message translates to:
  /// **'Restricted work'**
  String get safetySeverityRestrictedWork;

  /// An incident's severity: away from work for at least a day.
  ///
  /// In en, this message translates to:
  /// **'Lost time'**
  String get safetySeverityLostTime;

  /// An incident's severity: somebody died.
  ///
  /// In en, this message translates to:
  /// **'Fatality'**
  String get safetySeverityFatality;

  /// A Safety observation's type: somebody doing it right.
  ///
  /// In en, this message translates to:
  /// **'Safe act'**
  String get safetyObservationTypeSafeAct;

  /// A Safety observation's type: somebody doing it unsafely.
  ///
  /// In en, this message translates to:
  /// **'Unsafe act'**
  String get safetyObservationTypeUnsafeAct;

  /// A Safety observation's type: something unsafe about the place.
  ///
  /// In en, this message translates to:
  /// **'Unsafe condition'**
  String get safetyObservationTypeUnsafeCondition;

  /// A Safety observation's category: personal protective equipment.
  ///
  /// In en, this message translates to:
  /// **'PPE'**
  String get safetyObservationCategoryPpe;

  /// A Safety observation's category: guards on machinery.
  ///
  /// In en, this message translates to:
  /// **'Machine guarding'**
  String get safetyObservationCategoryMachineGuarding;

  /// A Safety observation's category: tidiness and order.
  ///
  /// In en, this message translates to:
  /// **'Housekeeping'**
  String get safetyObservationCategoryHousekeeping;

  /// A Safety observation's category: how the work loads the body.
  ///
  /// In en, this message translates to:
  /// **'Ergonomics'**
  String get safetyObservationCategoryErgonomics;

  /// A Safety observation's category: chemicals and their handling.
  ///
  /// In en, this message translates to:
  /// **'Chemical'**
  String get safetyObservationCategoryChemical;

  /// A Safety observation's category: work above the ground.
  ///
  /// In en, this message translates to:
  /// **'Working at height'**
  String get safetyObservationCategoryWorkingAtHeight;

  /// A Safety observation's category: vehicles and people moving.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get safetyObservationCategoryTraffic;

  /// A Safety observation's category: lock-out and tag-out.
  ///
  /// In en, this message translates to:
  /// **'Energy isolation'**
  String get safetyObservationCategoryEnergyIsolation;

  /// A Safety observation's category: the written way to do it.
  ///
  /// In en, this message translates to:
  /// **'Procedure'**
  String get safetyObservationCategoryProcedure;

  /// A Safety observation's category: none of the listed ones.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get safetyObservationCategoryOther;

  /// How bad an observation could have been: low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get safetyPotentialLow;

  /// How bad an observation could have been: medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get safetyPotentialMedium;

  /// How bad an observation could have been: high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get safetyPotentialHigh;

  /// How bad an observation could have been: fatal.
  ///
  /// In en, this message translates to:
  /// **'Fatal'**
  String get safetyPotentialFatal;

  /// The body region a Body part is filed under: head and neck.
  ///
  /// In en, this message translates to:
  /// **'Head'**
  String get bodyPartRegionHead;

  /// The body region a Body part is filed under: trunk and back.
  ///
  /// In en, this message translates to:
  /// **'Trunk'**
  String get bodyPartRegionTrunk;

  /// The body region a Body part is filed under: arms and hands.
  ///
  /// In en, this message translates to:
  /// **'Upper limb'**
  String get bodyPartRegionUpperLimb;

  /// The body region a Body part is filed under: legs and feet.
  ///
  /// In en, this message translates to:
  /// **'Lower limb'**
  String get bodyPartRegionLowerLimb;

  /// The body region a Body part is filed under: more than one place.
  ///
  /// In en, this message translates to:
  /// **'Multiple'**
  String get bodyPartRegionMultiple;

  /// The body region a Body part is filed under: not one of the listed ones.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get bodyPartRegionOther;

  /// An Account's role: works in the Org Units it is granted.
  ///
  /// In en, this message translates to:
  /// **'Operator'**
  String get roleOperator;

  /// An Account's role: runs the Org Units it is granted, and the people in them.
  ///
  /// In en, this message translates to:
  /// **'Supervisor'**
  String get roleSupervisor;

  /// An Account's role: improves the Org Units it is granted.
  ///
  /// In en, this message translates to:
  /// **'Engineer'**
  String get roleEngineer;

  /// An Account's role: oversees the Org Units it is granted.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// An Account's role: acts everywhere, with no Org Unit Grants at all.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get roleAdministrator;

  /// The line under the Operator role in the admission picker.
  ///
  /// In en, this message translates to:
  /// **'Works in the Org Units this Account is granted.'**
  String get roleOperatorDescription;

  /// The line under the Supervisor role in the admission picker.
  ///
  /// In en, this message translates to:
  /// **'Runs the Org Units this Account is granted, and the people in them.'**
  String get roleSupervisorDescription;

  /// The line under the Engineer role in the admission picker.
  ///
  /// In en, this message translates to:
  /// **'Improves the Org Units this Account is granted.'**
  String get roleEngineerDescription;

  /// The line under the Manager role in the admission picker.
  ///
  /// In en, this message translates to:
  /// **'Oversees the Org Units this Account is granted.'**
  String get roleManagerDescription;

  /// The line under the Administrator role in the admission picker.
  ///
  /// In en, this message translates to:
  /// **'Acts everywhere, in every Site, with no Org Unit Grants at all.'**
  String get roleAdministratorDescription;

  /// An Employee's employment type: a permanent contract.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get employmentTypePermanent;

  /// An Employee's employment type: a fixed-term contract.
  ///
  /// In en, this message translates to:
  /// **'Temporary'**
  String get employmentTypeTemporary;

  /// An Employee's employment type: supplied by an agency.
  ///
  /// In en, this message translates to:
  /// **'Agency'**
  String get employmentTypeAgency;

  /// An Employee's employment type: works for a contractor.
  ///
  /// In en, this message translates to:
  /// **'Contractor'**
  String get employmentTypeContractor;

  /// An Employee's employment type: learning the trade.
  ///
  /// In en, this message translates to:
  /// **'Apprentice'**
  String get employmentTypeApprentice;

  /// How a Trainee was evaluated: a paper test.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get trainingEvaluationPaper;

  /// How a Trainee was evaluated: on the job.
  ///
  /// In en, this message translates to:
  /// **'Job-training'**
  String get trainingEvaluationJobTraining;

  /// A Training record's status: being written, not yet sent to its Trainees.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get trainingStatusDraft;

  /// A Training record's status: sent to its Trainees to confirm.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get trainingStatusSent;

  /// An attendance row: at work for the whole shift.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get attendanceStatusPresent;

  /// An attendance row: at work, but late.
  ///
  /// In en, this message translates to:
  /// **'Late'**
  String get attendanceStatusLate;

  /// An attendance row: away, and the absence was booked.
  ///
  /// In en, this message translates to:
  /// **'Absent (planned)'**
  String get attendanceStatusAbsentPlanned;

  /// An attendance row: away with no notice.
  ///
  /// In en, this message translates to:
  /// **'Absent (unplanned)'**
  String get attendanceStatusAbsentUnplanned;

  /// An attendance row: on a training course instead of the line.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get attendanceStatusTraining;

  /// An attendance row: never rostered for that shift.
  ///
  /// In en, this message translates to:
  /// **'Not scheduled'**
  String get attendanceStatusNotScheduled;

  /// An attendance sheet: nobody has started it.
  ///
  /// In en, this message translates to:
  /// **'Not opened yet'**
  String get attendanceSheetStateMissing;

  /// An attendance sheet: rows entered, waiting for a supervisor.
  ///
  /// In en, this message translates to:
  /// **'Started, not yet confirmed'**
  String get attendanceSheetStateUnconfirmed;

  /// A leave request's status: waiting for a decision.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get leaveRequestStatusPending;

  /// A leave request's status: the time off was granted.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get leaveRequestStatusApproved;

  /// A leave request's status: the time off was refused.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get leaveRequestStatusRejected;

  /// A leave request's status: withdrawn by the person who asked.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get leaveRequestStatusCancelled;

  /// What a cost rate applies to: the whole Site.
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get costRateScopeSite;

  /// What a cost rate applies to: one Org Unit.
  ///
  /// In en, this message translates to:
  /// **'Org Unit'**
  String get costRateScopeOrgUnit;

  /// What a cost rate applies to: one Asset.
  ///
  /// In en, this message translates to:
  /// **'Asset'**
  String get costRateScopeAsset;

  /// What a cost rate applies to: a cost centre.
  ///
  /// In en, this message translates to:
  /// **'Cost centre'**
  String get costRateScopeCostCentre;

  /// A cost rate's kind: an hour of labour.
  ///
  /// In en, this message translates to:
  /// **'Labour, per hour'**
  String get costRateTypeLabourPerHour;

  /// A cost rate's kind: the multiplier paid on overtime.
  ///
  /// In en, this message translates to:
  /// **'Overtime premium, a multiplier'**
  String get costRateTypeOvertimePremium;

  /// A cost rate's kind: an hour of a stopped machine.
  ///
  /// In en, this message translates to:
  /// **'Machine downtime, per hour'**
  String get costRateTypeMachineDowntime;

  /// A cost rate's kind: an hour of overhead.
  ///
  /// In en, this message translates to:
  /// **'Overhead, per hour'**
  String get costRateTypeOverhead;

  /// A cost rate's kind: an hour spent putting work right.
  ///
  /// In en, this message translates to:
  /// **'Rework labour, per hour'**
  String get costRateTypeReworkLabour;

  /// A Non-conformance's status: written down, not yet contained.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get nonconformanceStatusOpen;

  /// A Non-conformance's status: the product is held.
  ///
  /// In en, this message translates to:
  /// **'Contained'**
  String get nonconformanceStatusContained;

  /// A Non-conformance's status: a decision was recorded about the product.
  ///
  /// In en, this message translates to:
  /// **'Dispositioned'**
  String get nonconformanceStatusDispositioned;

  /// A Non-conformance's status: finished and closed off.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get nonconformanceStatusClosed;

  /// A Non-conformance's status: called off on purpose.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get nonconformanceStatusCancelled;

  /// A Disposition: the product is thrown away.
  ///
  /// In en, this message translates to:
  /// **'Scrap'**
  String get dispositionScrap;

  /// A Disposition: the product is put right.
  ///
  /// In en, this message translates to:
  /// **'Rework'**
  String get dispositionRework;

  /// A Disposition: the product goes back where it came from.
  ///
  /// In en, this message translates to:
  /// **'Return to supplier'**
  String get dispositionReturnToSupplier;

  /// A Disposition: the product is used without changing it.
  ///
  /// In en, this message translates to:
  /// **'Use as is'**
  String get dispositionUseAsIs;

  /// A Disposition that is `use_as_is`, named as the concession it is.
  ///
  /// In en, this message translates to:
  /// **'Concession'**
  String get dispositionConcession;

  /// What a Non-conformance's own history calls a severity that was lowered.
  ///
  /// In en, this message translates to:
  /// **'Severity lowered'**
  String get severityChangeLowered;

  /// The sentence a Bloc reports when the caller's session has expired.
  ///
  /// In en, this message translates to:
  /// **'This session has ended. Sign in again to continue.'**
  String get noticeSessionEnded;

  /// The sentence a Bloc reports when a second write arrives while one is still running.
  ///
  /// In en, this message translates to:
  /// **'Another action is already in progress. Try again in a moment.'**
  String get noticeActionInFlight;

  /// The sentence a floor Bloc reports when its device has no registration.
  ///
  /// In en, this message translates to:
  /// **'This device is not registered. Ask an administrator to register it against an Org Unit.'**
  String get noticeDeviceNotRegistered;

  /// The sentence the floor training Bloc reports when its identification lapses.
  ///
  /// In en, this message translates to:
  /// **'Your identification has expired. Identify yourself again.'**
  String get noticeIdentificationExpired;

  /// The sentence the Accounts Bloc reports when a correction raced another administrator.
  ///
  /// In en, this message translates to:
  /// **'Another administrator has already changed that Account. The list has been refreshed.'**
  String get noticeAccountAlreadyMoved;

  /// The sentence the approval queue Bloc reports when a decision raced another administrator.
  ///
  /// In en, this message translates to:
  /// **'Another administrator has already dealt with that Account. The queue has been refreshed.'**
  String get noticeAccountAlreadyDecided;

  /// The sentence the employee detail Bloc reports after a departure is recorded.
  ///
  /// In en, this message translates to:
  /// **'{name} has left.'**
  String noticeEmployeeLeft(String name);

  /// The sentence the employee detail Bloc reports after a departure is undone.
  ///
  /// In en, this message translates to:
  /// **'{name} is back.'**
  String noticeEmployeeBack(String name);

  /// The sentence the Assets Bloc reports after an Asset is put back into service.
  ///
  /// In en, this message translates to:
  /// **'{code} is back on the active register.'**
  String noticeAssetBack(String code);

  /// The sentence the Actions Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is no action log to show.'**
  String get noticeNoSitesActionLog;

  /// The sentence the Assets Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is no register to show.'**
  String get noticeNoSitesRegister;

  /// The sentence the Stores Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there are no stores to show.'**
  String get noticeNoSitesStores;

  /// The sentence the skill coverage Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is no coverage to show.'**
  String get noticeNoSitesCoverage;

  /// The sentence the KPI catalogue Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is no KPI catalogue to show.'**
  String get noticeNoSitesKpiCatalogue;

  /// The sentence the KPI targets Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there are no Targets to show.'**
  String get noticeNoSitesKpiTargets;

  /// The sentence the KPI review Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is no KPI Review to show.'**
  String get noticeNoSitesKpiReview;

  /// The sentence the Tier board Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is no board to show.'**
  String get noticeNoSitesBoard;

  /// The sentence the Work orders Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is no work to show.'**
  String get noticeNoSitesWork;

  /// The sentence the triage queue Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is nothing waiting.'**
  String get noticeNoSitesWaiting;

  /// The sentence a register Bloc reports when the caller sees no Sites.
  ///
  /// In en, this message translates to:
  /// **'There are no Sites you can see, so there is nothing to show.'**
  String get noticeNoSitesNothing;

  /// The sentence the Assets Bloc reports after an Asset is taken out of service.
  ///
  /// In en, this message translates to:
  /// **'{code} has been retired.'**
  String noticeAssetRetired(String code);

  /// The sentence the Action detail Bloc reports after a measure is added to a Concern.
  ///
  /// In en, this message translates to:
  /// **'{actionNo} answers this — a {kind}.'**
  String noticeMeasureAnswers(String actionNo, String kind);

  /// The sentence the Action detail Bloc reports after a cycle is closed on its Act.
  ///
  /// In en, this message translates to:
  /// **'{actionNo} is closed — its Act named the standard that now holds it.'**
  String noticeActionClosed(String actionNo);

  /// The sentence the Action detail Bloc reports after a phase is completed and the next one is open.
  ///
  /// In en, this message translates to:
  /// **'{actionNo} is waiting on its {phase} phase.'**
  String noticeActionAwaitingPhase(String actionNo, String phase);

  /// What a record's own reader shows where nobody was named.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// A Defect code's default severity: minor.
  ///
  /// In en, this message translates to:
  /// **'Minor'**
  String get defectSeverityMinor;

  /// A Defect code's default severity: major.
  ///
  /// In en, this message translates to:
  /// **'Major'**
  String get defectSeverityMajor;

  /// A Defect code's default severity: critical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get defectSeverityCritical;

  /// A Non-conformance correction: the record was reopened.
  ///
  /// In en, this message translates to:
  /// **'Reopened'**
  String get correctionKindReopened;

  /// A Non-conformance correction: the record was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get correctionKindCancelled;

  /// A history row: the severity was lowered, naming both levels.
  ///
  /// In en, this message translates to:
  /// **'Severity lowered from {from} to {to}'**
  String correctionSummarySeverityLowered(String from, String to);

  /// A history row: the record was reopened from a state.
  ///
  /// In en, this message translates to:
  /// **'Reopened from {status}'**
  String correctionSummaryReopened(String status);

  /// A history row: the record was cancelled from a state.
  ///
  /// In en, this message translates to:
  /// **'Cancelled from {status}'**
  String correctionSummaryCancelled(String status);

  /// A Safety incident history row: the severity level changed.
  ///
  /// In en, this message translates to:
  /// **'Severity changed from {from} to {to}'**
  String incidentEventSeverityChanged(String from, String to);

  /// A Safety incident history row: the status moved.
  ///
  /// In en, this message translates to:
  /// **'Status moved from {from} to {to}'**
  String incidentEventStatusMoved(String from, String to);

  /// A Safety incident history row: the days away were recorded.
  ///
  /// In en, this message translates to:
  /// **'Days recorded: {days}'**
  String incidentEventDaysRecorded(String days);

  /// A Safety incident history row: the incident was closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get incidentEventClosed;

  /// A Safety incident history row: the incident was classified.
  ///
  /// In en, this message translates to:
  /// **'Classified'**
  String get incidentEventClassified;

  /// A Non-conformance's detection point: found as goods arrived.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get detectionPointIncoming;

  /// A Non-conformance's detection point: found while the work ran.
  ///
  /// In en, this message translates to:
  /// **'In process'**
  String get detectionPointInProcess;

  /// A Non-conformance's detection point: found at final inspection.
  ///
  /// In en, this message translates to:
  /// **'Final inspection'**
  String get detectionPointFinalInspection;

  /// A Non-conformance's detection point: found during an audit.
  ///
  /// In en, this message translates to:
  /// **'Audit'**
  String get detectionPointAudit;

  /// A Non-conformance's detection point: found by the customer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get detectionPointCustomer;

  /// The leading placeholder in the severity ladder's dropdown.
  ///
  /// In en, this message translates to:
  /// **'Choose a rung'**
  String get safetyAnySeverity;

  /// Appended to a severity level that has to be reported, in the ladder's dropdown.
  ///
  /// In en, this message translates to:
  /// **' · recordable'**
  String get safetySeverityRecordableSuffix;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
