// lib/core/errors/app_exception.dart

/// Base class for all application-level exceptions.
abstract class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, {this.code});

  @override
  String toString() => 'AppException(code: $code, message: $message)';
}

/// Thrown when an authentication or authorization operation fails.
class AuthException extends AppException {
  const AuthException(super.message, {super.code});

  @override
  String toString() => 'AuthException(code: $code, message: $message)';
}

/// Thrown when a network request fails due to connectivity issues,
/// timeouts, or unexpected HTTP errors.
class NetworkException extends AppException {
  final int? statusCode;

  const NetworkException(super.message, {super.code, this.statusCode});

  @override
  String toString() =>
      'NetworkException(code: $code, statusCode: $statusCode, message: $message)';
}

/// Thrown when a requested resource cannot be found (e.g., 404).
class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.code});

  @override
  String toString() => 'NotFoundException(code: $code, message: $message)';
}

/// Thrown when the current user lacks the required permissions
/// to perform an operation.
class PermissionException extends AppException {
  const PermissionException(super.message, {super.code});

  @override
  String toString() => 'PermissionException(code: $code, message: $message)';
}

/// Thrown when the remote server returns an unexpected error response.
class ServerException extends AppException {
  final int? statusCode;

  const ServerException(super.message, {super.code, this.statusCode});

  @override
  String toString() =>
      'ServerException(code: $code, statusCode: $statusCode, message: $message)';
}

/// Thrown when a local cache read or write operation fails.
class CacheException extends AppException {
  const CacheException(super.message, {super.code});

  @override
  String toString() => 'CacheException(code: $code, message: $message)';
}

/// Thrown when user-supplied data fails validation.
class ValidationException extends AppException {
  /// Field-level validation errors keyed by field name.
  final Map<String, String>? fieldErrors;

  const ValidationException(
    super.message, {
    super.code,
    this.fieldErrors,
  });

  @override
  String toString() =>
      'ValidationException(code: $code, message: $message, fields: $fieldErrors)';
}

/// Thrown when an operation times out before completing.
class TimeoutException extends AppException {
  const TimeoutException(super.message, {super.code});

  @override
  String toString() => 'TimeoutException(code: $code, message: $message)';
}

/// Thrown for any unexpected, unclassified error.
class UnknownException extends AppException {
  final Object? originalError;

  const UnknownException(super.message, {super.code, this.originalError});

  @override
  String toString() =>
      'UnknownException(code: $code, message: $message, originalError: $originalError)';
}
