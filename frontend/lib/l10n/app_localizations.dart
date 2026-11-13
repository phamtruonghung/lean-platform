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
