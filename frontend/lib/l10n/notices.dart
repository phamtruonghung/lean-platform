/// A Bloc's own copy travels as a **code**, and the Screen resolves it
/// (ADR-0062).
///
/// **Why.** A Bloc has no `BuildContext`, so it cannot read the catalogue; the
/// alternative — an English sentence carried in state and printed verbatim —
/// is what put English "This session has ended. Sign in again to continue."
/// under a Vietnamese page. So a Bloc emits one of the constants below, and the
/// Screen that renders it calls [noticeText]. The shape is the same one
/// `vocabulary.dart` uses for a status: a stable code mapped to a catalogue
/// word, falling back to the code itself so nothing ever renders blank.
///
/// A message that arrives already written for a person — a server's own error
/// text (`PeopleApiException.message`), say — does **not** start with `notice:`
/// and passes through [noticeText] untouched. That is the whole rule: codes are
/// translated, prose is left alone.
///
/// A code that carries a value says so after a `|`:
/// `notice:employee-left|Nguyễn Văn A`. The value is never translated — a name
/// and an asset code read the same in both languages.
library;

import 'app_localizations.dart';
import 'vocabulary.dart';

/// The prefix every Bloc-held code starts with.
const String blocNoticePrefix = 'notice:';

/// The Bloc-held messages this client has a catalogue entry for.
abstract final class BlocNotice {
  /// The caller's session has expired.
  static const String sessionEnded = 'notice:session-ended';

  /// A second write arrived while one was still running.
  static const String actionInFlight = 'notice:action-in-flight';

  /// A floor device has no registration against an Org Unit.
  static const String deviceNotRegistered = 'notice:device-not-registered';

  /// A floor identification has lapsed.
  static const String identificationExpired = 'notice:identification-expired';

  /// Another administrator changed the Account first.
  static const String accountAlreadyMoved = 'notice:account-already-moved';

  /// Another administrator decided the Account first.
  static const String accountAlreadyDecided = 'notice:account-already-decided';

  /// The caller sees no Sites, so the action log has nothing to show.
  static const String noSitesActionLog = 'notice:no-sites-action-log';

  /// The caller sees no Sites, so the register has nothing to show.
  static const String noSitesRegister = 'notice:no-sites-register';

  /// The caller sees no Sites, so there are no stores.
  static const String noSitesStores = 'notice:no-sites-stores';

  /// The caller sees no Sites, so there is no skill coverage.
  static const String noSitesCoverage = 'notice:no-sites-coverage';

  /// The caller sees no Sites, so there is no KPI catalogue.
  static const String noSitesKpiCatalogue = 'notice:no-sites-kpi-catalogue';

  /// The caller sees no Sites, so there are no KPI targets.
  static const String noSitesKpiTargets = 'notice:no-sites-kpi-targets';

  /// The caller sees no Sites, so there is no KPI review.
  static const String noSitesKpiReview = 'notice:no-sites-kpi-review';

  /// The caller sees no Sites, so there is no tier board.
  static const String noSitesBoard = 'notice:no-sites-board';

  /// The caller sees no Sites, so there is no work to show.
  static const String noSitesWork = 'notice:no-sites-work';

  /// The caller sees no Sites, so nothing is waiting to be triaged.
  static const String noSitesWaiting = 'notice:no-sites-waiting';

  /// The caller sees no Sites, so there is nothing to show.
  static const String noSitesNothing = 'notice:no-sites-nothing';

  /// An Employee's departure was recorded.
  static String employeeLeft(String displayName) =>
      '${blocNoticePrefix}employee-left|$displayName';

  /// An Employee's departure was undone.
  static String employeeBack(String displayName) =>
      '${blocNoticePrefix}employee-back|$displayName';

  /// An Asset is back in service.
  static String assetBack(String code) => '${blocNoticePrefix}asset-back|$code';

  /// An Asset has been taken out of service.
  static String assetRetired(String code) => '${blocNoticePrefix}asset-retired|$code';

  /// A measure was added to a Concern.
  static String measureAnswers(String actionNo, String actionTypeCode) =>
      '${blocNoticePrefix}measure-answers|$actionNo|$actionTypeCode';

  /// An Action's cycle closed on its Act.
  static String actionClosed(String actionNo) =>
      '${blocNoticePrefix}action-closed|$actionNo';

  /// An Action is waiting on a phase.
  static String actionAwaitingPhase(String actionNo, String phaseCode) =>
      '${blocNoticePrefix}action-awaiting-phase|$actionNo|$phaseCode';
}

/// [message] in [l10n]'s language: a Bloc-held code becomes a catalogue word,
/// and anything else (a server's own sentence) is returned unchanged.
String noticeText(AppLocalizations l10n, String message) {
  if (!message.startsWith(blocNoticePrefix)) return message;
  final parts = message.split('|');
  final code = parts.first;
  final value = parts.length > 1 ? parts.sublist(1).join('|') : '';
  return switch (code) {
    BlocNotice.sessionEnded => l10n.noticeSessionEnded,
    BlocNotice.actionInFlight => l10n.noticeActionInFlight,
    BlocNotice.deviceNotRegistered => l10n.noticeDeviceNotRegistered,
    BlocNotice.identificationExpired => l10n.noticeIdentificationExpired,
    BlocNotice.accountAlreadyMoved => l10n.noticeAccountAlreadyMoved,
    BlocNotice.accountAlreadyDecided => l10n.noticeAccountAlreadyDecided,
    BlocNotice.noSitesActionLog => l10n.noticeNoSitesActionLog,
    BlocNotice.noSitesRegister => l10n.noticeNoSitesRegister,
    BlocNotice.noSitesStores => l10n.noticeNoSitesStores,
    BlocNotice.noSitesCoverage => l10n.noticeNoSitesCoverage,
    BlocNotice.noSitesKpiCatalogue => l10n.noticeNoSitesKpiCatalogue,
    BlocNotice.noSitesKpiTargets => l10n.noticeNoSitesKpiTargets,
    BlocNotice.noSitesKpiReview => l10n.noticeNoSitesKpiReview,
    BlocNotice.noSitesBoard => l10n.noticeNoSitesBoard,
    BlocNotice.noSitesWork => l10n.noticeNoSitesWork,
    BlocNotice.noSitesWaiting => l10n.noticeNoSitesWaiting,
    BlocNotice.noSitesNothing => l10n.noticeNoSitesNothing,
    'notice:employee-left' => l10n.noticeEmployeeLeft(value),
    'notice:employee-back' => l10n.noticeEmployeeBack(value),
    'notice:asset-back' => l10n.noticeAssetBack(value),
    'notice:asset-retired' => l10n.noticeAssetRetired(value),
    'notice:measure-answers' => l10n.noticeMeasureAnswers(
        parts[1],
        actionTypeLabel(l10n, parts.length > 2 ? parts[2] : ''),
      ),
    'notice:action-closed' => l10n.noticeActionClosed(value),
    'notice:action-awaiting-phase' => l10n.noticeActionAwaitingPhase(
        parts[1],
        actionPhaseLabel(l10n, parts.length > 2 ? parts[2] : ''),
      ),
    // A code this build has no entry for is shown as its own code rather than
    // blank: the same fallback every vocabulary lookup in this directory takes.
    _ => message,
  };
}
