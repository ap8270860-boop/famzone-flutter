import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../session/session.dart';
import 'api_logger.dart';
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

  /// Overrides the session token for this client. Normally unset — the
  /// bearer comes from [Session] so there is one source of truth.
  String? _token;

  // ignore: avoid_setters_without_getters
  set token(String? value) => _token = value;

  String? get _bearer => _token ?? Session.instance.token;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_bearer != null) 'Authorization': 'Bearer $_bearer',
      };

  Uri _uri(String path) =>
      Uri.parse('${AppConfig.apiBaseUrl}/${path.replaceFirst(RegExp(r'^/'), '')}');

  Future<ApiResponse> get(String path) {
    final uri = _uri(path);
    return _send('GET', uri, () => _client.get(uri, headers: _headers));
  }

  Future<ApiResponse> post(String path, {Map<String, dynamic>? body}) {
    final uri = _uri(path);
    return _send(
      'POST',
      uri,
      () => _client.post(
        uri,
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      ),
      body: body,
    );
  }

  Future<ApiResponse> patch(String path, {Map<String, dynamic>? body}) {
    final uri = _uri(path);
    return _send(
      'PATCH',
      uri,
      () => _client.patch(
        uri,
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      ),
      body: body,
    );
  }

  Future<ApiResponse> delete(String path) {
    final uri = _uri(path);
    return _send('DELETE', uri, () => _client.delete(uri, headers: _headers));
  }

  /// Upload a file alongside optional form fields.
  ///
  /// Multipart cannot carry a JSON body, so this builds the request by hand
  /// rather than going through [_send]'s json path.
  Future<ApiResponse> upload(
    String path, {
    required String field,
    required String filePath,
    Map<String, String> fields = const {},
  }) async {
    final uri = _uri(path);
    ApiLogger.request('POST', uri, headers: _headers, body: {
      ...fields,
      field: filePath.split(RegExp(r'[/\\]')).last,
    });

    final started = DateTime.now();

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          'Accept': 'application/json',
          if (_bearer != null) 'Authorization': 'Bearer $_bearer',
        })
        ..fields.addAll(fields)
        ..files.add(await http.MultipartFile.fromPath(field, filePath));

      final streamed = await request.send().timeout(AppConfig.uploadTimeout);
      final response = await http.Response.fromStream(streamed);

      ApiLogger.response('POST', uri, response.statusCode, response.body,
          DateTime.now().difference(started));

      // nginx and PHP-FPM both refuse an oversized upload before Laravel
      // ever sees it, and they answer with an HTML error page rather than
      // our envelope. Decoding that as JSON throws, and the user is told
      // "Upload failed: FormatException" — which points at nothing.
      if (response.statusCode == 413) {
        throw const ApiException(
          'That file is too large to send.',
          statusCode: 413,
        );
      }

      try {
        return ApiResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
          response.statusCode,
        );
      } on FormatException {
        // Any other non-JSON body: a gateway error, a maintenance page. Say
        // what the server actually returned rather than paraphrasing a
        // parser failure.
        throw ApiException(
          'The server rejected that upload (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    } on ApiException {
      // Already meaningful — do not rewrap it as "Upload failed: ...".
      rethrow;
    } on SocketException catch (e) {
      ApiLogger.failure('POST', uri, e);
      throw const ApiException('No internet connection.');
    } catch (e) {
      ApiLogger.failure('POST', uri, e);
      throw ApiException('Upload failed: $e');
    }
  }

  Future<ApiResponse> _send(
    String method,
    Uri uri,
    Future<http.Response> Function() request, {
    Object? body,
  }) async {
    ApiLogger.request(method, uri, headers: _headers, body: body);

    final started = DateTime.now();
    late final http.Response response;

    try {
      response = await request().timeout(AppConfig.requestTimeout);
      ApiLogger.response(
        method,
        uri,
        response.statusCode,
        response.body,
        DateTime.now().difference(started),
      );
    } catch (e) {
      ApiLogger.failure(method, uri, e);
      throw _classify(e);
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


  /// Turn a transport failure into something worth showing a user.
  ///
  /// The catch that matters is [http.ClientException]. `package:http` wraps
  /// the real cause rather than letting it through, so an
  /// `on SocketException` clause never fires for a request made with it — the
  /// phone being offline fell through to the generic branch and surfaced as
  /// "Request failed: ClientException with SocketException...", which is a
  /// stack trace wearing a message's clothes.
  ///
  /// So the wrapper is unwrapped by inspecting it, and only then given
  /// wording somebody can act on.
  ApiException _classify(Object error) {
    if (error is TimeoutException) {
      return const ApiException(
        'The server took too long to respond. Try again.',
        offline: true,
      );
    }

    if (error is HandshakeException) {
      return const ApiException('Could not establish a secure connection.');
    }

    if (error is SocketException) {
      return _networkFailure(error.message);
    }

    if (error is http.ClientException) {
      return _networkFailure(error.message);
    }

    return ApiException('Something went wrong. ($error)');
  }

  /// Separate "no network at all" from "the name would not resolve", because
  /// they call for different things from the user.
  ApiException _networkFailure(String message) {
    final text = message.toLowerCase();

    if (text.contains('failed host lookup') ||
        text.contains('no address associated')) {
      return const ApiException(
        "Couldn't reach SFamily. Check your Wi-Fi or mobile data and try "
        'again.',
        offline: true,
      );
    }

    return const ApiException(
      'No internet connection. Check your network and try again.',
      offline: true,
    );
  }

  void dispose() => _client.close();
}
