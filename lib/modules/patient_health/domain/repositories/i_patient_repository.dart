import 'package:thingsboard_app/modules/patient_health/domain/entities/patient_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_history_point.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_sign_entity.dart';

/// PATIENT APP: Patient Repository Interface (Domain Layer)
/// 
/// This abstract interface defines the contract for patient health data access.
/// It combines data from both ThingsBoard (telemetry) and Medplum (FHIR).

abstract interface class IPatientRepository {
  // ============================================================
  // New Simplified API (for Mock/UI Development)
  // ============================================================

  /// Get the current patient's profile
  Future<PatientEntity> getPatientProfile();

  /// Get the latest vital signs for the current patient
  Future<List<VitalSignEntity>> getLatestVitals();

  /// Get daily tasks for the treatment plan
  Future<List<TaskEntity>> getDailyTasks();

  /// Get historical data points for a specific vital sign
  /// [vitalId] - Identifier for the vital (e.g., "heartRate", "temperature")
  /// [range] - Time range: "1D" (1 day), "1W" (1 week), "1M" (1 month)
  Future<List<VitalHistoryPoint>> getVitalHistory(String vitalId, String range);

  // ============================================================
  // Existing API (for Production with BFF)
  // ============================================================

  /// Get combined patient health summary
  /// Combines FHIR patient info with latest telemetry
  Future<PatientHealthSummary> getPatientHealthSummary(String patientId);

  /// Get patient's vital signs from IoT devices (ThingsBoard telemetry)
  Future<List<VitalSign>> getVitalSigns(String patientId);

  /// Get patient's clinical observations from FHIR (Medplum)
  Future<List<ClinicalObservation>> getClinicalObservations(String patientId);

  /// Get patient's health history (time series data)
  Future<HealthHistory> getHealthHistory(
    String patientId, {
    required DateTime startDate,
    required DateTime endDate,
  });
}

/// Domain entity representing a patient's health summary
class PatientHealthSummary {
  const PatientHealthSummary({
    required this.patientId,
    this.patientName,
    this.lastUpdated,
    this.vitalSigns = const [],
    this.recentObservations = const [],
  });

  final String patientId;
  final String? patientName;
  final DateTime? lastUpdated;
  final List<VitalSign> vitalSigns;
  final List<ClinicalObservation> recentObservations;
}

/// Domain entity for vital signs from IoT devices
class VitalSign {
  const VitalSign({
    required this.type,
    required this.value,
    required this.unit,
    required this.timestamp,
    this.deviceId,
    this.isNormal = true,
  });

  final VitalSignType type;
  final double value;
  final String unit;
  final DateTime timestamp;
  final String? deviceId;
  final bool isNormal;
}

enum VitalSignType {
  heartRate,
  bloodPressureSystolic,
  bloodPressureDiastolic,
  temperature,
  oxygenSaturation,
  respiratoryRate,
  bloodGlucose,
  weight,
}

/// Domain entity for clinical observations from FHIR
class ClinicalObservation {
  const ClinicalObservation({
    required this.id,
    required this.code,
    required this.displayName,
    required this.value,
    required this.effectiveDateTime,
    this.category,
    this.interpretation,
  });

  final String id;
  final String code;
  final String displayName;
  final String value;
  final DateTime effectiveDateTime;
  final String? category;
  final String? interpretation;
}

/// Domain entity for health history data
class HealthHistory {
  const HealthHistory({
    required this.patientId,
    required this.startDate,
    required this.endDate,
    this.dataPoints = const [],
  });

  final String patientId;
  final DateTime startDate;
  final DateTime endDate;
  final List<HealthDataPoint> dataPoints;
}

class HealthDataPoint {
  const HealthDataPoint({
    required this.timestamp,
    required this.metricName,
    required this.value,
    this.unit,
  });

  final DateTime timestamp;
  final String metricName;
  final double value;
  final String? unit;
}

