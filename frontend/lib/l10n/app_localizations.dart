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
