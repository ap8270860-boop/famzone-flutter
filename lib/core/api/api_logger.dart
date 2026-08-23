import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Prints every API call to the debug console.
///
/// Debug builds only — `kDebugMode` is a compile-time constant, so the whole
/// thing is tree-shaken out of a release build and cannot leak tokens or
/// personal data on a user's device.
abstract final class ApiLogger {
  /// Header and body keys whose values are replaced before printing.
  static const _redact = {
    'authorization',
    'password',
    'password_confirmation',
    'token',
    'device_token',
    'code',
    'sos_pin',
  };

  static void request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    if (!kDebugMode) return;

    final buffer = StringBuffer()
      ..writeln('┌─ →  $method  ${uri.path}')
      ..writeln('│  ${uri.origin}${uri.path}');

    if (headers != null && headers.isNotEmpty) {
      buffer.writeln('│  headers: ${_scrubMap(headers)}');
    }
    if (body != null) {
      buffer.writeln('│  body: ${_pretty(body)}');
    }
    buffer.write('└─');

    developer.log(buffer.toString(), name: 'API');
  }

  static void response(
    String method,
    Uri uri,
    int status,
    String body,
    Duration elapsed,
  ) {
    if (!kDebugMode) return;

    final ok = status >= 200 && status < 300;
    final mark = ok ? '✓' : '✗';

    final buffer = StringBuffer()
      ..writeln('┌─ ←  $mark  $status  $method  ${uri.path}  '
          '(${elapsed.inMilliseconds}ms)')
      ..writeln('│  ${_pretty(body)}')
      ..write('└─');

    developer.log(buffer.toString(), name: 'API');
  }

  static void failure(String method, Uri uri, Object error) {
    if (!kDebugMode) return;
    developer.log('✗  $method  ${uri.path}  →  $error', name: 'API');
  }

  static Map<String, String> _scrubMap(Map<String, String> input) {
    return input.map((k, v) => MapEntry(
          k,
          _redact.contains(k.toLowerCase()) ? '••• redacted' : v,
        ));
  }

  /// Pretty-print JSON, redacting sensitive keys at any depth.
  static String _pretty(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return const JsonEncoder.withIndent('  ')
          .convert(_scrub(decoded))
          .split('\n')
          .join('\n│  ');
    } catch (_) {
      // Not JSON — an HTML error page, most likely. Show enough to recognise it.
      final text = value.toString();
      return text.length > 500 ? '${text.substring(0, 500)}…' : text;
    }
  }

  /// Walk a decoded payload, replacing sensitive values.
  ///
  /// [inErrors] switches redaction off: inside a validation `errors` object
  /// the values are human-readable messages keyed by field name, not the
  /// field's value. Redacting there hides the very thing you need to read —
  /// "errors": {"password": "••• redacted"} tells you nothing.
  static Object? _scrub(Object? value, {bool inErrors = false}) {
    if (value is Map) {
      return value.map((k, v) {
        final key = k.toString().toLowerCase();

        if (!inErrors && _redact.contains(key)) {
          return MapEntry(k, '••• redacted');
        }

        return MapEntry(k, _scrub(v, inErrors: inErrors || key == 'errors'));
      });
    }
    if (value is List) {
      return value.map((v) => _scrub(v, inErrors: inErrors)).toList();
    }
    return value;
  }
}
