/// The Actions Module's HTTP surface, from the Flutter app's side.
///
/// Its own class next to its own Module, mirroring
/// `maintenance/maintenance_api.dart` — the client half of ADR-0012's
/// Module-for-Module mirror. Nothing here reads a People endpoint: the
/// register's Site chooser and the raise form's owner picker call `PeopleApi`
/// directly, the same way the Asset register does.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'action.dart';
import 'capa.dart';

/// The request could not be answered at all. Deliberately its own type rather
/// than People's `PeopleApiException` or Maintenance's: ADR-0006's third clause
/// keeps generic plumbing on each Module's own side, and the client mirrors it.
class ActionsApiException implements Exception {
  ActionsApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ActionsApi {
  ActionsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// A Site's action log (issue #176) — open Actions by default, history when
  /// [includeHistory] asks for it, narrowed by whichever filters are set. The
  /// API reads Site-wide whatever the caller's Grants, so nothing is filtered
  /// here either.
  Future<ActionRegister> fetchActions(
    String accessToken, {
    required String siteId,
    String? orgUnitId,
    String? status,
    String? actionType,
    String? ownerEmployeeId,
    String? pillarCode,
    String? escalatedToOrgUnitId,
    bool includeHistory = false,
  }) async {
    final path = '/api/actions/sites/$siteId/actions';
    final query = <String, String>{
      'orgUnitId': ?orgUnitId,
      'status': ?status,
      'actionType': ?actionType,
      'ownerEmployeeId': ?ownerEmployeeId,
      'pillarCode': ?pillarCode,
      'escalatedToOrgUnitId': ?escalatedToOrgUnitId,
      if (includeHistory) 'includeHistory': 'true',
    };
    final uri = Uri.parse(path)
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    final body = _decode(response, path);
    return ActionRegister(
      actions: [
        for (final action in body['actions'] as List<dynamic>)
          _actionFrom(action as Map<String, dynamic>),
      ],
      truncated: body['truncated'] == true,
    );
  }

  /// One Action (`GET /api/actions/:id`), with the collections a detail read
  /// carries: its parent and its measures.
  Future<Action> fetchAction(String accessToken, String id) async {
    final path = '/api/actions/$id';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Raises one Action (issue #176).
  ///
  /// The Org Unit is required and is the caller's decision; everything else is
  /// optional, and each null is left out of the body rather than sent as one —
  /// so the server's own defaults (type `concern`, priority 3, no due date)
  /// are what a caller gets when they choose nothing, rather than this client
  /// inventing a value the form never showed.
  Future<Action> raiseAction(
    String accessToken, {
    required String siteId,
    required String orgUnitId,
    required String title,
    String? description,
    String? actionType,
    String? pillarCode,
    String? ownerEmployeeId,
    String? dueDate,
    int? priority,
  }) async {
    final path = '/api/actions/sites/$siteId/actions';
    final body = <String, dynamic>{
      'orgUnitId': orgUnitId,
      'title': title,
      'description': ?description,
      'actionType': ?actionType,
      'pillarCode': ?pillarCode,
      'ownerEmployeeId': ?ownerEmployeeId,
      'dueDate': ?dueDate,
      'priority': ?priority,
    };
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Raises a measure against the Concern it answers (issue #178).
  ///
  /// A measure is an Action, so everything except the parent link is the raise
  /// form's own body — and every optional field is left out rather than sent as
  /// a null, so the server's defaults are what a caller gets when they choose
  /// nothing.
  Future<Action> raiseMeasure(
    String accessToken,
    String concernId, {
    required String actionType,
    required String title,
    String? description,
    String? orgUnitId,
    String? ownerEmployeeId,
    String? dueDate,
    int? priority,
  }) async {
    final path = '/api/actions/$concernId/measures';
    final body = <String, dynamic>{
      'actionType': actionType,
      'title': title,
      'description': ?description,
      'orgUnitId': ?orgUnitId,
      'ownerEmployeeId': ?ownerEmployeeId,
      'dueDate': ?dueDate,
      'priority': ?priority,
    };
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Completes the Action's open phase (issue #177) and answers with the
  /// Action as it now stands, phases included — so the caller renders the row
  /// the server just wrote rather than a guess at it.
  ///
  /// `outcome` is sent only when a verdict was chosen: a plan, a do and an act
  /// have none, and sending `null` for them would be this client inventing a
  /// field the server refuses.
  Future<Action> completePhase(
    String accessToken,
    String actionId,
    String phase, {
    required String note,
    String? outcome,
  }) async {
    final path = '/api/actions/$actionId/phases/$phase/complete';
    final body = <String, dynamic>{'note': note, 'outcome': ?outcome};
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// The Org Units this Action may be handed up to (issue #180): the ones
  /// **above** the Org Unit it sits at, nearest first, as the server works them
  /// out from the tree.
  ///
  /// Served rather than assembled here on purpose: what counts as "above" is
  /// the Site's own hierarchy, and a client that computed it would be a second
  /// implementation of the ltree rule.
  Future<List<EscalationTarget>> fetchEscalationTargets(String accessToken, String actionId) async {
    final path = '/api/actions/$actionId/escalation-targets';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    return [
      for (final target in _decode(response, path)['targets'] as List<dynamic>)
        EscalationTarget(
          id: (target as Map<String, dynamic>)['id'].toString(),
          code: target['code'] as String,
          name: target['name'] as String,
        ),
    ];
  }

  /// Hands one Action up to an Org Unit above it (issue #180).
  Future<Action> escalateAction(
    String accessToken,
    String actionId, {
    required String orgUnitId,
  }) async {
    final path = '/api/actions/$actionId/escalate';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'orgUnitId': orgUnitId}),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Calls one Action off (issue #179).
  ///
  /// The reason is optional and only sent when there is one: cancelling
  /// withdraws a claim rather than making one, so it carries no evidence and
  /// the server COALESCEs whatever arrives over any note already on the row.
  Future<Action> cancelAction(String accessToken, String actionId, {String? reason}) async {
    final path = '/api/actions/$actionId/cancel';
    final body = <String, dynamic>{'reason': ?reason};
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Raises a Concern from a Non-conformance (issue #208).
  ///
  /// The Org Unit is deliberately NOT in the body: the Concern lands at the
  /// Non-conformance's own Org Unit, because a problem is solved where it
  /// happened, and the server resolves it from the record rather than trusting
  /// a caller to name it. Every other field is the raise form's own, and each
  /// optional one is left out rather than sent as a null so the server's own
  /// defaults are what a caller gets when they choose nothing.
  Future<Action> raiseConcernFromNonconformance(
    String accessToken,
    String nonconformanceId, {
    required String title,
    String? description,
    String? pillarCode,
    String? ownerEmployeeId,
    String? dueDate,
    int? priority,
  }) async {
    final path = '/api/actions/nonconformances/$nonconformanceId/concern';
    final body = <String, dynamic>{
      'title': title,
      'description': ?description,
      'pillarCode': ?pillarCode,
      'ownerEmployeeId': ?ownerEmployeeId,
      'dueDate': ?dueDate,
      'priority': ?priority,
    };
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Links a further Non-conformance to an existing Concern (issue #208).
  ///
  /// The act is on the Concern — one problem answering several occurrences
  /// stays one Concern — so the address is the Concern's and the record to
  /// gather is the body. The answer is the Concern, with every occurrence it
  /// now answers.
  Future<Action> linkNonconformance(
    String accessToken,
    String concernId, {
    required String nonconformanceId,
  }) async {
    final path = '/api/actions/$concernId/nonconformances';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'nonconformanceId': nonconformanceId}),
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Unlinks a Non-conformance from a Concern (issue #208) — its own address
  /// rather than a DELETE, following every other change to an Action
  /// (`/cancel`, `/escalate`): the server answers with the Concern as it now
  /// stands, so nothing about the Screen reading it has to change.
  Future<Action> unlinkNonconformance(
    String accessToken,
    String concernId,
    String nonconformanceId,
  ) async {
    final path = '/api/actions/$concernId/nonconformances/$nonconformanceId/unlink';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
      ),
      path,
    );
    return _actionFrom(_decode(response, path)['action'] as Map<String, dynamic>);
  }

  /// Opens a CAPA on a Concern (issue #209, ADR-0034) — the Actions Module's
  /// own write, on the Concern's own address, answering with the investigation
  /// it created.
  ///
  /// The Org Unit is deliberately not in the body: a CAPA is filed at the
  /// Concern's own Org Unit and follows it if the Concern is escalated, so the
  /// server resolves it from the record rather than trusting a caller to name
  /// it. Everything else a caller may choose is optional and left out rather
  /// than sent as a null, so the server's own defaults are what a caller gets
  /// when they choose nothing — including a CAPA with no team and no problem
  /// description yet, which is a real state: the judgement is that this problem
  /// needs an investigation, and who investigates it may be decided next.
  Future<Capa> openCapa(
    String accessToken,
    String concernId, {
    String? teamLeadEmployeeId,
    List<String> teamMemberEmployeeIds = const [],
    String? problemStatement,
    String? dueDate,
  }) async {
    final path = '/api/actions/$concernId/capa';
    final body = <String, dynamic>{
      'teamLeadEmployeeId': ?teamLeadEmployeeId,
      'problemStatement': ?problemStatement,
      'dueDate': ?dueDate,
      // A team with nobody on it is the same fact as no team, so the list is
      // sent only when it has somebody in it — and a *replacement* list that
      // empties a team is a change, not this create.
      if (teamMemberEmployeeIds.isNotEmpty) 'teamMemberEmployeeIds': teamMemberEmployeeIds,
    };
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _capaFrom(_decode(response, path)['capa'] as Map<String, dynamic>);
  }

  /// One CAPA (`GET /api/actions/capas/:id`), with the Concern it is about —
  /// the Concern's own detail read, so its measures each carry the phases they
  /// have been round (issue #209).
  ///
  /// This is the read the CAPA's Screen makes: what D3-D7 of the 8D are is
  /// answered by the Concern's Containments, Countermeasures and Preventive
  /// actions, recorded once in the action log and shown here rather than
  /// recorded a second time.
  Future<Capa> fetchCapa(String accessToken, String id) async {
    final path = '/api/actions/capas/$id';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    return _capaFrom(_decode(response, path)['capa'] as Map<String, dynamic>);
  }

  /// The CAPA list (issue #211) — every investigation, worst first: the ones
  /// whose effectiveness check has fallen due, then the ones due soonest, then
  /// the most recently opened.
  ///
  /// No Site parameter, deliberately: a CAPA is identified by its own number
  /// and its own read has no Site in the address either, and the filter that
  /// names an *area* is the Org Unit one. Nothing here is filtered by Grant —
  /// the server reads the list platform-wide for any approved Account — so a
  /// narrowed read is exactly the three filters the caller set.
  Future<CapaRegister> fetchCapas(
    String accessToken, {
    String? orgUnitId,
    String? status,
    bool overdue = false,
  }) async {
    const path = '/api/actions/capas';
    final query = <String, String>{
      'orgUnitId': ?orgUnitId,
      'status': ?status,
      if (overdue) 'overdue': 'true',
    };
    final uri = Uri.parse(path).replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    final body = _decode(response, path);
    return CapaRegister(
      capas: [
        for (final capa in body['capas'] as List<dynamic>)
          _capaFrom(capa as Map<String, dynamic>),
      ],
      truncated: body['truncated'] == true,
    );
  }

  /// Records a CAPA's effectiveness check (issue #211) — the act that closes
  /// the investigation or sends its Concern round again.
  ///
  /// Only the two fields the record keeps are sent: the verdict and the note.
  /// The verifier is the caller's own Account and the time is the server's,
  /// because a check recorded on somebody else's behalf is not a check, and
  /// the due date, the status and the Concern's reopening are consequences of
  /// the verdict rather than fields a client may choose. The answer is the
  /// whole CAPA as it now reads, so the Screen behind the dialog repaints from
  /// the server's own answer rather than by a second read.
  Future<Capa> recordEffectivenessCheck(
    String accessToken,
    String capaId, {
    required String outcome,
    required String note,
  }) async {
    final path = '/api/actions/capas/$capaId/effectiveness';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'outcome': outcome, 'note': note}),
      ),
      path,
    );
    return _capaFrom(_decode(response, path)['capa'] as Map<String, dynamic>);
  }

  /// Adds a Why to one of a CAPA's chains (issue #210) — `occurrence` or
  /// `escape`, at the next position of that chain.
  ///
  /// The position is not sent: "the next one" is the chain's own fact, and the
  /// server computes it inside the transaction that writes the row. The chain
  /// is a body field rather than an address of its own because a chain is a
  /// column of the Why, not a record.
  ///
  /// The answer is the whole CAPA as it now reads — every write in this slice
  /// answers that way, so the Screen showing the investigation is refreshed
  /// from the one response rather than by a second read.
  Future<Capa> addCapaWhy(
    String accessToken,
    String capaId, {
    required String chain,
    required String statement,
  }) async {
    final path = '/api/actions/capas/$capaId/whys';
    final response = await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'chain': chain, 'statement': statement}),
      ),
      path,
    );
    return _capaFrom(_decode(response, path)['capa'] as Map<String, dynamic>);
  }

  /// Revises one Why (issue #210): what it says, where it sits in its chain,
  /// and whether it is the chain's confirmed root cause.
  ///
  /// Each field is sent only when the caller names it, so a form that changed
  /// one thing cannot quietly rewrite the other two — and a body naming nothing
  /// is a 400 rather than a silent no-op. Marking a second Why as the root
  /// cause *replaces* the first rather than being refused, which is what the
  /// API means by "the chain stopped here".
  Future<Capa> updateCapaWhy(
    String accessToken,
    String capaId,
    String whyId, {
    String? statement,
    int? sequence,
    bool? isRoot,
  }) async {
    final path = '/api/actions/capas/$capaId/whys/$whyId';
    // Built in two steps rather than with the null-aware element syntax: an
    // `info`-level lint on that shape fails `flutter analyze` (the same rule
    // `AppSearchField`'s callers follow).
    final body = <String, dynamic>{};
    if (statement != null) body['statement'] = statement;
    if (sequence != null) body['sequence'] = sequence;
    if (isRoot != null) body['isRoot'] = isRoot;
    final response = await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
      path,
    );
    return _capaFrom(_decode(response, path)['capa'] as Map<String, dynamic>);
  }

  /// Removes one Why from a CAPA's chain (issue #210), leaving the chain's
  /// order contiguous — the server renumbers what is left.
  Future<Capa> removeCapaWhy(String accessToken, String capaId, String whyId) async {
    final path = '/api/actions/capas/$capaId/whys/$whyId';
    final response = await _send(
      () => _client.delete(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
      path,
    );
    return _capaFrom(_decode(response, path)['capa'] as Map<String, dynamic>);
  }

  /// The five Pillars, for the raise form's chooser (ADR-0023: a value with a
  /// known set is chosen, never typed).
  Future<List<Pillar>> fetchPillars(String accessToken) async {
    const path = '/api/actions/pillars';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    final body = _decode(response, path);
    return [
      for (final pillar in body['pillars'] as List<dynamic>)
        Pillar(
          code: (pillar as Map<String, dynamic>)['code'] as String,
          name: pillar['name'] as String,
          description: pillar['description'] as String?,
        ),
    ];
  }

  Map<String, dynamic> _decode(http.Response response, String path) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      throw ActionsApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One Action off the wire. Every id is a string: the server sends BIGINTs
  /// as strings, and a client that coerced them to int would break on the
  /// first id past 2^53.
  static Action _actionFrom(Map<String, dynamic> json) => Action(
        id: json['id'].toString(),
        actionNo: json['actionNo'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        actionType: json['actionType'] as String,
        pillarCode: json['pillarCode'] as String?,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitName: json['orgUnitName'] as String,
        siteId: json['siteId'].toString(),
        ownerEmployeeId: json['ownerEmployeeId']?.toString(),
        ownerName: json['ownerName'] as String?,
        raisedByEmployeeId: json['raisedByEmployeeId']?.toString(),
        raisedByName: json['raisedByName'] as String?,
        raisedAt: json['raisedAt'] == null ? null : DateTime.parse(json['raisedAt'] as String),
        dueDate: json['dueDate'] as String?,
        isOverdue: json['isOverdue'] == true,
        daysOverdue: json['daysOverdue'] as int?,
        priority: json['priority'] as int,
        status: json['status'] as String,
        completedAt: json['completedAt'] == null ? null : DateTime.parse(json['completedAt'] as String),
        closureNote: json['closureNote'] as String?,
        escalatedToOrgUnitId: json['escalatedToOrgUnitId']?.toString(),
        escalatedToOrgUnitName: json['escalatedToOrgUnitName'] as String?,
        escalatedAt: json['escalatedAt'] == null ? null : DateTime.parse(json['escalatedAt'] as String),
        sourceType: json['sourceType'] as String?,
        sourceNonconformanceId: json['sourceNonconformanceId']?.toString(),
        // The CAPA opened on this Action, if one has been (issue #209).
        capa: json['capa'] == null
            ? null
            : CapaLink(
                id: (json['capa'] as Map<String, dynamic>)['id'].toString(),
                capaNo: (json['capa'] as Map<String, dynamic>)['capaNo'] as String,
                status: (json['capa'] as Map<String, dynamic>)['status'] as String,
              ),
        parentId: json['parentId']?.toString(),
        measureCount: (json['measureCount'] as int?) ?? 0,
        countermeasureCount: (json['countermeasureCount'] as int?) ?? 0,
        openPhase: json['openPhase'] == null
            ? null
            : _phaseFrom(json['openPhase'] as Map<String, dynamic>),
        phases: [
          for (final phase in (json['phases'] as List<dynamic>? ?? const []))
            _phaseFrom(phase as Map<String, dynamic>),
        ],
        parent: json['parent'] == null
            ? null
            : _parentFrom(json['parent'] as Map<String, dynamic>),
        measures: [
          for (final measure in (json['measures'] as List<dynamic>? ?? const []))
            _actionFrom(measure as Map<String, dynamic>),
        ],
        // What this Concern answers (issue #208) — the Non-conformances, the
        // one it was raised from first. Always present on a detail read, and
        // absent from a register row, where an empty list is what the Screen
        // wants anyway.
        nonconformances: [
          for (final nonconformance in (json['nonconformances'] as List<dynamic>? ?? const []))
            LinkedNonconformance.fromJson(nonconformance as Map<String, dynamic>),
        ],
      );

  /// The Concern a measure answers, named rather than nested — see
  /// `ActionParent`.
  static ActionParent _parentFrom(Map<String, dynamic> json) => ActionParent(
        id: json['id'].toString(),
        actionNo: json['actionNo'] as String,
        title: json['title'] as String,
        actionType: json['actionType'] as String,
        status: json['status'] as String,
      );

  /// One CAPA off the wire (issue #209). Every id is a string for the same
  /// reason an Action's is: the server sends BIGINTs as strings, and a client
  /// that coerced them to int would break on the first id past 2^53.
  ///
  /// The Concern comes back through the Action parser rather than a second
  /// mapper of its own: a CAPA's `concern` *is* an Action's detail read — the
  /// same fields, the same measures, the same phases — and a second parser
  /// would be a second place for the two shapes to drift apart.
  static Capa _capaFrom(Map<String, dynamic> json) => Capa(
        id: json['id'].toString(),
        capaNo: json['capaNo'] as String,
        title: json['title'] as String,
        method: json['method'] as String,
        status: json['status'] as String,
        orgUnitId: json['orgUnitId'].toString(),
        orgUnitCode: json['orgUnitCode'] as String?,
        orgUnitName: json['orgUnitName'] as String,
        siteId: json['siteId'].toString(),
        problemStatement: json['problemStatement'] as String?,
        teamLead: json['teamLead'] == null
            ? null
            : _capaTeamMemberFrom(json['teamLead'] as Map<String, dynamic>),
        teamMembers: [
          for (final member in (json['teamMembers'] as List<dynamic>? ?? const []))
            _capaTeamMemberFrom(member as Map<String, dynamic>),
        ],
        whys: [
          for (final why in (json['whys'] as List<dynamic>? ?? const []))
            _capaWhyFrom(why as Map<String, dynamic>),
        ],
        openedAt: json['openedAt'] == null ? null : DateTime.parse(json['openedAt'] as String),
        dueDate: json['dueDate'] as String?,
        closedAt: json['closedAt'] == null ? null : DateTime.parse(json['closedAt'] as String),
        // The effectiveness check (issue #211). The delay is read with the
        // server's own default behind it, so a row written before the column
        // existed still reads as the 30 days the schema says.
        effectivenessCheckDelayDays: (json['effectivenessCheckDelayDays'] as int?) ?? 30,
        effectivenessCheckDueAt: json['effectivenessCheckDueAt'] as String?,
        effectivenessCheckOverdue: json['effectivenessCheckOverdue'] == true,
        effectivenessVerifiedAt: json['effectivenessVerifiedAt'] == null
            ? null
            : DateTime.parse(json['effectivenessVerifiedAt'] as String),
        effectivenessVerifiedBy: json['effectivenessVerifiedBy'] == null
            ? null
            : _capaVerifierFrom(json['effectivenessVerifiedBy'] as Map<String, dynamic>),
        effectivenessNote: json['effectivenessNote'] as String?,
        concern: json['concern'] == null
            ? null
            : _actionFrom(json['concern'] as Map<String, dynamic>),
      );

  /// The Account that recorded an effectiveness check (issue #211): the id an
  /// address would need and the name a person reads, which is what the row
  /// shows.
  static CapaVerifier _capaVerifierFrom(Map<String, dynamic> json) => CapaVerifier(
        accountId: json['accountId'].toString(),
        name: json['name'] as String? ?? '',
      );

  /// One Employee on a CAPA's team: the id an address needs and the name a
  /// person reads.
  static CapaTeamMember _capaTeamMemberFrom(Map<String, dynamic> json) => CapaTeamMember(
        employeeId: json['employeeId'].toString(),
        name: json['name'] as String? ?? '',
      );

  /// One Why of one of a CAPA's chains (issue #210). `sequence` is the chain's
  /// own 1-based position, which the server sends as a number and keeps
  /// contiguous — a client that renumbered them would be the second place the
  /// order is decided, so it is read and rendered as sent.
  static CapaWhy _capaWhyFrom(Map<String, dynamic> json) => CapaWhy(
        id: json['id'].toString(),
        chain: json['chain'] as String,
        sequence: json['sequence'] as int,
        statement: json['statement'] as String,
        isRoot: json['isRoot'] == true,
      );

  static ActionPhase _phaseFrom(Map<String, dynamic> json) => ActionPhase(
        cycle: json['cycle'] as int,
        phase: json['phase'] as String,
        id: json['id']?.toString(),
        ownerEmployeeId: json['ownerEmployeeId']?.toString(),
        ownerName: json['ownerName'] as String?,
        dueDate: json['dueDate'] as String?,
        completedAt:
            json['completedAt'] == null ? null : DateTime.parse(json['completedAt'] as String),
        outcome: json['outcome'] as String?,
        note: json['note'] as String?,
      );

  /// The same error shape Maintenance's and People's clients use: the server's
  /// own message where it sent one, and a status-and-path sentence where it did
  /// not — never a raw exception, which names internals a screen should not
  /// show.
  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw ActionsApiException('Could not reach the API: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ActionsApiException(
        _messageFrom(response) ?? 'The API answered ${response.statusCode} for $path.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  static String? _messageFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final message = body['message'];
      return message is String && message.isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }
}
