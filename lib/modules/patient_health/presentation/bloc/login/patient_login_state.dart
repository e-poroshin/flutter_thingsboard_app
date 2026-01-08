import 'package:equatable/equatable.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/auth_response.dart';

/// PATIENT APP: Patient Login BLoC States
///
/// States for the custom NestJS authentication flow.

sealed class PatientLoginState extends Equatable {
  const PatientLoginState();

  @override
  List<Object?> get props => [];
}

/// Initial state - not authenticated, no login attempt
final class PatientLoginInitialState extends PatientLoginState {
  const PatientLoginInitialState();
}

/// Loading state - login/registration in progress
final class PatientLoginLoadingState extends PatientLoginState {
  const PatientLoginLoadingState({this.message});

  final String? message;

  @override
  List<Object?> get props => [message];
}

/// Success state - user authenticated
final class PatientLoginSuccessState extends PatientLoginState {
  const PatientLoginSuccessState({
    required this.authResponse,
  });

  final AuthResponse authResponse;

  @override
  List<Object?> get props => [authResponse];
}

/// Already authenticated state (checked on app start)
final class PatientLoginAuthenticatedState extends PatientLoginState {
  const PatientLoginAuthenticatedState();
}

/// Error state - login/registration failed
final class PatientLoginErrorState extends PatientLoginState {
  const PatientLoginErrorState({
    required this.message,
    this.isValidationError = false,
    this.validationErrors,
  });

  final String message;
  final bool isValidationError;
  final Map<String, List<String>>? validationErrors;

  @override
  List<Object?> get props => [message, isValidationError, validationErrors];
}

/// Logged out state
final class PatientLoginLoggedOutState extends PatientLoginState {
  const PatientLoginLoggedOutState();
}

