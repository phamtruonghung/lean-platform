/// The People Module's HTTP surface, from the Flutter app's side.
///
/// One call: "who does this session's token belong to, and is that Account
/// admitted yet?" — `GET /api/people/me`, the one endpoint an Account may
/// call before Approval (see `backend/src/modules/people/routes.js`).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

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
}
