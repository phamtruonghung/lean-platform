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
          OrgUnitNode(
            id: (orgUnit as Map<String, dynamic>)['id'].toString(),
            parentId: orgUnit['parentId']?.toString(),
            code: orgUnit['code'] as String,
            name: orgUnit['name'] as String,
            unitType: orgUnit['unitType'] as String,
          ),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

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
  /// Each row carries no job role and no Org Unit — `listEmployees`
  /// (directory.js) selects only the Employee's own columns, nothing joined
  /// in. See [Employee]'s own header.
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

  static Employee _employeeFrom(Map<String, dynamic> employee) => Employee(
        id: employee['id'].toString(),
        employeeNo: employee['employeeNo'] as String,
        displayName: employee['displayName'] as String,
        employmentType: employee['employmentType'] as String,
        isActive: employee['isActive'] == true,
      );

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
      displayName: employee['displayName'] as String,
      isActive: employee['isActive'] == true,
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
  /// [isLapsed] is not part of this: unlike `listAssigneeCandidates`,
  /// `getEmployeeDetail` (directory.js) does not compute it — its own skills
  /// query selects `assessed_on`/`expires_on` and nothing derived from them.
  /// [_isLapsed] below reproduces `QUALIFICATION_IS_CURRENT_SQL`'s own rule
  /// (`backend/src/modules/people/sql.js`) as closely as a client can:
  /// lapsed iff `expiresOn` is present and on or before today, compared as
  /// `YYYY-MM-DD` strings — never parsed into a `DateTime` and compared as an
  /// instant, since a DATE column has no time component to begin with
  /// (directory.js's own `toDateString` header). This is the one place in
  /// this app where "lapsed" is decided on the device clock rather than
  /// read off the wire; making `getEmployeeDetail` compute it server-side,
  /// the way `listAssigneeCandidates` already does, is a backend follow-up
  /// reported alongside this ticket rather than done here (no backend change
  /// is in scope for issue #86).
  static HeldSkill _qualificationFrom(Map<String, dynamic> skill) {
    final nested = skill['skill'] as Map<String, dynamic>;
    final expiresOn = skill['expiresOn'] as String?;
    return HeldSkill(
      id: skill['id'].toString(),
      skillId: nested['id'].toString(),
      code: nested['code'] as String,
      name: nested['name'] as String,
      proficiencyLevel: (skill['proficiencyLevel'] as num).toInt(),
      expiresOn: expiresOn,
      isLapsed: _isLapsed(expiresOn),
    );
  }

  static bool _isLapsed(String? expiresOn) {
    if (expiresOn == null) return false;
    final now = DateTime.now();
    final today = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return expiresOn.compareTo(today) <= 0;
  }

  /// The job role catalogue (`GET /api/people/job-roles`), for the
  /// Directory's own job role filter — active roles only, no Site needed
  /// (ADR-0005's shared catalogue). See job-roles.js's own header for why
  /// this needs no Grant either.
  Future<List<JobRole>> fetchJobRoles(String accessToken) async {
    const path = '/api/people/job-roles';
    final response = await _send(
      () => _client.get(Uri.parse(path), headers: {'authorization': 'Bearer $accessToken'}),
      path,
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return [
        for (final jobRole in body['jobRoles'] as List<dynamic>)
          JobRole(
            id: (jobRole as Map<String, dynamic>)['id'].toString(),
            code: jobRole['code'] as String,
            name: jobRole['name'] as String,
          ),
      ];
    } catch (error) {
      throw PeopleApiException('The API answered with something this app could not read: $error');
    }
  }

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
  /// copy so its messages stay byte-identical.
  Future<http.Response> _send(Future<http.Response> Function() send, String path) async {
    final http.Response response;
    try {
      response = await send();
    } catch (error) {
      throw PeopleApiException('Could not reach the API: $error');
    }
    if (response.statusCode != 200) {
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
