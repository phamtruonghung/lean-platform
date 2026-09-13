/// Where an Account may work, as `GET /api/people/me` answers it.
///
/// An administrator reaches every Site by virtue of the role and holds no
/// Grants at all, so [everywhere] is the answer and [grants] is empty — never
/// read an empty [grants] as "nowhere" without checking [everywhere] first.
///
/// These are the caller's raw Grants, not their entry points. "Where does my
/// scope begin in *this* Site's tree" is a per-Site question the API answers
/// on demand from `GET /sites/:siteId/org-units` with no parentId (ADR-0008);
/// nothing here re-derives it.
///
/// Each Grant also names the Org Units it *reaches* — the granted unit plus
/// every descendant beneath it (issue #110, ADR-0027). A Grant reaches
/// downward, so the server walks that subtree (the same `path <@` containment
/// `canAct` uses) and hands the client a flat list of ids to match against;
/// [OrgUnitScope.reachesOrgUnit] and [OrgUnitScope.canWriteAt] are that match,
/// the one mechanism both Home's awaiting-assignment count and
/// `canAssignWorkOrder` read. A Grant sent without an explicit list — an older
/// server, or a hand-written fixture — reaches only its own Org Unit, which is
/// the pre-#110 reading and never a wider one.
library;

import 'package:flutter/foundation.dart';

@immutable
class OrgUnitGrant {
  const OrgUnitGrant({
    required this.orgUnitId,
    required this.siteId,
    required this.canWrite,
    this.orgUnitIds,
  });

  /// The Org Unit this Grant was made on — the top of what it reaches, not
  /// the whole of it.
  final String orgUnitId;

  final String siteId;
  final bool canWrite;

  /// Every Org Unit id this Grant reaches, granted unit included, as `/me`
  /// reports it (issue #110). Null when the server did not send one.
  final List<String>? orgUnitIds;

  /// The ids this Grant actually reaches: the server's own list when it sent
  /// one, else just [orgUnitId] — never an empty list, which would read as a
  /// Grant that reaches nothing.
  List<String> get reachedOrgUnitIds => orgUnitIds ?? [orgUnitId];
}

@immutable
class OrgUnitScope {
  const OrgUnitScope({required this.everywhere, required this.grants});

  /// No Grants and not an administrator: this Account reaches nothing yet.
  const OrgUnitScope.nowhere()
      : everywhere = false,
        grants = const [];

  final bool everywhere;
  final List<OrgUnitGrant> grants;

  /// Whether this Account may edit anything, anywhere — the everywhere-first
  /// rule expressed once so no Screen has to remember it.
  bool get canWriteSomewhere => everywhere || grants.any((grant) => grant.canWrite);

  /// Whether this Account holds a Grant reaching anywhere at all, write or
  /// read. Raising a Request needs only a read Grant reaching the Asset's Org
  /// Unit (issue #72, the server passes `write: false`), so the raise
  /// affordance reads this rather than [canWriteSomewhere] — a read-only Grant
  /// the server would allow to raise must not be hidden.
  bool get canReadSomewhere => everywhere || grants.isNotEmpty;

  /// Whether any Grant of this Account reaches [orgUnitId] — the unit itself
  /// or, since a Grant reaches downward, any descendant of it (issue #110,
  /// ADR-0027). An administrator reaches everywhere.
  bool reachesOrgUnit(String orgUnitId) =>
      everywhere ||
      grants.any((grant) => grant.reachedOrgUnitIds.contains(orgUnitId));

  /// Whether any *write* Grant of this Account reaches [orgUnitId] — the same
  /// downward-reach test [reachesOrgUnit] makes, restricted to the Grants
  /// whose `canWrite` is true. This is the per-record counterpart to
  /// [canWriteSomewhere]: it answers "may I act on this particular Org Unit",
  /// which is what a per-row affordance (and the server's own
  /// `canAct({ write: true })`) actually asks. An administrator reaches
  /// everywhere.
  bool canWriteAt(String orgUnitId) =>
      everywhere ||
      grants.any((grant) => grant.canWrite && grant.reachedOrgUnitIds.contains(orgUnitId));
}
