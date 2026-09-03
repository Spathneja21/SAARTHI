import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Something went wrong talking to the backend.
///
/// Carries the HTTP status so callers can distinguish "you are not signed in"
/// from "that does not exist" from "the server is misconfigured", and a message
/// already extracted from FastAPI's response shape.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body});

  final int statusCode;
  final String message;
  final Object? body;

  /// The caller's token is missing, expired or rejected. The app should send the
  /// user back to sign-in. Note the backend answers 401 for both a *missing*
  /// header and a *bad* token, so both land here.
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  /// The requested resource does not exist — or belongs to another user. The
  /// backend deliberately returns 404 rather than 403 for someone else's task,
  /// so this does not leak whether that id exists.
  bool get isNotFound => statusCode == 404;

  /// Request body failed validation. `message` holds FastAPI's field detail.
  bool get isValidationError => statusCode == 422;

  /// Server-side misconfiguration — in practice, a missing Firebase
  /// service-account key. Retrying will not help; do NOT treat it as a sign-out.
  bool get isServerMisconfigured => statusCode == 503;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thrown when the device cannot reach the backend at all.
class ApiUnreachableException implements Exception {
  ApiUnreachableException(this.baseUrl, this.cause);

  final String baseUrl;
  final Object cause;

  @override
  String toString() =>
      'Could not reach the AURA backend at $baseUrl. '
      'Is it running, and is the base URL right for this platform? ($cause)';
}

/// Thin JSON client over the AURA backend.
///
/// Every request carries the caller's Firebase ID token as a Bearer header.
/// Tokens are fetched per request rather than cached: `getIdToken()` returns a
/// cached value until roughly five minutes before expiry and refreshes
/// transparently, so the SDK already does the caching correctly and doing it
/// again here would only risk sending a stale one.
class ApiClient {
  /// Uses the signed-in Firebase user's ID token.
  ApiClient({http.Client? httpClient, FirebaseAuth? auth, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _tokenProvider = _firebaseTokenProvider(auth ?? FirebaseAuth.instance),
        _baseUrlOverride = baseUrl;

  /// Takes the token from an arbitrary source instead of Firebase.
  ///
  /// Exists so the client, DTO parsing and error handling can be exercised
  /// against a real backend without booting Firebase — plain `flutter test` has
  /// no platform channels, so `FirebaseAuth.instance` cannot work there.
  ApiClient.withTokenProvider(
    this._tokenProvider, {
    http.Client? httpClient,
    String? baseUrl,
  })  : _http = httpClient ?? http.Client(),
        _baseUrlOverride = baseUrl;

  final http.Client _http;
  final Future<String?> Function() _tokenProvider;
  final String? _baseUrlOverride;

  String get baseUrl => _baseUrlOverride ?? ApiConfig.baseUrl;

  static Future<String?> Function() _firebaseTokenProvider(FirebaseAuth auth) {
    return () async {
      final user = auth.currentUser;
      if (user == null) {
        throw ApiException(401, 'Not signed in.');
      }
      try {
        // Returns a cached token until roughly five minutes before expiry and
        // refreshes transparently, so there is no need to cache it again here.
        return await user.getIdToken();
      } on FirebaseAuthException catch (e) {
        // The account was disabled or deleted while the app was open, so no
        // valid token can be minted. Surface as unauthorized, not a crash.
        throw ApiException(401, 'Could not refresh sign-in: ${e.code}');
      }
    };
  }

  Future<Map<String, String>> _headers({bool withBody = false}) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw ApiException(401, 'Could not obtain an authentication token.');
    }

    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (withBody) 'Content-Type': 'application/json',
    };
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, Map<String, String>? query}) =>
      _send('POST', path, body: body, query: query);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: (query != null && query.isNotEmpty) ? query : null,
    );
    final headers = await _headers(withBody: body != null);

    late http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final streamed = await _http.send(request).timeout(ApiConfig.timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException catch (e) {
      throw ApiUnreachableException(baseUrl, 'timed out after ${ApiConfig.timeout.inSeconds}s: $e');
    } catch (e) {
      // SocketException, HandshakeException, ClientException — all mean the
      // request never got an answer, which for a developer almost always means
      // a wrong base URL or a backend that is not running.
      throw ApiUnreachableException(baseUrl, e);
    }

    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    final status = response.statusCode;

    // 204 No Content: DELETE endpoints answer with an empty body, and
    // jsonDecode('') throws.
    if (status == 204 || response.body.isEmpty) {
      if (status >= 400) {
        throw ApiException(status, 'Request failed with status $status.');
      }
      return null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      if (status >= 400) {
        throw ApiException(status, response.body, body: response.body);
      }
      throw ApiException(status, 'Expected JSON but got: ${response.body}');
    }

    if (status >= 400) {
      throw ApiException(status, _extractDetail(decoded, status), body: decoded);
    }
    return decoded;
  }

  /// Pull a human-readable message out of FastAPI's two error shapes.
  ///
  /// A raised HTTPException gives `{"detail": "Task not found"}`, while a
  /// validation failure gives `{"detail": [{"loc": [...], "msg": "...", ...}]}`.
  /// Without this the UI would show a raw list of maps to the user.
  static String _extractDetail(dynamic decoded, int status) {
    if (decoded is Map && decoded['detail'] != null) {
      final detail = decoded['detail'];
      if (detail is String) return detail;
      if (detail is List) {
        final parts = detail.map((item) {
          if (item is Map) {
            final loc = item['loc'];
            final field = (loc is List && loc.length > 1)
                ? loc.sublist(1).join('.')
                : (loc is List ? loc.join('.') : '');
            final msg = item['msg'] ?? 'invalid';
            return field.isEmpty ? '$msg' : '$field: $msg';
          }
          return item.toString();
        });
        return parts.join('; ');
      }
      return detail.toString();
    }
    return 'Request failed with status $status.';
  }

  void dispose() => _http.close();
}
