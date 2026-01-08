import 'package:equatable/equatable.dart';

/// PATIENT APP: Patient Login BLoC Events
///
/// Events for the custom NestJS authentication flow.

sealed class PatientLoginEvent extends Equatable {
  const PatientLoginEvent();

  @override
  List<Object?> get props => [];
}

/// Event to initiate login with email and password
final class PatientLoginSubmitEvent extends PatientLoginEvent {
  const PatientLoginSubmitEvent({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

/// Event to initiate registration
final class PatientRegisterSubmitEvent extends PatientLoginEvent {
  const PatientRegisterSubmitEvent({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
  });

  final String email;
  final String password;
  final String firstName;
  final String lastName;

  @override
  List<Object?> get props => [email, password, firstName, lastName];
}

/// Event to logout
final class PatientLogoutEvent extends PatientLoginEvent {
  const PatientLogoutEvent();
}

/// Event to check authentication status
final class PatientCheckAuthEvent extends PatientLoginEvent {
  const PatientCheckAuthEvent();
}

/// Event to reset login state (clear errors)
final class PatientLoginResetEvent extends PatientLoginEvent {
  const PatientLoginResetEvent();
}

