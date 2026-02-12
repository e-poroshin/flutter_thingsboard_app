import 'dart:math';

import 'package:thingsboard_app/modules/patient_health/data/datasources/patient_local_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/task_hive_model.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/vital_history_hive_model.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/patient_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_history_point.dart';
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
    this.localDatasource,
  });

  /// Duration to simulate network latency
  final Duration simulatedLatency;

  /// If true, all methods will throw an error (for testing error states)
  final bool shouldSimulateError;

  /// Optional local datasource for task persistence
  /// If provided, tasks will be persisted to local storage
  final PatientLocalDatasource? localDatasource;

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
  Future<List<VitalHistoryPoint>> getVitalHistory(
    String vitalId,
    String range,
  ) async {
    // Step 1: Try to get real data from local storage first
    if (localDatasource != null) {
      try {
        final since = _getSinceFromRange(range);
        final localHistory = await localDatasource!.getVitalHistory(
          vitalId,
          since: since,
        );

        if (localHistory.isNotEmpty) {
          // Real data exists — return it mapped to domain entities
          return localHistory.map((m) => m.toEntity()).toList();
        }
      } catch (e) {
        // Fall through to mock data on error
      }
    }

    // Step 2: No local data — generate mock data for UI development
    await _simulateNetworkDelay();
    return _generateMockHistory(vitalId, range);
  }

  /// Convert range string to a DateTime cutoff
  DateTime _getSinceFromRange(String range) {
    final now = DateTime.now();
    switch (range) {
      case '1D':
        return now.subtract(const Duration(hours: 24));
      case '1W':
        return now.subtract(const Duration(days: 7));
      case '1M':
        return now.subtract(const Duration(days: 30));
      default:
        return now.subtract(const Duration(hours: 24));
    }
  }

  /// Generate mock history data for UI development
  List<VitalHistoryPoint> _generateMockHistory(String vitalId, String range) {
    final now = DateTime.now();
    final List<VitalHistoryPoint> points = [];

    final vitalType = _getVitalTypeFromId(vitalId);
    final (baseValue, minValue, maxValue) = _getVitalRange(vitalType);

    if (range == '1D') {
      for (int i = 23; i >= 0; i--) {
        final timestamp = now.subtract(Duration(hours: i));
        final variation = _randomDoubleInRange(-5, 5);
        final trend = (23 - i) * 0.2;
        final value = (baseValue + variation + trend)
            .clamp(minValue, maxValue)
            .toDouble();
        points.add(VitalHistoryPoint(timestamp: timestamp, value: value));
      }
    } else if (range == '1W') {
      for (int i = 6; i >= 0; i--) {
        final timestamp = now.subtract(Duration(days: i));
        final variation = _randomDoubleInRange(-8, 8);
        final trend = (6 - i) * 0.3;
        final value = (baseValue + variation + trend)
            .clamp(minValue, maxValue)
            .toDouble();
        points.add(VitalHistoryPoint(timestamp: timestamp, value: value));
      }
    } else if (range == '1M') {
      for (int i = 29; i >= 0; i--) {
        final timestamp = now.subtract(Duration(days: i));
        final variation = _randomDoubleInRange(-10, 10);
        final trend = (29 - i) * 0.1;
        final value = (baseValue + variation + trend)
            .clamp(minValue, maxValue)
            .toDouble();
        points.add(VitalHistoryPoint(timestamp: timestamp, value: value));
      }
    }

    return points;
  }

  @override
  Future<void> saveVitalMeasurement({
    required String vitalType,
    required double value,
    String? unit,
  }) async {
    if (localDatasource != null) {
      await localDatasource!.saveVitalMeasurement(
        VitalHistoryHiveModel.fromMeasurement(
          vitalType: vitalType,
          value: value,
          unit: unit,
        ),
      );
    }
  }

  /// Helper to get vital type from ID string
  new_entities.VitalSignType _getVitalTypeFromId(String vitalId) {
    // Map common vital IDs to types
    final idLower = vitalId.toLowerCase();
    if (idLower.contains('heart') || idLower.contains('hr') || idLower.contains('pulse')) {
      return new_entities.VitalSignType.heartRate;
    } else if (idLower.contains('temp') || idLower.contains('temperature')) {
      return new_entities.VitalSignType.temperature;
    } else if (idLower.contains('oxygen') || idLower.contains('spo2') || idLower.contains('o2')) {
      return new_entities.VitalSignType.oxygenSaturation;
    } else if (idLower.contains('respiratory') || idLower.contains('rr')) {
      return new_entities.VitalSignType.respiratoryRate;
    } else if (idLower.contains('glucose') || idLower.contains('sugar')) {
      return new_entities.VitalSignType.bloodGlucose;
    } else if (idLower.contains('weight')) {
      return new_entities.VitalSignType.weight;
    } else {
      // Default to heart rate
      return new_entities.VitalSignType.heartRate;
    }
  }

  /// Get base value and range for a vital type
  (double baseValue, double minValue, double maxValue) _getVitalRange(
    new_entities.VitalSignType type,
  ) {
    switch (type) {
      case new_entities.VitalSignType.heartRate:
        return (75.0, 60.0, 100.0);
      case new_entities.VitalSignType.temperature:
        return (36.5, 35.5, 38.0);
      case new_entities.VitalSignType.oxygenSaturation:
        return (98.0, 95.0, 100.0);
      case new_entities.VitalSignType.respiratoryRate:
        return (16.0, 12.0, 20.0);
      case new_entities.VitalSignType.bloodGlucose:
        return (100.0, 70.0, 140.0);
      case new_entities.VitalSignType.weight:
        return (72.0, 70.0, 75.0);
      default:
        return (75.0, 60.0, 100.0);
    }
  }

  @override
  Future<List<TaskEntity>> getDailyTasks() async {
    await _simulateNetworkDelay();

    // If local datasource is available, use it for persistence
    if (localDatasource != null) {
      try {
        final localTasks = await localDatasource!.getTasks();
        if (localTasks.isNotEmpty) {
          // Return persisted tasks
          return localTasks.map((model) => model.toEntity()).toList();
        }
        // If empty, seed with default tasks and return them
        final defaultTasks = _getDefaultTasks();
        final hiveModels = defaultTasks
            .map((task) => TaskHiveModel.fromEntity(task))
            .toList();
        await localDatasource!.cacheTasks(hiveModels);
        return defaultTasks;
      } catch (e) {
        // If local storage fails, fall back to mock data
        return _getDefaultTasks();
      }
    }

    // Return mock daily tasks for treatment plan (no persistence)
    return _getDefaultTasks();
  }

  /// Get default mock tasks
  List<TaskEntity> _getDefaultTasks() {
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

  @override
  Future<void> addTask(TaskEntity task) async {
    await _simulateNetworkDelay();
    
    // If local datasource is available, persist the task
    if (localDatasource != null) {
      try {
        final hiveModel = TaskHiveModel.fromEntity(task);
        await localDatasource!.saveTask(hiveModel);
      } catch (e) {
        // If persistence fails, just log and continue
        // Task won't be persisted but won't crash the app
      }
    }
    // Note: If no local datasource, task is not persisted (mock mode without storage)
  }

  @override
  Future<void> updateTask(TaskEntity task) async {
    await _simulateNetworkDelay();
    
    // If local datasource is available, persist the update
    if (localDatasource != null) {
      try {
        final hiveModel = TaskHiveModel.fromEntity(task);
        await localDatasource!.updateTask(hiveModel);
      } catch (e) {
        // If persistence fails, just log and continue
        // Task won't be persisted but won't crash the app
      }
    }
    // Note: If no local datasource, task update is not persisted (mock mode without storage)
  }

  @override
  Future<void> saveSensor(String remoteId) async {
    await _simulateNetworkDelay();
    
    // If local datasource is available, persist the sensor ID
    if (localDatasource != null) {
      try {
        await localDatasource!.savePairedSensorId(remoteId);
      } catch (e) {
        // If persistence fails, just log and continue
        // Sensor won't be persisted but won't crash the app
      }
    }
    // Note: If no local datasource, sensor is not persisted (mock mode without storage)
  }

  @override
  Future<String?> getSensorId() async {
    await _simulateNetworkDelay();
    
    // If local datasource is available, get the sensor ID
    if (localDatasource != null) {
      try {
        return await localDatasource!.getPairedSensorId();
      } catch (e) {
        // If retrieval fails, return null
        return null;
      }
    }
    return null;
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
