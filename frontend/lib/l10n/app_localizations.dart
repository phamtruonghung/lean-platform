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

  /// No description provided for @capaDetailOccurrence.
  ///
  /// In en, this message translates to:
  /// **'occurrence'**
  String get capaDetailOccurrence;

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
