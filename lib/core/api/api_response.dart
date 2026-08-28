/// A decoded FamZone API response.
///
/// The backend always replies with the same envelope:
///
///   { "success": bool, "message": string, "data": ..., "errors": ... }
///
/// Keeping that shape in one place means screens never parse raw JSON.
class ApiResponse {
  const ApiResponse({
    required this.success,
    required this.message,
    this.data,
    this.errors,
    required this.statusCode,
  });

  final bool success;
  final String message;
  final dynamic data;
  final dynamic errors;
  final int statusCode;

  factory ApiResponse.fromJson(Map<String, dynamic> json, int statusCode) {
    return ApiResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      data: json['data'],
      errors: json['errors'],
      statusCode: statusCode,
    );
  }

  /// `data` as a map, or an empty map when the payload was a list or null.
  Map<String, dynamic> get dataMap =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : const {};

  @override
  String toString() =>
      'ApiResponse(success: $success, status: $statusCode, message: $message)';
}

/// Thrown when a request cannot complete — no network, timeout, bad TLS,
/// or a response body that is not the expected envelope.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.offline = false});

  final String message;
  final int? statusCode;

  /// True when the request never reached the server — no network, no DNS, or
  /// a timeout. Worth distinguishing: an offline failure is fixed by the user
  /// and is worth offering a Retry for, whereas a 500 is not.
  final bool offline;

  @override
  String toString() => message;
}
