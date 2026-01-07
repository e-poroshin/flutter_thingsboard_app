import 'package:equatable/equatable.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';

/// PATIENT APP: Patient Health BLoC States
/// 
/// States representing the UI state for patient health data

sealed class PatientState extends Equatable {
  const PatientState();

  @override
  List<Object?> get props => [];
}

/// Initial state when no data has been loaded
final class PatientInitialState extends PatientState {
  const PatientInitialState();
}

/// Loading state while fetching patient data
final class PatientLoadingState extends PatientState {
  const PatientLoadingState();
}

/// State when patient health summary is loaded successfully
final class PatientHealthLoadedState extends PatientState {
  const PatientHealthLoadedState({
    required this.healthSummary,
  });

  final PatientHealthSummary healthSummary;

  @override
  List<Object?> get props => [healthSummary];
}

/// State when vital signs are loaded
final class PatientVitalSignsLoadedState extends PatientState {
  const PatientVitalSignsLoadedState({
    required this.vitalSigns,
  });

  final List<VitalSign> vitalSigns;

  @override
  List<Object?> get props => [vitalSigns];
}

/// State when health history is loaded
final class PatientHistoryLoadedState extends PatientState {
  const PatientHistoryLoadedState({
    required this.history,
  });

  final HealthHistory history;

  @override
  List<Object?> get props => [history];
}

/// Error state when something goes wrong
final class PatientErrorState extends PatientState {
  const PatientErrorState({
    required this.message,
    this.exception,
  });

  final String message;
  final Object? exception;

  @override
  List<Object?> get props => [message, exception];
}

