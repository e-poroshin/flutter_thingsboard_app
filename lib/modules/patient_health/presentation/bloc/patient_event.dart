import 'package:equatable/equatable.dart';

/// PATIENT APP: Patient Health BLoC Events
/// 
/// Events that trigger state changes in PatientBloc

sealed class PatientEvent extends Equatable {
  const PatientEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load the patient's health summary
final class PatientLoadHealthSummaryEvent extends PatientEvent {
  const PatientLoadHealthSummaryEvent({required this.patientId});

  final String patientId;

  @override
  List<Object?> get props => [patientId];
}

/// Event to refresh the patient's health data
final class PatientRefreshEvent extends PatientEvent {
  const PatientRefreshEvent();
}

/// Event to load vital signs
final class PatientLoadVitalSignsEvent extends PatientEvent {
  const PatientLoadVitalSignsEvent({required this.patientId});

  final String patientId;

  @override
  List<Object?> get props => [patientId];
}

/// Event to load health history for a date range
final class PatientLoadHistoryEvent extends PatientEvent {
  const PatientLoadHistoryEvent({
    required this.patientId,
    required this.startDate,
    required this.endDate,
  });

  final String patientId;
  final DateTime startDate;
  final DateTime endDate;

  @override
  List<Object?> get props => [patientId, startDate, endDate];
}

/// Event to load vital history for charting
final class PatientLoadVitalHistoryEvent extends PatientEvent {
  const PatientLoadVitalHistoryEvent({
    required this.vitalId,
    required this.range,
  });

  final String vitalId;
  final String range; // "1D", "1W", "1M"

  @override
  List<Object?> get props => [vitalId, range];
}
