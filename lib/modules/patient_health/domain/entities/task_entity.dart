import 'package:equatable/equatable.dart';

/// PATIENT APP: Task Entity (Domain Layer)
///
/// Represents a daily task in the patient's treatment plan.
/// Tasks can be medications, measurements, exercises, or other health-related activities.

class TaskEntity extends Equatable {
  const TaskEntity({
    required this.id,
    required this.title,
    required this.time,
    required this.type,
    this.isCompleted = false,
    this.description,
    this.medicationDosage,
    this.medicationUnit,
  });

  /// Unique identifier for the task
  final String id;

  /// Task title (e.g., "Take Aspirin", "Measure Blood Pressure")
  final String title;

  /// Time when the task should be performed (e.g., "08:00 AM")
  final String time;

  /// Type of task
  final TaskType type;

  /// Whether the task has been completed
  final bool isCompleted;

  /// Optional description or additional notes
  final String? description;

  /// Medication dosage (if type is medication)
  final double? medicationDosage;

  /// Medication unit (e.g., "mg", "tablets")
  final String? medicationUnit;

  /// Get formatted medication string (e.g., "100 mg")
  String? get formattedMedication {
    if (type != TaskType.medication || medicationDosage == null) {
      return null;
    }
    final unit = medicationUnit ?? 'mg';
    return '${medicationDosage!.toStringAsFixed(0)} $unit';
  }

  /// Get display title with medication info if applicable
  String get displayTitle {
    if (type == TaskType.medication && formattedMedication != null) {
      return '$title (${formattedMedication!})';
    }
    return title;
  }

  /// Create a copy with updated fields
  TaskEntity copyWith({
    String? id,
    String? title,
    String? time,
    TaskType? type,
    bool? isCompleted,
    String? description,
    double? medicationDosage,
    String? medicationUnit,
  }) {
    return TaskEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      time: time ?? this.time,
      type: type ?? this.type,
      isCompleted: isCompleted ?? this.isCompleted,
      description: description ?? this.description,
      medicationDosage: medicationDosage ?? this.medicationDosage,
      medicationUnit: medicationUnit ?? this.medicationUnit,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        time,
        type,
        isCompleted,
        description,
        medicationDosage,
        medicationUnit,
      ];

  @override
  String toString() => 'TaskEntity(id: $id, title: $title, time: $time, type: $type, completed: $isCompleted)';
}

/// Types of tasks in the treatment plan
enum TaskType {
  medication,
  measurement,
  exercise,
  appointment,
  other;

  /// Display name for UI
  String get displayName {
    switch (this) {
      case TaskType.medication:
        return 'Medication';
      case TaskType.measurement:
        return 'Measurement';
      case TaskType.exercise:
        return 'Exercise';
      case TaskType.appointment:
        return 'Appointment';
      case TaskType.other:
        return 'Other';
    }
  }

  /// Icon for the task type
  String get iconName {
    switch (this) {
      case TaskType.medication:
        return 'medication';
      case TaskType.measurement:
        return 'monitor_heart';
      case TaskType.exercise:
        return 'fitness_center';
      case TaskType.appointment:
        return 'event';
      case TaskType.other:
        return 'check_circle';
    }
  }
}
