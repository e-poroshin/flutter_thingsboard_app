import 'package:thingsboard_app/modules/patient_health/data/datasources/medplum_remote_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/tb_telemetry_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';

/// PATIENT APP: Patient Repository Implementation (Data Layer)
///
/// Combines data from NestJS BFF endpoints that proxy to:
/// - ThingsBoard for IoT device telemetry (vital signs from wearables)
/// - Medplum for FHIR clinical data (observations, conditions)
///
/// **Architecture:**
/// - All data flows through NestJS BFF
/// - Repository transforms raw JSON to domain entities
/// - Handles data aggregation and caching (future)

class PatientRepositoryImpl implements IPatientRepository {
  const PatientRepositoryImpl({
    required this.medplumDatasource,
    required this.telemetryDatasource,
  });

  final IMedplumRemoteDatasource medplumDatasource;
  final ITbTelemetryDatasource telemetryDatasource;

  @override
  Future<PatientHealthSummary> getPatientHealthSummary(String patientId) async {
    try {
      // Fetch data in parallel from NestJS BFF
      final results = await Future.wait([
        medplumDatasource.fetchPatientProfile(),
        telemetryDatasource.fetchLatestVitals(),
        medplumDatasource.fetchPatientObservations(),
      ]);

      final profileData = results[0] as Map<String, dynamic>;
      final vitalsData = results[1] as Map<String, dynamic>;
      final observationsData = results[2] as List<Map<String, dynamic>>;

      // Transform to domain entities
      final vitalSigns = _parseVitalSigns(vitalsData);
      final observations = _parseClinicalObservations(observationsData);

      return PatientHealthSummary(
        patientId: patientId,
        patientName: _extractPatientName(profileData),
        lastUpdated: DateTime.now(),
        vitalSigns: vitalSigns,
        recentObservations: observations,
      );
    } catch (e) {
      // Return empty summary on error, let BLoC handle error state
      rethrow;
    }
  }

  @override
  Future<List<VitalSign>> getVitalSigns(String patientId) async {
    final vitalsData = await telemetryDatasource.fetchLatestVitals();
    return _parseVitalSigns(vitalsData);
  }

  @override
  Future<List<ClinicalObservation>> getClinicalObservations(
    String patientId,
  ) async {
    final observationsData = await medplumDatasource.fetchPatientObservations();
    return _parseClinicalObservations(observationsData);
  }

  @override
  Future<HealthHistory> getHealthHistory(
    String patientId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final historyData = await telemetryDatasource.fetchVitalsHistory(
      startTs: startDate.millisecondsSinceEpoch,
      endTs: endDate.millisecondsSinceEpoch,
    );

    final dataPoints = historyData
        .map((item) => HealthDataPoint(
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                item['ts'] as int? ?? 0,
              ),
              metricName: item['key'] as String? ?? 'unknown',
              value: (item['value'] as num?)?.toDouble() ?? 0.0,
              unit: item['unit'] as String?,
            ))
        .toList();

    return HealthHistory(
      patientId: patientId,
      startDate: startDate,
      endDate: endDate,
      dataPoints: dataPoints,
    );
  }

  // ============================================================
  // Private Helper Methods
  // ============================================================

  String? _extractPatientName(Map<String, dynamic> profileData) {
    final firstName = profileData['firstName'] as String?;
    final lastName = profileData['lastName'] as String?;
    final name = profileData['name'] as String?;

    if (firstName != null || lastName != null) {
      return [firstName, lastName].whereType<String>().join(' ');
    }
    return name;
  }

  List<VitalSign> _parseVitalSigns(Map<String, dynamic> vitalsData) {
    final vitalSigns = <VitalSign>[];

    // Map of API keys to VitalSignType
    final keyToType = {
      'heartRate': VitalSignType.heartRate,
      'heart_rate': VitalSignType.heartRate,
      'bloodPressureSystolic': VitalSignType.bloodPressureSystolic,
      'systolic': VitalSignType.bloodPressureSystolic,
      'bloodPressureDiastolic': VitalSignType.bloodPressureDiastolic,
      'diastolic': VitalSignType.bloodPressureDiastolic,
      'temperature': VitalSignType.temperature,
      'oxygenSaturation': VitalSignType.oxygenSaturation,
      'spo2': VitalSignType.oxygenSaturation,
      'respiratoryRate': VitalSignType.respiratoryRate,
      'respiratory_rate': VitalSignType.respiratoryRate,
      'bloodGlucose': VitalSignType.bloodGlucose,
      'glucose': VitalSignType.bloodGlucose,
      'weight': VitalSignType.weight,
    };

    final unitMap = {
      VitalSignType.heartRate: 'bpm',
      VitalSignType.bloodPressureSystolic: 'mmHg',
      VitalSignType.bloodPressureDiastolic: 'mmHg',
      VitalSignType.temperature: '°C',
      VitalSignType.oxygenSaturation: '%',
      VitalSignType.respiratoryRate: '/min',
      VitalSignType.bloodGlucose: 'mg/dL',
      VitalSignType.weight: 'kg',
    };

    for (final entry in vitalsData.entries) {
      final type = keyToType[entry.key];
      if (type != null && entry.value != null) {
        final value = entry.value;
        double numValue;

        if (value is num) {
          numValue = value.toDouble();
        } else if (value is Map) {
          // Handle nested format: { "value": 72, "ts": 1234567890 }
          numValue = (value['value'] as num?)?.toDouble() ?? 0.0;
        } else {
          continue;
        }

        vitalSigns.add(VitalSign(
          type: type,
          value: numValue,
          unit: unitMap[type] ?? '',
          timestamp: DateTime.now(),
          isNormal: _isVitalSignNormal(type, numValue),
        ));
      }
    }

    return vitalSigns;
  }

  bool _isVitalSignNormal(VitalSignType type, double value) {
    // Basic normal ranges - should be configurable
    switch (type) {
      case VitalSignType.heartRate:
        return value >= 60 && value <= 100;
      case VitalSignType.bloodPressureSystolic:
        return value >= 90 && value <= 140;
      case VitalSignType.bloodPressureDiastolic:
        return value >= 60 && value <= 90;
      case VitalSignType.temperature:
        return value >= 36.1 && value <= 37.2;
      case VitalSignType.oxygenSaturation:
        return value >= 95;
      case VitalSignType.respiratoryRate:
        return value >= 12 && value <= 20;
      case VitalSignType.bloodGlucose:
        return value >= 70 && value <= 140;
      case VitalSignType.weight:
        return true; // Weight doesn't have a "normal" range
    }
  }

  List<ClinicalObservation> _parseClinicalObservations(
    List<Map<String, dynamic>> observationsData,
  ) {
    return observationsData.map((obs) {
      return ClinicalObservation(
        id: obs['id'] as String? ?? '',
        code: obs['code'] as String? ?? '',
        displayName: obs['displayName'] as String? ??
            obs['display'] as String? ??
            obs['name'] as String? ??
            'Unknown',
        value: obs['value']?.toString() ?? '',
        effectiveDateTime: obs['effectiveDateTime'] != null
            ? DateTime.tryParse(obs['effectiveDateTime'] as String) ??
                DateTime.now()
            : DateTime.now(),
        category: obs['category'] as String?,
        interpretation: obs['interpretation'] as String?,
      );
    }).toList();
  }
}
