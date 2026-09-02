/// The People Module's HTTP surface, from the Flutter app's side.
///
/// One call: "who does this session's token belong to, and is that Account
/// admitted yet?" — `GET /api/people/me`, the one endpoint an Account may
/// call before Approval (see `backend/src/modules/people/routes.js`).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'people/org_unit.dart';
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
  const AccountActive({required super.email, required this.displayName, required this.role});

  final String displayName;
  final String role;
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

    return AccountActive(
      email: email,
      displayName: account['displayName'] as String,
      role: account['role'] as String,
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
  Future<void> approvePendingAccount(
    String accessToken, {
    required String accountId,
    required String role,
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
          'expectedApprovalStatus': 'pending',
        }),
      ),
      '/api/people/accounts/$accountId/approval',
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
