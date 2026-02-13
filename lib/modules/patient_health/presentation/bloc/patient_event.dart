import 'package:equatable/equatable.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/health_record_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';

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

/// Event to load tasks into the bloc (for syncing with repository-loaded tasks)
final class PatientLoadTasksEvent extends PatientEvent {
  const PatientLoadTasksEvent({required this.tasks});

  final List<TaskEntity> tasks;

  @override
  List<Object?> get props => [tasks];
}

/// Event to add a new task to the treatment plan
final class PatientAddTaskEvent extends PatientEvent {
  const PatientAddTaskEvent({required this.task});

  final TaskEntity task;

  @override
  List<Object?> get props => [task];
}

/// Event to update vitals with BLE sensor data
final class PatientBleUpdateEvent extends PatientEvent {
  const PatientBleUpdateEvent({
    required this.temperature,
    required this.humidity,
  });

  final double temperature;
  final double humidity;

  @override
  List<Object?> get props => [temperature, humidity];
}

/// Event to connect to a paired BLE sensor
/// Dispatched after saving a sensor ID to immediately start listening
final class PatientConnectSensorEvent extends PatientEvent {
  const PatientConnectSensorEvent();
}

/// Event to add a patient-reported health record (symptoms, mood, notes)
final class PatientAddRecordEvent extends PatientEvent {
  const PatientAddRecordEvent({required this.record});

  final HealthRecordEntity record;

  @override
  List<Object?> get props => [record];
}