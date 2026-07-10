// lib/core/errors/failure.dart

import 'package:equatable/equatable.dart';

/// Base class for all domain-layer failures.
///
/// Failures are value objects — two failures with the same [message]
/// are considered equal. Use them to represent the user-facing
/// consequence of an [AppException] without leaking infrastructure
/// details into the presentation layer.
abstract class Failure extends Equatable {
  final String message;

  const Failure(this.message);

  @override
  List<Object> get props => [message];

  @override
  String toString() => '$runtimeType(message: $message)';
}

/// Returned when an authentication or session operation fails,
/// e.g. wrong password, expired token, or unauthenticated access.
class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Returned when the device is offline, a request times out, or
/// the remote host is unreachable.
class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// Returned when the requested resource does not exist.
class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

/// Returned when the current user lacks the required permissions.
class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

/// Returned when the remote server responds with an unexpected error.
class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

/// Returned when reading from or writing to the local cache fails.
class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

/// Returned when user-supplied data fails validation rules.
class ValidationFailure extends Failure {
  /// Optional field-level error messages keyed by field name.
  final Map<String, String>? fieldErrors;

  const ValidationFailure(super.message, {this.fieldErrors});

  @override
  List<Object> get props => [message, fieldErrors ?? {}];
}

/// Returned for any unexpected, unclassified error.
class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
