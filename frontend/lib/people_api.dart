/// The People Module's HTTP surface, from the Flutter app's side.
///
/// One call: "who does this session's token belong to, and is that Account
/// admitted yet?" — `GET /api/people/me`, the one endpoint an Account may
/// call before Approval (see `backend/src/modules/people/routes.js`).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'people/assignee_candidate.dart';
import 'people/employee.dart';
import 'people/job_role.dart';
import 'people/managed_account.dart';
import 'people/org_unit.dart';
import 'people/org_unit_scope.dart';
import 'people/pending_account.dart';
import 'people/skill.dart';

/// What the API answered for the caller's own Account: either it is still
/// waiting on Approval, or it is active and may use the rest of the API.
sealed class AccountStatus {
  const AccountStatus({required this.email});

  final String email;
}

class AccountPendingApproval extends AccountStatus {
  const AccountPendingApproval({required super.email});
}

class AccountActive extends AccountStatus {
  const AccountActive({
    required this.id,
    required super.email,
    required this.displayName,
    required this.role,
    this.orgUnitScope = const OrgUnitScope.nowhere(),
  });

  /// The caller's own Account id — what the Accounts Screen compares each row
  /// against, so it never offers an action on the caller's own Account that
  /// the server will refuse (issue #53).
  final String id;
  final String displayName;
  final String role;

  /// Where this Account may work (issue #43) — "nowhere" by default so a
  /// cached client that predates this field, or a response the API sent with
  /// no `orgUnitScope` at all, still constructs a valid [AccountActive].
  final OrgUnitScope orgUnitScope;
}

/// The request could not be answered at all — unreachable API, a malformed
/// response, an unexpected status code. Deliberately a different type from
/// [AccountPendingApproval]: per issue #6, "awaiting Approval" is not a
/// failure, and the app must be able to tell the two apart.
class PeopleApiException implements Exception {
  PeopleApiException(this.message, {this.statusCode});

  final String message;

  /// The HTTP status, when the request reached the API at all.
  final int? statusCode;

  @override
  String toString() => message;
}

/// One row's own reason a bulk import (issue #90, ADR-0011) refused it —
/// `{row, code, field, message}` exactly as `org-unit-import.js`'s
/// `addError` builds it: `row` is the 0-based index into the submitted
/// array, `code` is that row's own `code` value (not an error code — the
/// wire's own field name, kept as-is), `field` names which key was wrong.
class OrgUnitImportRowError {
  const OrgUnitImportRowError({required this.row, this.code, this.field, required this.message});

  final int row;
  final String? code;
  final String? field;
  final String message;
}

/// A bulk import's own `422`: distinct from every other refusal in this
/// Module (org-unit-import.js's own header), carrying one entry per
/// offending row rather than [PeopleApiException]'s bare [message]. A
/// subclass, not a wholly separate type, so a caller that only wants the
/// summary message can still catch it as a [PeopleApiException].
class OrgUnitImportException extends PeopleApiException {
  OrgUnitImportException(super.message, {required this.errors}) : super(statusCode: 422);

  final List<OrgUnitImportRowError> errors;
}

class PeopleApi {
  PeopleApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The URL is relative on purpose, for the same reason main.dart's health
  /// check is: the reverse proxy serves the app and the API from one
  /// hostname, so nothing here knows the API's address.
  Future<AccountStatus> fetchMe(String accessToken) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse('/api/people/me'),
        headers: {'authorization': 'Bearer $accessToken'},
      );
    } catch (error) {
      throw PeopleApiException('Could not reach the API: $error');
    }

    if (response.statusCode != 200) {
      throw PeopleApiException(
        'The API answered ${response.statusCode} for /api/people/me.',
        statusCode: response.statusCode,
      );
    }

    final Map<String, dynamic> body;
    final Map<String, dynamic> account;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
      account = body['account'] as Map<String, dynamic>;
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }

    final email = account['email'] as String;

    if (body['status'] == 'pending_approval') {
      return AccountPendingApproval(email: email);
    }

    final id = account['id'];
    if (id == null) {
      throw PeopleApiException('The API answered /api/people/me with no Account id.');
    }

    return AccountActive(
      id: id.toString(),
      email: email,
      displayName: account['displayName'] as String,
      role: account['role'] as String,
      orgUnitScope: _orgUnitScopeFrom(body['orgUnitScope']),
    );
  }

  /// The caller's own Org Unit scope, when the API sent one. Tolerant of its
  /// absence rather than fatal: a cached client can outlive a deploy, and an
  /// Account that cannot yet be told where it may work is still an Account
  /// that can sign in and see the Shell.
  static OrgUnitScope _orgUnitScopeFrom(Object? raw) {
    if (raw is! Map<String, dynamic>) return const OrgUnitScope.nowhere();
    final grants = raw['grants'];
    return OrgUnitScope(
      everywhere: raw['everywhere'] == true,
      grants: [
        if (grants is List<dynamic>)
          for (final grant in grants.whereType<Map<String, dynamic>>())
            OrgUnitGrant(
              orgUnitId: grant['orgUnitId'].toString(),
              siteId: grant['siteId'].toString(),
              canWrite: grant['canWrite'] == true,
            ),
      ],
    );
  }

  /// The Approval queue: every Account nobody has decided about yet
  /// (`GET /api/people/accounts/pending`, administrator only).
  Future<List<PendingAccount>> fetchPendingAccounts(String accessToken) async {
    final response = await _send(
      () => _client.get(
        Uri.parse('/api/people/accounts/pending'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
      '/api/people/accounts/pending',
    );

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final account in body['accounts'] as List<dynamic>)
          PendingAccount(
            id: (account as Map<String, dynamic>)['id'].toString(),
            email: account['email'] as String,
            waitingSince: DateTime.parse(account['createdAt'] as String),
          ),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Rejects an Account still waiting in the queue.
  ///
  /// `expectedApprovalStatus` is a precondition, not decoration: it is what
  /// makes the API refuse (409) rather than silently overwrite a decision
  /// another administrator made while this queue was on screen.
  Future<void> rejectPendingAccount(String accessToken, {required String accountId}) async {
    await _send(
      () => _client.post(
        Uri.parse('/api/people/accounts/$accountId/rejection'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'expectedApprovalStatus': 'pending'}),
      ),
      '/api/people/accounts/$accountId/rejection',
    );
  }

  /// Every Site this Account can see (`GET /api/people/sites`). The API
  /// filters the list itself — an administrator sees every Site, anyone else
  /// only the Sites they hold a Grant within.
  Future<List<Site>> fetchSites(String accessToken) async {
    final response = await _send(
      () => _client.get(
        Uri.parse('/api/people/sites'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
      '/api/people/sites',
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final site in body['sites'] as List<dynamic>)
          Site(
            id: (site as Map<String, dynamic>)['id'].toString(),
            code: site['code'] as String,
            name: site['name'] as String,
          ),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  /// One level of a Site's Org Unit tree
  /// (`GET /api/people/sites/:siteId/org-units[?parentId=]`).
  ///
  /// With no [parentId] this is the root level, and what comes back depends on
  /// the *caller*: an administrator gets the Site's own root Org Units; anyone
  /// else gets their own entry points, which can sit several levels deep and
  /// carry a real, non-null `parentId` (ADR-0008). Either way these rows are
  /// the top of what this caller can browse, so nothing here or above reads
  /// `parentId` to decide that.
  Future<List<OrgUnitNode>> fetchOrgUnits(
    String accessToken, {
    required String siteId,
    String? parentId,
  }) async {
    final path = '/api/people/sites/$siteId/org-units';
    final uri = Uri.parse(path).replace(
      queryParameters: parentId == null ? null : {'parentId': parentId},
    );
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final orgUnit in body['orgUnits'] as List<dynamic>)
          _orgUnitNodeFrom(orgUnit as Map<String, dynamic>),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static OrgUnitNode _orgUnitNodeFrom(Map<String, dynamic> orgUnit) => OrgUnitNode(
        id: orgUnit['id'].toString(),
        parentId: orgUnit['parentId']?.toString(),
        code: orgUnit['code'] as String,
        name: orgUnit['name'] as String,
        unitType: orgUnit['unitType'] as String,
        isActive: orgUnit['isActive'] == null ? true : orgUnit['isActive'] == true,
      );

  /// Creates a Site (`POST /api/people/sites`, administrator only, issue
  /// #90). [timezone] must be a real IANA zone — `sites_validate_timezone`
  /// (the baseline's own trigger) is what actually enforces that, surfaced
  /// here as an ordinary [PeopleApiException] carrying its message.
  /// [countryCode] is the only optional field (`plant.createSite`'s own
  /// contract).
  Future<void> createSite(
    String accessToken, {
    required String code,
    required String name,
    required String timezone,
    String? countryCode,
  }) async {
    const path = '/api/people/sites';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'name': name,
          'timezone': timezone,
          'countryCode': ?countryCode,
        }),
      ),
      path,
    );
  }

  /// Adds an Org Unit beneath [parentId], or starts a new root branch when
  /// [parentId] is left null (`POST /api/people/sites/:siteId/org-units`,
  /// issue #90). Gated by `requireOrgUnitCreateScope` server-side (ADR-0008):
  /// a root row is administrator-only, a row under a parent needs write scope
  /// on it — this method sends whatever the caller gives it and lets the
  /// server's own 403 (`OUTSIDE_GRANTED_ORG_UNITS`) be the real gate, the same
  /// division every other write in this Module keeps. [unitType] must be one
  /// of `plant.js`'s own `UNIT_TYPES`; [sortOrder] left null defers to the
  /// server's own default of 0.
  Future<void> createOrgUnit(
    String accessToken, {
    required String siteId,
    String? parentId,
    required String code,
    required String name,
    required String unitType,
    int? sortOrder,
  }) async {
    final path = '/api/people/sites/$siteId/org-units';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'parentId': ?parentId,
          'code': code,
          'name': name,
          'unitType': unitType,
          'sortOrder': ?sortOrder,
        }),
      ),
      path,
    );
  }

  /// Retires, or reinstates, an Org Unit (`PATCH /api/people/org-units/:id`,
  /// issue #90) — a flag, never a deletion (CONTEXT.md's own Org Unit entry).
  /// Write scope on the named Org Unit or an ancestor of it
  /// (`authorization.requireOrgUnitScope({ write: true })`); this is the only
  /// field the route accepts, and the server 400s if `isActive` is missing or
  /// not a boolean (plant-routes.js's own check), so this method always sends
  /// exactly that one key.
  Future<void> setOrgUnitActive(
    String accessToken,
    String orgUnitId, {
    required bool isActive,
  }) async {
    final path = '/api/people/org-units/$orgUnitId';
    await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'isActive': isActive}),
      ),
      path,
    );
  }

  /// Searches a Site's Org Units by partial, case-insensitive name, at any
  /// depth in one call (`GET /api/people/sites/:siteId/org-units/search`,
  /// issue #90/#35) — the gap `fetchOrgUnits`'s one-level-at-a-time browsing
  /// leaves, and the reason issue #24 was raised in the first place: an
  /// Account with a deep Grant should not have to walk down to it. [truncated]
  /// on the result names whether the server's own limit
  /// (`ORG_UNIT_SEARCH_LIMIT`, plant.js) cut the match list short — carried
  /// through rather than dropped, since acting on a silently incomplete list
  /// is exactly the failure this exists to avoid.
  Future<OrgUnitSearchResult> searchOrgUnits(
    String accessToken, {
    required String siteId,
    required String search,
  }) async {
    final path = '/api/people/sites/$siteId/org-units/search';
    final uri = Uri.parse(path).replace(queryParameters: {'search': search});
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return OrgUnitSearchResult(
        orgUnits: [
          for (final orgUnit in body['orgUnits'] as List<dynamic>)
            _orgUnitNodeFrom(orgUnit as Map<String, dynamic>),
        ],
        truncated: body['truncated'] == true,
      );
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  /// Imports a whole branch (or several) of a Site's Org Unit hierarchy in
  /// one call (`POST /api/people/sites/:siteId/org-units/import`, ADR-0011,
  /// issue #90). [orgUnits] is the raw row set — each row is
  /// `{code, name, unitType, parentCode, sortOrder}`, rows naming their own
  /// parent by `code` rather than by id, since most of a fresh branch has no
  /// id yet (`org-unit-import.js`'s own header). Validated whole before
  /// anything is applied; a `422` never lands here as an ordinary
  /// [PeopleApiException], because that type carries only a bare message and
  /// this failure is one entry per offending row — [OrgUnitImportException]
  /// is what this method throws instead, so the caller can render every row's
  /// own reason rather than a single flattened string.
  Future<void> importOrgUnits(
    String accessToken, {
    required String siteId,
    required List<Map<String, Object?>> orgUnits,
  }) async {
    final path = '/api/people/sites/$siteId/org-units/import';
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'orgUnits': orgUnits}),
      );
    } catch (error) {
      throw PeopleApiException('Could not reach the API: $error');
    }
    if (response.statusCode == 422) {
      throw _importFailureFrom(response);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PeopleApiException(
        _messageFrom(response) ?? 'The API answered ${response.statusCode} for $path.',
        statusCode: response.statusCode,
      );
    }
  }

  static OrgUnitImportException _importFailureFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final message = body['message'] as String? ?? 'The import contains invalid rows';
      return OrgUnitImportException(
        message,
        errors: [
          for (final error in body['errors'] as List<dynamic>? ?? const [])
            _importRowErrorFrom(error as Map<String, dynamic>),
        ],
      );
    } catch (error) {
      return OrgUnitImportException(
        'The API answered with something this app could not read: $error',
        errors: const [],
      );
    }
  }

  static OrgUnitImportRowError _importRowErrorFrom(Map<String, dynamic> error) => OrgUnitImportRowError(
        row: (error['row'] as num).toInt(),
        code: error['code'] as String?,
        field: error['field'] as String?,
        message: error['message'] as String,
      );

  /// Who a Work order could be given to, and what each currently holds
  /// (`GET /api/people/employees/assignee-candidates`, issue #62). Active
  /// Employees only — the server excludes Departed ones (AC8), so nothing
  /// filters here either. [orgUnitId] narrows to that Org Unit and everything
  /// beneath it; the assign dialog does not send one (#62's own decision — a
  /// central technician sits outside the Asset's own Org Unit).
  Future<List<AssigneeCandidate>> fetchAssigneeCandidates(
    String accessToken, {
    String? orgUnitId,
  }) async {
    const path = '/api/people/employees/assignee-candidates';
    final uri = Uri.parse(path).replace(
      queryParameters: orgUnitId == null ? null : {'orgUnitId': orgUnitId},
    );
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final candidate in body['candidates'] as List<dynamic>)
          _assigneeCandidateFrom(candidate as Map<String, dynamic>),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static AssigneeCandidate _assigneeCandidateFrom(Map<String, dynamic> candidate) {
    final skills = candidate['skills'];
    return AssigneeCandidate(
      id: candidate['id'].toString(),
      employeeNo: candidate['employeeNo'] as String,
      displayName: candidate['displayName'] as String,
      skills: [
        if (skills is List<dynamic>)
          for (final skill in skills.whereType<Map<String, dynamic>>()) _heldSkillFrom(skill),
      ],
    );
  }

  static HeldSkill _heldSkillFrom(Map<String, dynamic> skill) {
    final nested = skill['skill'] as Map<String, dynamic>;
    return HeldSkill(
      id: skill['id'].toString(),
      skillId: nested['id'].toString(),
      code: nested['code'] as String,
      name: nested['name'] as String,
      proficiencyLevel: (skill['proficiencyLevel'] as num).toInt(),
      expiresOn: skill['expiresOn'] as String?,
      isLapsed: skill['isLapsed'] == true,
    );
  }

  /// The Directory list (`GET /api/people/employees`, issue #86) — Active
  /// Employees by default, `includeDeparted: true` widens it. [search]
  /// narrows by name, [orgUnitId] and [jobRoleId] each narrow further; the
  /// server combines every filter given by AND (directory.js's own header).
  /// No Grant filtering at all — the whole Directory is readable by any
  /// approved Account regardless of their own Org Unit scope (ADR-0009), so
  /// nothing here narrows it either.
  ///
  /// Each row now names the Employee's current Org Unit and current job role
  /// (issue #91) — `listEmployees` (directory.js) resolves both in the same
  /// one query the list was always built from, never a query per Employee.
  /// See [Employee]'s own header.
  Future<List<Employee>> fetchEmployees(
    String accessToken, {
    String? search,
    String? orgUnitId,
    String? jobRoleId,
    bool includeDeparted = false,
  }) async {
    const path = '/api/people/employees';
    final queryParameters = <String, String>{
      if (search != null && search.isNotEmpty) 'search': search,
      'orgUnitId': ?orgUnitId,
      'jobRoleId': ?jobRoleId,
      // Exact string 'true' only, mirroring the server's own narrow check
      // (directory-routes.js) — never sent at all otherwise, so a stray
      // `includeDeparted=false` is never constructed here either.
      if (includeDeparted) 'includeDeparted': 'true',
    };
    final uri = Uri.parse(path)
        .replace(queryParameters: queryParameters.isEmpty ? null : queryParameters);
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final employee in body['employees'] as List<dynamic>)
          _employeeFrom(employee as Map<String, dynamic>),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static Employee _employeeFrom(Map<String, dynamic> employee) {
    final orgUnit = employee['orgUnit'] as Map<String, dynamic>?;
    final jobRole = employee['jobRole'] as Map<String, dynamic>?;
    return Employee(
      id: employee['id'].toString(),
      employeeNo: employee['employeeNo'] as String,
      displayName: employee['displayName'] as String,
      employmentType: employee['employmentType'] as String,
      isActive: employee['isActive'] == true,
      orgUnitName: orgUnit?['name'] as String?,
      jobRoleName: jobRole?['name'] as String?,
    );
  }

  /// One Employee's full record (`GET /api/people/employees/:id`, issue #86)
  /// — job role, Assignment history and skills, alongside the Employee
  /// record itself. No Grant filtering, the same as [fetchEmployees]
  /// (ADR-0009): any approved Account may open any Employee's detail view.
  Future<EmployeeDetail> fetchEmployeeDetail(String accessToken, String employeeId) async {
    final path = '/api/people/employees/$employeeId';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    return _employeeDetailFromResponse(response, path);
  }

  /// The caller's own Employee record (`GET /api/people/employees/me`), when
  /// this Account has one linked — what lets a Member reach their own record
  /// (AC7) without searching the Directory for themselves. The server 404s
  /// with its own message when this Account carries no `employeeId` at all
  /// (directory-routes.js's own comment); that 404 surfaces as an ordinary
  /// [PeopleApiException] here, ready for the Screen to show.
  Future<EmployeeDetail> fetchMyEmployeeRecord(String accessToken) async {
    const path = '/api/people/employees/me';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    return _employeeDetailFromResponse(response, path);
  }

  EmployeeDetail _employeeDetailFromResponse(http.Response response, String path) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return _employeeDetailFrom(body['employee'] as Map<String, dynamic>);
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static EmployeeDetail _employeeDetailFrom(Map<String, dynamic> employee) {
    final jobRole = employee['jobRole'] as Map<String, dynamic>?;
    final assignments = employee['assignments'] as List<dynamic>? ?? const [];
    final skills = employee['skills'] as List<dynamic>? ?? const [];
    return EmployeeDetail(
      id: employee['id'].toString(),
      employeeNo: employee['employeeNo'] as String,
      firstName: employee['firstName'] as String,
      lastName: employee['lastName'] as String,
      displayName: employee['displayName'] as String,
      isActive: employee['isActive'] == true,
      hiredOn: employee['hiredOn'] as String?,
      terminatedOn: employee['terminatedOn'] as String?,
      employmentType: employee['employmentType'] as String,
      workEmail: employee['workEmail'] as String?,
      jobRoleName: jobRole?['name'] as String?,
      assignments: [
        for (final assignment in assignments.whereType<Map<String, dynamic>>())
          _assignmentFrom(assignment),
      ],
      qualifications: [
        for (final skill in skills.whereType<Map<String, dynamic>>()) _qualificationFrom(skill),
      ],
    );
  }

  static EmployeeAssignment _assignmentFrom(Map<String, dynamic> assignment) {
    final orgUnit = assignment['orgUnit'] as Map<String, dynamic>?;
    final jobRole = assignment['jobRole'] as Map<String, dynamic>?;
    return EmployeeAssignment(
      id: assignment['id'].toString(),
      effectiveFrom: assignment['effectiveFrom'] as String,
      effectiveTo: assignment['effectiveTo'] as String?,
      isCurrent: assignment['isCurrent'] == true,
      orgUnitName: orgUnit?['name'] as String? ?? '—',
      jobRoleName: jobRole?['name'] as String?,
    );
  }

  /// A held qualification off the detail view, reusing [HeldSkill] — the same
  /// model `fetchAssigneeCandidates` already builds — rather than a second
  /// type of the same shape.
  ///
  /// [isLapsed] is read straight off the wire (issue #91): `getEmployeeDetail`
  /// (directory.js) now derives it from `QUALIFICATION_IS_CURRENT_SQL`
  /// (`backend/src/modules/people/sql.js`), the Module's own single
  /// definition of a current qualification, the same way
  /// `listAssigneeCandidates` already does — so this client never re-derives
  /// the date rule against the device clock.
  static HeldSkill _qualificationFrom(Map<String, dynamic> skill) {
    final nested = skill['skill'] as Map<String, dynamic>;
    return HeldSkill(
      id: skill['id'].toString(),
      skillId: nested['id'].toString(),
      code: nested['code'] as String,
      name: nested['name'] as String,
      proficiencyLevel: (skill['proficiencyLevel'] as num).toInt(),
      expiresOn: skill['expiresOn'] as String?,
      isLapsed: skill['isLapsed'] == true,
    );
  }

  /// Adds a new Employee (`POST /api/people/employees`, administrator only,
  /// issue #87). Required: [employeeNo], [firstName], [lastName]. Optional:
  /// [employmentType] (the server defaults it to `'permanent'`) and
  /// [workEmail].
  ///
  /// Returns nothing: `createEmployee`'s own RETURNING clause
  /// (`directory.js`) answers the bare `toEmployee` shape — no `orgUnit`, no
  /// `jobRole`, since those are resolved only by `listEmployees`'s own joins.
  /// Splicing this response straight into the Directory list would render the
  /// new row with neither until something else reloaded it, so the caller
  /// re-reads the list instead (`DirectoryBloc._onAddConfirmed`).
  Future<void> createEmployee(
    String accessToken, {
    required String employeeNo,
    required String firstName,
    required String lastName,
    String? employmentType,
    String? workEmail,
  }) async {
    const path = '/api/people/employees';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'employeeNo': employeeNo,
          'firstName': firstName,
          'lastName': lastName,
          'employmentType': ?employmentType,
          'workEmail': ?workEmail,
        }),
      ),
      path,
    );
  }

  /// Corrects an existing Employee's record
  /// (`PATCH /api/people/employees/:id`, administrator only, issue #87).
  /// [changes] is sent exactly as given — only the keys actually present are
  /// touched, mirroring the server's own `hasOwnProperty` rule
  /// (`updateEmployee`, directory.js): a one-field correction carries one
  /// field, never the whole record re-sent. Building that diff is
  /// `EmployeeCorrectionDialog`'s job, not this method's — it sends whatever
  /// it is given.
  ///
  /// `isActive` and `terminatedOn` are unreachable through this call: the
  /// server's own `EMPLOYEE_WRITABLE_COLUMNS` has no entry for either, by
  /// design (directory.js's own comment) — [setEmployeeDeparted] and
  /// [reinstateEmployee] are the only two routes into them.
  Future<void> updateEmployee(String accessToken, String id, Map<String, Object?> changes) async {
    final path = '/api/people/employees/$id';
    await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(changes),
      ),
      path,
    );
  }

  /// Records that an Employee has departed
  /// (`POST /api/people/employees/:id/departure`, administrator only, issue
  /// #87) — a flag and a date, never a deletion (CONTEXT.md's own Departed
  /// entry). [terminatedOn] is `YYYY-MM-DD`, the day it took effect; left
  /// null, the server defaults it to today.
  Future<void> setEmployeeDeparted(String accessToken, String id, {String? terminatedOn}) async {
    final path = '/api/people/employees/$id/departure';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'terminatedOn': ?terminatedOn}),
      ),
      path,
    );
  }

  /// Undoes a departure
  /// (`POST /api/people/employees/:id/reinstatement`, administrator only,
  /// issue #87) — the other half of [setEmployeeDeparted]. No body: reinstating
  /// asks for nothing.
  Future<void> reinstateEmployee(String accessToken, String id) async {
    final path = '/api/people/employees/$id/reinstatement';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(const {}),
      ),
      path,
    );
  }

  /// Assigns an Employee to an Org Unit, as a given job role, from a given
  /// date (`POST /api/people/employees/:id/assignments`, issue #88). Unlike
  /// every write above, this is not administrator-only — ADR-0010 gates it on
  /// write scope over the *destination* [orgUnitId] instead, so any caller
  /// holding a write Grant reaching that Org Unit may call it. A 403 here
  /// carries `OUTSIDE_GRANTED_ORG_UNITS`, surfaced like any other
  /// [PeopleApiException].
  ///
  /// [jobRoleId] is optional, matching `createAssignment`'s own contract
  /// (directory.js). [crewId] is never sent: crews have no client surface yet
  /// (issue #88's own out-of-scope note).
  ///
  /// Already holding an open Assignment turns this into a transfer, entirely
  /// server-side (directory.js's own header on `createAssignment`): the open
  /// one is closed with an end date and this one is opened. Returns nothing —
  /// the response is one Assignment, not the recomputed history with
  /// `isCurrent` resolved, so the caller re-reads the Employee's record
  /// instead (the same reason [updateEmployee]'s own callers do).
  Future<void> createAssignment(
    String accessToken,
    String employeeId, {
    required String orgUnitId,
    String? jobRoleId,
    required String effectiveFrom,
  }) async {
    final path = '/api/people/employees/$employeeId/assignments';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'orgUnitId': orgUnitId,
          'jobRoleId': ?jobRoleId,
          'effectiveFrom': effectiveFrom,
        }),
      ),
      path,
    );
  }

  /// The job role catalogue (`GET /api/people/job-roles`), for the
  /// Directory's own job role filter, an Assignment's own job role choice,
  /// and the job role catalogue Screen (issue #88) — active roles only by
  /// default, no Site needed (ADR-0005's shared catalogue). See
  /// job-roles.js's own header for why this needs no Grant either.
  ///
  /// [includeInactive] mirrors the server's own narrow `'true'`-exact check
  /// (job-role-routes.js) — only the catalogue Screen's administrator sends
  /// it, to reach a deactivated row worth reactivating; every other caller
  /// leaves it false and reads active roles only, exactly as before issue #88.
  Future<List<JobRole>> fetchJobRoles(String accessToken, {bool includeInactive = false}) async {
    const path = '/api/people/job-roles';
    final uri = Uri.parse(path).replace(
      queryParameters: includeInactive ? {'includeInactive': 'true'} : null,
    );
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final jobRole in body['jobRoles'] as List<dynamic>) _jobRoleFrom(jobRole as Map<String, dynamic>),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static JobRole _jobRoleFrom(Map<String, dynamic> jobRole) => JobRole(
        id: jobRole['id'].toString(),
        code: jobRole['code'] as String,
        name: jobRole['name'] as String,
        isActive: jobRole['isActive'] == true,
      );

  /// Adds a job role to the shared catalogue
  /// (`POST /api/people/job-roles`, administrator only, issue #88).
  Future<void> createJobRole(String accessToken, {required String code, required String name}) async {
    const path = '/api/people/job-roles';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({'code': code, 'name': name}),
      ),
      path,
    );
  }

  /// Corrects a job role, or deactivates/reactivates one
  /// (`PATCH /api/people/job-roles/:id`, administrator only, issue #88).
  /// [changes] is sent exactly as given — only the keys actually present are
  /// touched, mirroring `updateJobRole`'s (job-roles.js) own `hasOwnProperty`
  /// contract, the same discipline [updateEmployee] already keeps for the
  /// Employee record. There is no delete: `isActive: false` is the only way
  /// this reaches retirement (job-roles.js's own header).
  Future<void> updateJobRole(String accessToken, String id, Map<String, Object?> changes) async {
    final path = '/api/people/job-roles/$id';
    await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(changes),
      ),
      path,
    );
  }

  /// The skill catalogue (`GET /api/people/skills`, issue #89) — active
  /// skills only by default, no Site needed (ADR-0005's shared catalogue
  /// applies to `skills` the same way it does to `job_roles` — skills.js's
  /// own header). See `Skill`'s own header for why this needs no Grant
  /// either (skill-routes.js's own reasoning for `GET /skills`).
  ///
  /// [includeInactive] mirrors the server's own narrow `'true'`-exact check
  /// (skill-routes.js) — only the catalogue Screen's administrator sends it,
  /// to reach a deactivated row worth reactivating, the same shape
  /// [fetchJobRoles] already follows. [skillCategory] narrows to one of
  /// [skillCategories]; left null, every category is read.
  Future<List<Skill>> fetchSkills(
    String accessToken, {
    bool includeInactive = false,
    String? skillCategory,
  }) async {
    const path = '/api/people/skills';
    final uri = Uri.parse(path).replace(
      queryParameters: {
        if (includeInactive) 'includeInactive': 'true',
        'skillCategory': ?skillCategory,
      },
    );
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final skill in body['skills'] as List<dynamic>) _skillFrom(skill as Map<String, dynamic>),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static Skill _skillFrom(Map<String, dynamic> skill) => Skill(
        id: skill['id'].toString(),
        code: skill['code'] as String,
        name: skill['name'] as String,
        skillCategory: skill['skillCategory'] as String,
        requiresCertification: skill['requiresCertification'] == true,
        revalidationMonths: (skill['revalidationMonths'] as num?)?.toInt(),
        isActive: skill['isActive'] == true,
      );

  /// Adds a skill to the shared catalogue (`POST /api/people/skills`,
  /// administrator only, issue #89). [skillCategory] left null defers to the
  /// server's own default (`'operation'`, skills.js).
  Future<void> createSkill(
    String accessToken, {
    required String code,
    required String name,
    String? skillCategory,
    bool? requiresCertification,
    int? revalidationMonths,
  }) async {
    const path = '/api/people/skills';
    await _send(
      () => _client.post(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'name': name,
          'skillCategory': ?skillCategory,
          'requiresCertification': ?requiresCertification,
          'revalidationMonths': ?revalidationMonths,
        }),
      ),
      path,
    );
  }

  /// Corrects a skill, or deactivates/reactivates one
  /// (`PATCH /api/people/skills/:id`, administrator only, issue #89).
  /// [changes] is sent exactly as given — only the keys actually present are
  /// touched, the same `hasOwnProperty` contract [updateJobRole] already
  /// keeps, on `updateSkill`'s (skills.js) own end. There is no delete:
  /// `isActive: false` is the only way this reaches deactivation
  /// (skills.js's own header).
  Future<void> updateSkill(String accessToken, String id, Map<String, Object?> changes) async {
    final path = '/api/people/skills/$id';
    await _send(
      () => _client.patch(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode(changes),
      ),
      path,
    );
  }

  /// Records, or re-assesses, an Employee holding a skill
  /// (`PUT /api/people/employees/:id/skills/:skillId`, administrator only,
  /// issue #89) — an upsert, always answering 200 whether this is the first
  /// assessment or the fifth (skill-routes.js's own header), so this one
  /// method covers both; the caller never needs to know which it is.
  /// [proficiencyLevel] is 0–4 on the ILUO scale; [assessedOn] left null
  /// defers to the server's own default of today. Returns nothing — the
  /// response is the bare `employee_skills` row, not the recomputed
  /// `EmployeeDetail` with `isLapsed` resolved, so the caller re-reads the
  /// Employee's record instead, the same reason [createAssignment]'s own
  /// callers do.
  Future<void> recordEmployeeSkill(
    String accessToken,
    String employeeId,
    String skillId, {
    required int proficiencyLevel,
    String? assessedOn,
    String? expiresOn,
    String? evidenceRef,
    String? note,
  }) async {
    final path = '/api/people/employees/$employeeId/skills/$skillId';
    await _send(
      () => _client.put(
        Uri.parse(path),
        headers: {'authorization': 'Bearer $accessToken', 'content-type': 'application/json'},
        body: jsonEncode({
          'proficiencyLevel': proficiencyLevel,
          'assessedOn': ?assessedOn,
          'expiresOn': ?expiresOn,
          'evidenceRef': ?evidenceRef,
          'note': ?note,
        }),
      ),
      path,
    );
  }

  /// Who holds a skill, scoped to an Org Unit and filtered by a minimum
  /// proficiency level (`GET /api/people/skills/:id/qualified-employees`,
  /// issue #89). [orgUnitId] is required here, not optional — the route
  /// itself 400s without it (skill-routes.js's own header: "the criterion is
  /// explicitly scoped to an Org Unit"), so this method carries that same
  /// requirement rather than letting a caller construct a request the server
  /// would refuse. [minimumLevel] left null defers to the server's own
  /// default of 1 (skills.js's own `validateMinimumLevel`) — 0 is never a
  /// real minimum on the ILUO scale.
  Future<List<QualifiedEmployee>> fetchQualifiedEmployees(
    String accessToken,
    String skillId, {
    required String orgUnitId,
    int? minimumLevel,
  }) async {
    final path = '/api/people/skills/$skillId/qualified-employees';
    final uri = Uri.parse(path).replace(
      queryParameters: {
        'orgUnitId': orgUnitId,
        if (minimumLevel != null) 'minimumLevel': minimumLevel.toString(),
      },
    );
    final response = await _send(
      () => _client.get(uri, headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final employee in body['employees'] as List<dynamic>)
          _qualifiedEmployeeFrom(employee as Map<String, dynamic>),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static QualifiedEmployee _qualifiedEmployeeFrom(Map<String, dynamic> employee) => QualifiedEmployee(
        id: employee['id'].toString(),
        employeeNo: employee['employeeNo'] as String,
        displayName: employee['displayName'] as String,
        proficiencyLevel: (employee['proficiencyLevel'] as num).toInt(),
        expiresOn: employee['expiresOn'] as String?,
      );

  /// A Site's skill coverage — where it is short
  /// (`GET /api/people/sites/:siteId/skill-coverage`, administrator only,
  /// issue #89). Deliberately narrower than every other Site-shaped read
  /// this client makes (skill-routes.js's own header compares it to
  /// `GET /accounts`) — "how the plant is being run", not "who works here".
  /// Already filtered to a real shortfall server-side; see
  /// `SkillCoverageEntry`'s own header.
  Future<List<SkillCoverageEntry>> fetchSiteSkillCoverage(String accessToken, String siteId) async {
    final path = '/api/people/sites/$siteId/skill-coverage';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final entry in body['coverage'] as List<dynamic>)
          _skillCoverageEntryFrom(entry as Map<String, dynamic>),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static SkillCoverageEntry _skillCoverageEntryFrom(Map<String, dynamic> entry) => SkillCoverageEntry(
        orgUnitId: entry['orgUnitId'].toString(),
        orgUnitCode: entry['orgUnitCode'] as String,
        orgUnitName: entry['orgUnitName'] as String,
        skillId: entry['skillId'].toString(),
        skillCode: entry['skillCode'] as String,
        skillName: entry['skillName'] as String,
        minimumLevel: (entry['minimumLevel'] as num).toInt(),
        minimumQualifiedHeadcount: (entry['minimumQualifiedHeadcount'] as num).toInt(),
        qualifiedHeadcount: (entry['qualifiedHeadcount'] as num).toInt(),
        expiredHeadcount: (entry['expiredHeadcount'] as num).toInt(),
        shortfall: (entry['shortfall'] as num).toInt(),
      );

  /// Admits an Account: sets its role and its Grants in one act
  /// (`POST /api/people/accounts/:id/approval`, administrator only). The
  /// server writes both in one transaction, so no Account is observably left
  /// with a new role and the old Grants, or the reverse.
  ///
  /// [grants] is the *whole* Grant set the Account will hold, not an addition
  /// to one: `approveAccount` deletes every existing row and re-inserts this
  /// list (`backend/src/modules/people/service.js`), so an empty list means
  /// "no Grants at all", which is exactly right for an administrator. Each
  /// entry is `{'orgUnitId': <id>, 'canWrite': <bool>}`; the id is sent as the
  /// string the API answered with, which is what `parseId` accepts and what
  /// BIGINT columns come back as over JSON.
  ///
  /// `expectedApprovalStatus` is the same precondition [rejectPendingAccount]
  /// sends, for the same reason: a 409 rather than a silent overwrite of a
  /// decision another administrator made while this queue was on screen.
  ///
  /// [expectedApprovalStatus] is required, not defaulted to `'pending'`, so
  /// this one method can serve both admitting a pending Account and
  /// correcting an already-admitted one (issue #36): the precondition is
  /// whichever standing the caller actually read the Account at.
  Future<void> admitAccount(
    String accessToken, {
    required String accountId,
    required String role,
    required String expectedApprovalStatus,
    List<Map<String, Object?>> grants = const [],
  }) async {
    await _send(
      () => _client.post(
        Uri.parse('/api/people/accounts/$accountId/approval'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'role': role,
          'grants': grants,
          'expectedApprovalStatus': expectedApprovalStatus,
        }),
      ),
      '/api/people/accounts/$accountId/approval',
    );
  }

  /// Every Account the server knows about (`GET /api/people/accounts`,
  /// administrator only), each carrying the decision made about it and the
  /// whole Grant set it currently holds. Nothing is filtered here: which of
  /// these rows a Screen shows is the Screen's business.
  Future<List<ManagedAccount>> fetchAccounts(String accessToken) async {
    final response = await _send(
      () => _client.get(
        Uri.parse('/api/people/accounts'),
        headers: {'authorization': 'Bearer $accessToken'},
      ),
      '/api/people/accounts',
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final account in body['accounts'] as List<dynamic>)
          _managedAccountFrom(account as Map<String, dynamic>),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

  static ManagedAccount _managedAccountFrom(Map<String, dynamic> account) {
    final grants = account['grants'];
    return ManagedAccount(
      id: account['id'].toString(),
      email: account['email'] as String,
      displayName: account['displayName'] as String? ?? account['email'] as String,
      role: account['role'] as String,
      isActive: account['isActive'] == true,
      approvalStatus: account['approvalStatus'] as String,
      createdAt: DateTime.parse(account['createdAt'] as String),
      grants: [
        if (grants is List<dynamic>)
          for (final grant in grants.whereType<Map<String, dynamic>>())
            AccountGrant(
              orgUnitId: grant['orgUnitId'].toString(),
              parentId: grant['parentId']?.toString(),
              code: grant['code'] as String,
              name: grant['name'] as String,
              unitType: grant['unitType'] as String,
              siteId: grant['siteId'].toString(),
              siteName: grant['siteName'] as String,
              canWrite: grant['canWrite'] == true,
            ),
      ],
    );
  }

  /// Deactivates or reactivates an admitted Account
  /// (`PATCH /api/people/accounts/:id`, administrator only). Not a deletion:
  /// the Account, its role and its Grants all stay exactly as they were, and
  /// the same call puts it back. The server refuses this for an Account that
  /// is not `approved` — a pending or rejected one is admitted through
  /// [admitAccount] instead.
  Future<void> setAccountActive(
    String accessToken, {
    required String accountId,
    required bool isActive,
  }) async {
    await _send(
      () => _client.patch(
        Uri.parse('/api/people/accounts/$accountId'),
        headers: {
          'authorization': 'Bearer $accessToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'isActive': isActive}),
      ),
      '/api/people/accounts/$accountId',
    );
  }

  /// The one place a request's transport failure and its non-2xx status turn
  /// into a [PeopleApiException] — `fetchMe` predates this and keeps its own
  /// copy so its messages stay byte-identical. Accepts any 2xx, not only 200
  /// (issue #87): `createEmployee` answers 201, the same reason
  /// `MaintenanceApi._send` already accepts any 2xx rather than one exact code.
  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw PeopleApiException('Could not reach the API: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PeopleApiException(
        _messageFrom(response) ?? 'The API answered ${response.statusCode} for $path.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  /// The API's own `{ "message": ... }`, when it sent one — the backend's
  /// `errors.js handleError` answers every refusal in that shape.
  static String? _messageFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['message'] is String) {
        return body['message'] as String;
      }
    } catch (_) {
      // Not JSON, or not that shape: the caller's generic message stands.
    }
    return null;
  }
}
