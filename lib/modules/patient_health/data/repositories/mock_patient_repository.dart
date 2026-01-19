import 'dart:math';

import 'package:thingsboard_app/modules/patient_health/domain/entities/patient_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_sign_entity.dart'
    as new_entities;
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart' as repo;

/// PATIENT APP: Mock Patient Repository
///
/// Mock implementation of [IPatientRepository] for UI development.
/// Returns hardcoded data with simulated network latency.
///
/// **Features:**
/// - Simulates network latency (1 second delay)
/// - Returns "Happy Path" data by default
/// - Randomized vital signs for realistic UI testing
/// - Can simulate errors for error handling testing

class MockPatientRepository implements repo.IPatientRepository {
  MockPatientRepository({
    this.simulatedLatency = const Duration(seconds: 1),
    this.shouldSimulateError = false,
  });

  /// Duration to simulate network latency
  final Duration simulatedLatency;

  /// If true, all methods will throw an error (for testing error states)
  final bool shouldSimulateError;

  final _random = Random();

  /// Simulate network delay
  Future<void> _simulateNetworkDelay() async {
    await Future.delayed(simulatedLatency);
    if (shouldSimulateError) {
      throw Exception('Simulated network error');
    }
  }

  // ============================================================
  // New Simplified API Implementation
  // ============================================================

  @override
  Future<PatientEntity> getPatientProfile() async {
    await _simulateNetworkDelay();

    return PatientEntity(
      id: 'patient-001',
      fullName: 'John Doe',
      email: 'john.doe@example.com',
      avatarUrl: 'https://i.pravatar.cc/150?u=john.doe',
      dateOfBirth: DateTime(1985, 6, 15),
      phoneNumber: '+1 (555) 123-4567',
      gender: Gender.male,
      address: '123 Health Street, Medical City, MC 12345',
    );
  }

  @override
  Future<List<new_entities.VitalSignEntity>> getLatestVitals() async {
    await _simulateNetworkDelay();

    final now = DateTime.now();

    // Generate randomized vitals for realistic UI testing
    return [
      new_entities.VitalSignEntity(
        type: new_entities.VitalSignType.heartRate,
        value: _randomInRange(60, 100),
        unit: 'bpm',
        timestamp: now.subtract(Duration(minutes: _random.nextInt(30))),
        isCritical: false,
        deviceId: 'fitbit-hr-001',
      ),
      new_entities.VitalSignEntity(
        type: new_entities.VitalSignType.bloodPressure,
        value: {
          'systolic': _randomInRange(110, 140),
          'diastolic': _randomInRange(70, 90),
        },
        unit: 'mmHg',
        timestamp: now.subtract(Duration(minutes: _random.nextInt(60))),
        isCritical: false,
        deviceId: 'omron-bp-002',
      ),
      new_entities.VitalSignEntity(
        type: new_entities.VitalSignType.temperature,
        value: _randomDoubleInRange(36.2, 37.0),
        unit: '°C',
        timestamp: now.subtract(Duration(hours: _random.nextInt(4))),
        isCritical: false,
      ),
      new_entities.VitalSignEntity(
        type: new_entities.VitalSignType.oxygenSaturation,
        value: _randomInRange(96, 100),
        unit: '%',
        timestamp: now.subtract(Duration(minutes: _random.nextInt(15))),
        isCritical: false,
        deviceId: 'pulse-ox-003',
      ),
      new_entities.VitalSignEntity(
        type: new_entities.VitalSignType.respiratoryRate,
        value: _randomInRange(14, 18),
        unit: '/min',
        timestamp: now.subtract(Duration(minutes: _random.nextInt(45))),
        isCritical: false,
      ),
      new_entities.VitalSignEntity(
        type: new_entities.VitalSignType.bloodGlucose,
        value: _randomInRange(85, 120),
        unit: 'mg/dL',
        timestamp: now.subtract(Duration(hours: _random.nextInt(6))),
        isCritical: false,
        deviceId: 'glucose-004',
        notes: 'Fasting glucose',
      ),
      new_entities.VitalSignEntity(
        type: new_entities.VitalSignType.weight,
        value: _randomDoubleInRange(70.0, 75.0),
        unit: 'kg',
        timestamp: now.subtract(const Duration(days: 1)),
        isCritical: false,
        deviceId: 'scale-005',
      ),
    ];
  }

  @override
  Future<List<TaskEntity>> getDailyTasks() async {
    await _simulateNetworkDelay();

    // Return mock daily tasks for treatment plan
    return [
      TaskEntity(
        id: 'task-001',
        title: 'Take Vitamin C',
        time: '08:00 AM',
        type: TaskType.medication,
        isCompleted: true,
        medicationDosage: 1000.0,
        medicationUnit: 'mg',
        description: 'Take with breakfast',
      ),
      TaskEntity(
        id: 'task-002',
        title: 'Measure Blood Pressure',
        time: '10:00 AM',
        type: TaskType.measurement,
        isCompleted: false,
        description: 'Use home BP monitor',
      ),
      TaskEntity(
        id: 'task-003',
        title: 'Evening Cardio',
        time: '06:00 PM',
        type: TaskType.exercise,
        isCompleted: false,
        description: '30 minutes of light cardio',
      ),
      TaskEntity(
        id: 'task-004',
        title: 'Take Aspirin',
        time: '08:00 PM',
        type: TaskType.medication,
        isCompleted: false,
        medicationDosage: 81.0,
        medicationUnit: 'mg',
        description: 'Low-dose aspirin',
      ),
    ];
  }

  // ============================================================
  // Existing API Implementation (using mock data)
  // ============================================================

  @override
  Future<repo.PatientHealthSummary> getPatientHealthSummary(String patientId) async {
    await _simulateNetworkDelay();

    final now = DateTime.now();

    return repo.PatientHealthSummary(
      patientId: patientId,
      patientName: 'John Doe',
      lastUpdated: now,
      vitalSigns: [
        repo.VitalSign(
          type: repo.VitalSignType.heartRate,
          value: _randomInRange(60, 100).toDouble(),
          unit: 'bpm',
          timestamp: now.subtract(Duration(minutes: _random.nextInt(30))),
          isNormal: true,
        ),
        repo.VitalSign(
          type: repo.VitalSignType.bloodPressureSystolic,
          value: _randomInRange(110, 140).toDouble(),
          unit: 'mmHg',
          timestamp: now.subtract(Duration(minutes: _random.nextInt(60))),
          isNormal: true,
        ),
        repo.VitalSign(
          type: repo.VitalSignType.bloodPressureDiastolic,
          value: _randomInRange(70, 90).toDouble(),
          unit: 'mmHg',
          timestamp: now.subtract(Duration(minutes: _random.nextInt(60))),
          isNormal: true,
        ),
        repo.VitalSign(
          type: repo.VitalSignType.temperature,
          value: _randomDoubleInRange(36.2, 37.0),
          unit: '°C',
          timestamp: now.subtract(Duration(hours: _random.nextInt(4))),
          isNormal: true,
        ),
        repo.VitalSign(
          type: repo.VitalSignType.oxygenSaturation,
          value: _randomInRange(96, 100).toDouble(),
          unit: '%',
          timestamp: now.subtract(Duration(minutes: _random.nextInt(15))),
          isNormal: true,
        ),
      ],
      recentObservations: [
        repo.ClinicalObservation(
          id: 'obs-001',
          code: '29463-7',
          displayName: 'Body Weight',
          value: '${_randomDoubleInRange(70, 75).toStringAsFixed(1)} kg',
          effectiveDateTime: now.subtract(const Duration(days: 1)),
          category: 'vital-signs',
        ),
        repo.ClinicalObservation(
          id: 'obs-002',
          code: '8302-2',
          displayName: 'Body Height',
          value: '175 cm',
          effectiveDateTime: now.subtract(const Duration(days: 30)),
          category: 'vital-signs',
        ),
        repo.ClinicalObservation(
          id: 'obs-003',
          code: '39156-5',
          displayName: 'BMI',
          value: '23.5 kg/m²',
          effectiveDateTime: now.subtract(const Duration(days: 1)),
          category: 'vital-signs',
          interpretation: 'Normal',
        ),
      ],
    );
  }

  @override
  Future<List<repo.VitalSign>> getVitalSigns(String patientId) async {
    await _simulateNetworkDelay();

    final now = DateTime.now();

    return [
      repo.VitalSign(
        type: repo.VitalSignType.heartRate,
        value: _randomInRange(60, 100).toDouble(),
        unit: 'bpm',
        timestamp: now.subtract(Duration(minutes: _random.nextInt(30))),
        isNormal: true,
      ),
      repo.VitalSign(
        type: repo.VitalSignType.bloodPressureSystolic,
        value: _randomInRange(110, 140).toDouble(),
        unit: 'mmHg',
        timestamp: now,
        isNormal: true,
      ),
      repo.VitalSign(
        type: repo.VitalSignType.bloodPressureDiastolic,
        value: _randomInRange(70, 90).toDouble(),
        unit: 'mmHg',
        timestamp: now,
        isNormal: true,
      ),
      repo.VitalSign(
        type: repo.VitalSignType.temperature,
        value: _randomDoubleInRange(36.2, 37.0),
        unit: '°C',
        timestamp: now.subtract(Duration(hours: _random.nextInt(4))),
        isNormal: true,
      ),
      repo.VitalSign(
        type: repo.VitalSignType.oxygenSaturation,
        value: _randomInRange(96, 100).toDouble(),
        unit: '%',
        timestamp: now,
        isNormal: true,
      ),
    ];
  }

  @override
  Future<List<repo.ClinicalObservation>> getClinicalObservations(
    String patientId,
  ) async {
    await _simulateNetworkDelay();

    final now = DateTime.now();

    return [
      repo.ClinicalObservation(
        id: 'obs-001',
        code: '29463-7',
        displayName: 'Body Weight',
        value: '72.5 kg',
        effectiveDateTime: now.subtract(const Duration(days: 1)),
        category: 'vital-signs',
      ),
      repo.ClinicalObservation(
        id: 'obs-002',
        code: '8302-2',
        displayName: 'Body Height',
        value: '175 cm',
        effectiveDateTime: now.subtract(const Duration(days: 30)),
        category: 'vital-signs',
      ),
      repo.ClinicalObservation(
        id: 'obs-003',
        code: '2339-0',
        displayName: 'Hemoglobin A1c',
        value: '5.4 %',
        effectiveDateTime: now.subtract(const Duration(days: 14)),
        category: 'laboratory',
        interpretation: 'Normal',
      ),
      repo.ClinicalObservation(
        id: 'obs-004',
        code: '2093-3',
        displayName: 'Total Cholesterol',
        value: '185 mg/dL',
        effectiveDateTime: now.subtract(const Duration(days: 14)),
        category: 'laboratory',
        interpretation: 'Desirable',
      ),
    ];
  }

  @override
  Future<repo.HealthHistory> getHealthHistory(
    String patientId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await _simulateNetworkDelay();

    // Generate mock historical data points
    final dataPoints = <repo.HealthDataPoint>[];
    var currentDate = startDate;

    while (currentDate.isBefore(endDate)) {
      // Heart rate data point
      dataPoints.add(repo.HealthDataPoint(
        timestamp: currentDate,
        metricName: 'heartRate',
        value: _randomInRange(60, 100).toDouble(),
        unit: 'bpm',
      ));

      // Weight data point (daily)
      if (currentDate.hour == 8) {
        dataPoints.add(repo.HealthDataPoint(
          timestamp: currentDate,
          metricName: 'weight',
          value: _randomDoubleInRange(71, 73),
          unit: 'kg',
        ));
      }

      currentDate = currentDate.add(const Duration(hours: 4));
    }

    return repo.HealthHistory(
      patientId: patientId,
      startDate: startDate,
      endDate: endDate,
      dataPoints: dataPoints,
    );
  }

  // ============================================================
  // Helper Methods
  // ============================================================

  /// Generate random integer in range [min, max]
  int _randomInRange(int min, int max) {
    return min + _random.nextInt(max - min + 1);
  }

  /// Generate random double in range [min, max]
  double _randomDoubleInRange(double min, double max) {
    return min + _random.nextDouble() * (max - min);
  }
}

/// Factory to create different mock scenarios
class MockPatientRepositoryFactory {
  MockPatientRepositoryFactory._();

  /// Standard mock with happy path data
  static MockPatientRepository standard() {
    return MockPatientRepository();
  }

  /// Fast mock with minimal latency (for testing)
  static MockPatientRepository fast() {
    return MockPatientRepository(
      simulatedLatency: const Duration(milliseconds: 100),
    );
  }

  /// Mock that always throws errors (for error state testing)
  static MockPatientRepository error() {
    return MockPatientRepository(
      shouldSimulateError: true,
    );
  }

  /// Mock with slow network (for loading state testing)
  static MockPatientRepository slow() {
    return MockPatientRepository(
      simulatedLatency: const Duration(seconds: 3),
    );
  }
}
