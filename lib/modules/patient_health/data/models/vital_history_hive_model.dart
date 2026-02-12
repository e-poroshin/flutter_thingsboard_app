import 'package:hive/hive.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_history_point.dart';

/// PATIENT APP: Vital History Hive Model (Data Layer)
///
/// Hive model for persisting vital sign measurements to local storage.
/// Each instance represents a single data point (timestamp + value) for
/// a given vital type (temperature, humidity, etc.).
///
/// Note: Using manual adapter instead of code generation to avoid
/// dependency conflicts with freezed and custom_lint.

class VitalHistoryHiveModel extends HiveObject {
  VitalHistoryHiveModel({
    required this.vitalType,
    required this.timestamp,
    required this.value,
    this.unit,
  });

  /// Type of vital sign (e.g., 'temperature', 'humidity')
  final String vitalType;

  /// When this measurement was taken
  final DateTime timestamp;

  /// The measured value
  final double value;

  /// Optional unit of measurement (e.g., '°C', '%')
  final String? unit;

  /// Convert Hive model to Domain Entity
  VitalHistoryPoint toEntity() {
    return VitalHistoryPoint(
      timestamp: timestamp,
      value: value,
    );
  }

  /// Create Hive model from individual values
  factory VitalHistoryHiveModel.fromMeasurement({
    required String vitalType,
    required double value,
    String? unit,
    DateTime? timestamp,
  }) {
    return VitalHistoryHiveModel(
      vitalType: vitalType,
      timestamp: timestamp ?? DateTime.now(),
      value: value,
      unit: unit,
    );
  }

  @override
  String toString() =>
      'VitalHistoryHiveModel(type: $vitalType, value: $value, timestamp: $timestamp)';
}
