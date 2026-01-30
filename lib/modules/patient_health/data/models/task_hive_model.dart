import 'package:hive/hive.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';

/// PATIENT APP: Task Hive Model (Data Layer)
///
/// Hive model for persisting TaskEntity to local storage.
/// This model is used by Hive to serialize/deserialize task data.
/// 
/// Note: Using manual adapter instead of code generation to avoid
/// dependency conflicts with freezed and custom_lint.

class TaskHiveModel extends HiveObject {
  TaskHiveModel({
    required this.id,
    required this.title,
    required this.time,
    required this.type,
    this.isCompleted = false,
    this.description,
    this.medicationDosage,
    this.medicationUnit,
  });

  final String id;
  final String title;
  final String time;
  final int type; // Store TaskType as int (enum index)
  final bool isCompleted;
  final String? description;
  final double? medicationDosage;
  final String? medicationUnit;

  /// Convert Hive model to Domain Entity
  TaskEntity toEntity() {
    return TaskEntity(
      id: id,
      title: title,
      time: time,
      type: TaskType.values[type],
      isCompleted: isCompleted,
      description: description,
      medicationDosage: medicationDosage,
      medicationUnit: medicationUnit,
    );
  }

  /// Create Hive model from Domain Entity
  factory TaskHiveModel.fromEntity(TaskEntity entity) {
    return TaskHiveModel(
      id: entity.id,
      title: entity.title,
      time: entity.time,
      type: entity.type.index,
      isCompleted: entity.isCompleted,
      description: entity.description,
      medicationDosage: entity.medicationDosage,
      medicationUnit: entity.medicationUnit,
    );
  }

  /// Create a copy with updated fields
  TaskHiveModel copyWith({
    String? id,
    String? title,
    String? time,
    int? type,
    bool? isCompleted,
    String? description,
    double? medicationDosage,
    String? medicationUnit,
  }) {
    return TaskHiveModel(
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
}
