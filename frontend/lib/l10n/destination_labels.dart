/// The Shell's own words, in the language the reader chose.
///
/// **Why a lookup and not a field on [Destination].** `platformDestinations` is
/// a `const` table, and `Destination.label` is its stable, English identity:
/// tests find a sidebar entry by `ValueKey('nav-item-Work orders')`, the
/// favicon-free browser tab title is built from the same words
/// (`router.dart`'s `documentTitle`), and a destination's label is what a
/// reviewer reads in the table. Translating by mutating the table would move
/// all three at once. So this file maps a destination's **address** — the one
/// thing on a `Destination` that is already stable and unique — to the
/// catalogue's own word for it, and falls back to the English label for any
/// address the catalogue has not been taught yet. That fallback is deliberate:
/// a Destination added tomorrow shows its English name in both languages until
/// someone translates it, rather than throwing or rendering blank.
///
/// The same shape covers the sidebar's group headings, whose constants
/// (`DestinationGroupNames`) stay the table's own keys for the same reason.
library;

import '../platform/destinations.dart';
import '../platform/router.dart';
import 'app_localizations.dart';

/// What the sidebar calls [destination], in [l10n]'s language.
String destinationLabel(AppLocalizations l10n, Destination destination) =>
    switch (destination.path) {
      Routes.home => l10n.navHome,
      Routes.directory => l10n.navDirectory,
      Routes.jobRoles => l10n.navJobRoles,
      Routes.skills => l10n.navSkills,
      Routes.orgUnits => l10n.navOrgUnits,
      Routes.attendance => l10n.navAttendance,
      Routes.training => l10n.navTraining,
      Routes.mySignature => l10n.navMySignature,
      Routes.leaveRequests => l10n.navLeaveRequests,
      Routes.costRates => l10n.navCostRates,
      Routes.productCosts => l10n.navProductStandardCosts,
      Routes.assets => l10n.navAssets,
      Routes.parts => l10n.navParts,
      Routes.stores => l10n.navStores,
      Routes.workOrders => l10n.navWorkOrders,
      Routes.myRequests => l10n.navMyRequests,
      Routes.requests => l10n.navTriageQueue,
      Routes.downtime => l10n.navDowntime,
      Routes.pmSchedules => l10n.navPmSchedules,
      Routes.meters => l10n.navMeters,
      Routes.jobPlans => l10n.navJobPlans,
      Routes.tierBoard => l10n.navTierBoard,
      Routes.skillCoverage => l10n.navSkillCoverage,
      Routes.kpi => l10n.navKpiCatalogue,
      Routes.kpiReview => l10n.navKpiReview,
      Routes.actions => l10n.navActionLog,
      Routes.products => l10n.navProducts,
      Routes.defectCodes => l10n.navDefectCodes,
      Routes.nonConformances => l10n.navNonConformances,
      Routes.capas => l10n.navCapas,
      Routes.customers => l10n.navCustomers,
      Routes.complaints => l10n.navCustomerComplaints,
      Routes.slideShow => l10n.navSlideShow,
      Routes.suppliers => l10n.navSuppliers,
      Routes.supplierNcrs => l10n.navSupplierNcrs,
      Routes.safetyIncidents => l10n.navIncidents,
      Routes.safetyObservations => l10n.navObservations,
      Routes.injuryTypes => l10n.navInjuryTypes,
      Routes.bodyParts => l10n.navBodyParts,
      Routes.production => l10n.navShiftHandovers,
      Routes.approvals => l10n.navApprovals,
      Routes.accounts => l10n.navAccounts,
      Routes.roles => l10n.navRoles,
      Routes.settings => l10n.settingsTitle,
      _ => destination.label,
    };

/// What the sidebar calls a group heading, in [l10n]'s language.
String destinationGroupLabel(AppLocalizations l10n, String group) => switch (group) {
      DestinationGroupNames.people => l10n.groupPeople,
      DestinationGroupNames.maintenance => l10n.groupMaintenance,
      DestinationGroupNames.quality => l10n.groupQuality,
      DestinationGroupNames.actions => l10n.groupActions,
      DestinationGroupNames.safety => l10n.groupSafety,
      DestinationGroupNames.production => l10n.groupProduction,
      DestinationGroupNames.insights => l10n.groupInsights,
      DestinationGroupNames.administration => l10n.groupAdministration,
      // An unlisted heading is a new group someone added without a catalogue
      // word for it; it renders as the constant they chose rather than blank.
      _ => group,
    };
