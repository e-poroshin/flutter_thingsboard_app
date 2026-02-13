import 'package:hive/hive.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/health_record_entity.dart';

/// PATIENT APP: Health Record Hive Model (Data Layer)
///
/// Hive model for persisting HealthRecordEntity to local storage.
/// Stores patient-reported symptoms, mood, and notes.
///
/// Note: Using manual adapter instead of code generation to avoid
/// dependency conflicts with freezed and custom_lint.

class HealthRecordHiveModel extends HiveObject {
  HealthRecordHiveModel({
    required this.id,
    required this.timestamp,
    required this.mood,
    required this.symptoms,
    this.note,
  });

  /// Unique record identifier (UUID)
  final String id;

  /// When this record was created
  final DateTime timestamp;

  /// Mood on a 1-5 scale (1 = worst, 5 = best)
  final int mood;

  /// List of reported symptoms
  final List<String> symptoms;

  /// Optional free-text note
  final String? note;

  /// Convert Hive model to Domain Entity
  HealthRecordEntity toEntity() {
    return HealthRecordEntity(
      id: id,
      timestamp: timestamp,
      mood: mood,
      symptoms: symptoms,
      note: note,
    );
  }

  /// Create Hive model from Domain Entity
  factory HealthRecordHiveModel.fromEntity(HealthRecordEntity entity) {
    return HealthRecordHiveModel(
      id: entity.id,
      timestamp: entity.timestamp,
      mood: entity.mood,
      symptoms: entity.symptoms,
      note: entity.note,
    );
  }

  @override
  String toString() =>
      'HealthRecordHiveModel(id: $id, mood: $mood, symptoms: $symptoms)';
}
