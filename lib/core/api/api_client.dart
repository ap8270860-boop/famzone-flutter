import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_response.dart';

/// Thin wrapper around `package:http` that speaks the FamZone envelope.
///
/// Every screen goes through this rather than calling http directly, so that
/// auth headers, timeouts and error handling stay in one place. When Sanctum
/// lands, the bearer token gets injected in [_headers] and nothing else
/// has to change.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Set after login; cleared on logout.
  String? _token;

  // ignore: avoid_setters_without_getters
  set token(String? value) => _token = value;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path) =>
      Uri.parse('${AppConfig.apiBaseUrl}/${path.replaceFirst(RegExp(r'^/'), '')}');

  Future<ApiResponse> get(String path) =>
      _send(() => _client.get(_uri(path), headers: _headers));

  Future<ApiResponse> post(String path, {Map<String, dynamic>? body}) =>
      _send(() => _client.post(
            _uri(path),
            headers: _headers,
            body: body == null ? null : jsonEncode(body),
          ));

  Future<ApiResponse> _send(Future<http.Response> Function() request) async {
    late final http.Response response;

    try {
      response = await request().timeout(AppConfig.requestTimeout);
    } on SocketException {
      throw const ApiException(
        'No internet connection. Check your network and try again.',
      );
    } on HandshakeException {
      throw const ApiException('Could not establish a secure connection.');
    } catch (e) {
      throw ApiException('Request failed: $e');
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Usually an HTML error page from Nginx or a Laravel debug trace.
      throw ApiException(
        'Unexpected response from server (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    return ApiResponse.fromJson(decoded, response.statusCode);
  }

  void dispose() => _client.close();
}
