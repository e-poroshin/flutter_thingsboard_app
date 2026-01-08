/// PATIENT APP: NestJS API Exception Types
///
/// Defines exception types for NestJS API errors.

enum NestApiExceptionType {
  /// Network connectivity issues
  network,

  /// Request/response timeout
  timeout,

  /// Request was cancelled
  cancelled,

  /// 400 Bad Request
  badRequest,

  /// 401 Unauthorized - token expired or invalid
  unauthorized,

  /// 403 Forbidden - no permission
  forbidden,

  /// 404 Not Found
  notFound,

  /// 422 Validation Error
  validation,

  /// 5xx Server Error
  server,

  /// Unknown error
  unknown,
}

/// PATIENT APP: NestJS API Exception
///
/// Custom exception for all NestJS API errors.
/// Maps HTTP errors to actionable exception types.
class NestApiException implements Exception {
  const NestApiException({
    required this.message,
    required this.statusCode,
    this.type = NestApiExceptionType.unknown,
    this.data,
  });

  final String message;
  final int statusCode;
  final NestApiExceptionType type;
  final dynamic data;

  /// Check if this is an authentication error
  bool get isAuthError => type == NestApiExceptionType.unauthorized;

  /// Check if this is a network/connectivity error
  bool get isNetworkError =>
      type == NestApiExceptionType.network ||
      type == NestApiExceptionType.timeout;

  /// Check if this is a server error
  bool get isServerError => type == NestApiExceptionType.server;

  /// Check if this is a validation error
  bool get isValidationError => type == NestApiExceptionType.validation;

  /// Get validation errors from response data (if available)
  Map<String, List<String>>? get validationErrors {
    if (data is Map<String, dynamic> && data['errors'] != null) {
      final errors = data['errors'];
      if (errors is Map<String, dynamic>) {
        return errors.map(
          (key, value) => MapEntry(
            key,
            value is List ? value.cast<String>() : [value.toString()],
          ),
        );
      }
    }
    return null;
  }

  @override
  String toString() => 'NestApiException($statusCode): $message';
}

/// PATIENT APP: Authentication Exception
///
/// Specific exception for authentication failures
class NestAuthException extends NestApiException {
  const NestAuthException({
    required super.message,
    super.statusCode = 401,
    super.type = NestApiExceptionType.unauthorized,
    super.data,
  });

  factory NestAuthException.invalidCredentials() => const NestAuthException(
        message: 'Invalid email or password',
        statusCode: 401,
      );

  factory NestAuthException.tokenExpired() => const NestAuthException(
        message: 'Your session has expired. Please log in again.',
        statusCode: 401,
      );

  factory NestAuthException.accountLocked() => const NestAuthException(
        message: 'Your account has been locked. Please contact support.',
        statusCode: 403,
        type: NestApiExceptionType.forbidden,
      );
}

