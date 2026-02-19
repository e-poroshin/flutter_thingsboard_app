import 'dart:async';

import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/network/nest_api_exceptions.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/medplum_remote_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/nest_auth_remote_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/patient_local_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/tb_telemetry_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/health_record_hive_model.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/models.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/task_hive_model.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/vital_history_hive_model.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/health_record_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/patient_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_history_point.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_sign_entity.dart'
    as vitals;
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';

// Type aliases for cleaner code
typedef VitalSignEntity = vitals.VitalSignEntity;
typedef NewVitalSignType = vitals.VitalSignType;

// Alias for the old VitalSign type from the repository interface
typedef LegacyVitalSign = VitalSign;
typedef LegacyVitalSignType = VitalSignType;

/// PATIENT APP: Patient Repository Implementation (Data Layer)
///
/// Combines data from NestJS BFF endpoints that proxy to:
/// - ThingsBoard for IoT device telemetry (vital signs from wearables)
/// - Medplum for FHIR clinical data (observations, conditions)
///
/// **Architecture:**
/// - All data flows through NestJS BFF
/// - Repository fetches linked IDs from user profile first
/// - Uses medplumPatientId for FHIR data
/// - Uses thingsboardDeviceId for telemetry data
/// - Falls back to legacy endpoints if IDs not available

class PatientRepositoryImpl implements IPatientRepository {
  PatientRepositoryImpl({
    required this.authDatasource,
    required this.medplumDatasource,
    required this.telemetryDatasource,
    required this.localDatasource,
    this.logger,
  });

  final INestAuthRemoteDatasource authDatasource;
  final IMedplumRemoteDatasource medplumDatasource;
  final ITbTelemetryDatasource telemetryDatasource;
  final PatientLocalDatasource localDatasource;
  final TbLogger? logger;

  /// Cached user profile (contains linked IDs)
  UserProfileDTO? _cachedProfile;

  /// Completer to deduplicate concurrent fetchUserProfile() calls.
  /// When multiple methods (e.g. getPatientProfile + getLatestVitals) call
  /// fetchUserProfile() in parallel, only ONE network request is made.
  Completer<UserProfileDTO>? _profileCompleter;

  /// Get the current user profile (cached)
  UserProfileDTO? get currentProfile => _cachedProfile;

  // ============================================================
  // Profile Management
  // ============================================================

  /// Fetch and cache the user profile
  /// This MUST be called first to get medplumPatientId and thingsboardDeviceId
  ///
  /// Uses a [Completer] to deduplicate concurrent calls — if three callers
  /// call this at the same time, only one HTTP request is made and the
  /// result is shared.
  Future<UserProfileDTO> fetchUserProfile({bool forceRefresh = false}) async {
    if (_cachedProfile != null && !forceRefresh) {
      return _cachedProfile!;
    }

    // Deduplicate: if a fetch is already in-flight, piggyback on it.
    if (_profileCompleter != null) {
      return _profileCompleter!.future;
    }

    _profileCompleter = Completer<UserProfileDTO>();

    try {
      logger?.debug('PatientRepositoryImpl: Fetching user profile...');

      UserProfileDTO profile;
      try {
        profile = await authDatasource.getProfile();
      } on NestApiException catch (e) {
        // ── Fallback: profile endpoint not available yet ──────────
        if (e.statusCode == 404) {
          logger?.warn(
            'PatientRepositoryImpl: /auth/profile returned 404 — '
            'using minimal fallback profile. '
            'Remote data features will be unavailable.',
          );
          profile = const UserProfileDTO(
            id: '0',
            email: '',
            medplumPatientId: null,
            thingsboardDeviceId: null,
          );
        } else {
          rethrow;
        }
      }

      _cachedProfile = profile;

      logger?.debug(
        'PatientRepositoryImpl: Profile loaded - '
        'medplumPatientId: ${_cachedProfile?.medplumPatientId}, '
        'thingsboardDeviceId: ${_cachedProfile?.thingsboardDeviceId}',
      );

      _profileCompleter!.complete(profile);
      return profile;
    } catch (e) {
      _profileCompleter!.completeError(e);
      rethrow;
    } finally {
      _profileCompleter = null;
    }
  }

  /// Clear the cached profile (e.g., on logout)
  void clearCache() {
    _cachedProfile = null;
  }

  // ============================================================
  // IPatientRepository Implementation
  // ============================================================

  @override
  Future<PatientEntity> getPatientProfile() async {
    // Step 1: Ensure we have the user profile with linked IDs
    final userProfile = await fetchUserProfile();

    // Step 2: Use medplumPatientId if available, otherwise fall back to legacy
    try {
      if (userProfile.hasMedplumPatient) {
        logger?.debug(
          'PatientRepositoryImpl: Fetching Medplum patient ${userProfile.medplumPatientId}',
        );
        final medplumPatient = await medplumDatasource.fetchPatient(
          userProfile.medplumPatientId!,
        );
        return _mapMedplumPatientToEntity(medplumPatient, userProfile);
      } else {
        // Fallback to legacy endpoint
        logger?.debug('PatientRepositoryImpl: Using legacy patient profile endpoint');
        final profileData = await medplumDatasource.fetchPatientProfile();
        return _parsePatientEntity(profileData, userProfile);
      }
    } on NestApiException catch (e) {
      if (e.statusCode == 404) {
        logger?.warn(
          'PatientRepositoryImpl: Patient profile endpoint returned 404 — '
          'using minimal fallback patient entity.',
        );
        return _buildFallbackPatientEntity(userProfile);
      }
      rethrow;
    }
  }

  /// Build a minimal [PatientEntity] from the user profile when
  /// the patient profile endpoint is not available (404).
  PatientEntity _buildFallbackPatientEntity(UserProfileDTO userProfile) {
    return PatientEntity(
      id: userProfile.id,
      fullName: userProfile.fullName,
      email: userProfile.email,
    );
  }

  @override
  Future<List<VitalSignEntity>> getLatestVitals() async {
    // Step 1: Ensure we have the user profile with linked IDs
    final userProfile = await fetchUserProfile();

    // Step 2: Use thingsboardDeviceId if available, otherwise fall back to legacy
    try {
      if (userProfile.hasThingsboardDevice) {
        logger?.debug(
          'PatientRepositoryImpl: Fetching telemetry for device ${userProfile.thingsboardDeviceId}',
        );
        final telemetry = await telemetryDatasource.fetchLatestTelemetry(
          userProfile.thingsboardDeviceId!,
        );
        return _mapTelemetryToVitals(telemetry);
      } else {
        // Fallback to legacy endpoint
        logger?.debug('PatientRepositoryImpl: Using legacy vitals endpoint');
        final vitalsData = await telemetryDatasource.fetchLatestVitals();
        return _parseVitalSignEntities(vitalsData);
      }
    } on NestApiException catch (e) {
      if (e.statusCode == 404) {
        logger?.warn(
          'PatientRepositoryImpl: Vitals endpoint returned 404 — '
          'returning empty vitals list.',
        );
        return [];
      }
      rethrow;
    }
  }

  @override
  Future<List<TaskEntity>> getDailyTasks() async {
    logger?.debug('PatientRepositoryImpl: Getting daily tasks from local storage');

    try {
      // Step 1: Fetch from Local Datasource
      final localTasks = await localDatasource.getTasks();

      // Step 2: Check if empty (First Run) - seed with default tasks
      if (localTasks.isEmpty) {
        logger?.debug(
          'PatientRepositoryImpl: No tasks found in local storage. Seeding default tasks...',
        );

        // Generate default/mock tasks (same as MockPatientRepository)
        final defaultTasks = _generateDefaultTasks();

        // Convert to Hive models and cache them
        final hiveModels = defaultTasks
            .map((task) => TaskHiveModel.fromEntity(task))
            .toList();
        await localDatasource.cacheTasks(hiveModels);

        logger?.debug(
          'PatientRepositoryImpl: Seeded ${defaultTasks.length} default tasks',
        );

        // Return the default tasks
        return defaultTasks;
      }

      // Step 3: If not empty, return local data mapped to Entities
      final entities = localTasks.map((model) => model.toEntity()).toList();
      logger?.debug(
        'PatientRepositoryImpl: Retrieved ${entities.length} tasks from local storage',
      );
      return entities;
    } catch (e, s) {
      logger?.error(
        'PatientRepositoryImpl: Error getting daily tasks',
        e,
        s,
      );
      // On error, return empty list rather than crashing
      return [];
    }
  }

  /// Generate default tasks for first-time users
  /// These match the mock data from MockPatientRepository
  List<TaskEntity> _generateDefaultTasks() {
    return [
      TaskEntity(
        id: 'task-001',
        title: 'Take Vitamin C',
        time: '08:00 AM',
        type: TaskType.medication,
        isCompleted: false,
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

  /// Add a new task to local storage
  /// This is called when user creates a custom reminder
  Future<void> addTask(TaskEntity task) async {
    logger?.debug('PatientRepositoryImpl: Adding task "${task.id}"');
    try {
      final hiveModel = TaskHiveModel.fromEntity(task);
      await localDatasource.saveTask(hiveModel);
      logger?.debug('PatientRepositoryImpl: Task "${task.id}" saved successfully');
    } catch (e, s) {
      logger?.error(
        'PatientRepositoryImpl: Error adding task',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Update an existing task (e.g., toggle completion)
  Future<void> updateTask(TaskEntity task) async {
    logger?.debug('PatientRepositoryImpl: Updating task "${task.id}"');
    try {
      final hiveModel = TaskHiveModel.fromEntity(task);
      await localDatasource.updateTask(hiveModel);
      logger?.debug('PatientRepositoryImpl: Task "${task.id}" updated successfully');
    } catch (e, s) {
      logger?.error(
        'PatientRepositoryImpl: Error updating task',
        e,
        s,
      );
      rethrow;
    }
  }

  @override
  Future<void> addHealthRecord(HealthRecordEntity record) async {
    logger?.debug('PatientRepositoryImpl: Adding health record "${record.id}"');
    try {
      final hiveModel = HealthRecordHiveModel.fromEntity(record);
      await localDatasource.saveHealthRecord(hiveModel);
      logger?.debug(
        'PatientRepositoryImpl: Health record "${record.id}" saved successfully',
      );
    } catch (e, s) {
      logger?.error(
        'PatientRepositoryImpl: Error adding health record',
        e,
        s,
      );
      rethrow;
    }
  }

  @override
  Future<List<HealthRecordEntity>> getHealthRecords() async {
    logger?.debug('PatientRepositoryImpl: Getting health records');
    try {
      final hiveModels = await localDatasource.getHealthRecords();
      final entities = hiveModels.map((m) => m.toEntity()).toList();
      logger?.debug(
        'PatientRepositoryImpl: Retrieved ${entities.length} health records',
      );
      return entities;
    } catch (e, s) {
      logger?.error(
        'PatientRepositoryImpl: Error getting health records',
        e,
        s,
      );
      return [];
    }
  }

  @override
  Future<void> saveSensor(String remoteId) async {
    logger?.debug('PatientRepositoryImpl: Saving sensor ID: $remoteId');
    try {
      await localDatasource.savePairedSensorId(remoteId);
      logger?.debug('PatientRepositoryImpl: Sensor "$remoteId" saved successfully');
    } catch (e, s) {
      logger?.error(
        'PatientRepositoryImpl: Error saving sensor',
        e,
        s,
      );
      rethrow;
    }
  }

  @override
  Future<String?> getSensorId() async {
    logger?.debug('PatientRepositoryImpl: Getting paired sensor ID');
    try {
      final sensorId = await localDatasource.getPairedSensorId();
      logger?.debug('PatientRepositoryImpl: Retrieved sensor ID: $sensorId');
      return sensorId;
    } catch (e, s) {
      logger?.error(
        'PatientRepositoryImpl: Error getting sensor ID',
        e,
        s,
      );
      return null;
    }
  }

  @override
  Future<List<VitalHistoryPoint>> getVitalHistory(
    String vitalId,
    String range,
  ) async {
    final since = _getSinceFromRange(range);
    final now = DateTime.now();

    // ── Step 1: Fetch Remote observations from Medplum ──────────
    List<VitalHistoryPoint> remotePoints = [];
    try {
      final profile = await fetchUserProfile();

      if (profile.hasMedplumPatient) {
        final loincCode = _vitalIdToLoincCode(vitalId);

        if (loincCode != null) {
          logger?.debug(
            'PatientRepositoryImpl: Fetching remote observations for '
            '$vitalId (LOINC: $loincCode) since $since',
          );

          final observations =
              await medplumDatasource.fetchObservationsByCode(
            profile.medplumPatientId!,
            code: loincCode,
            from: since,
            to: now,
          );

          remotePoints = observations
              .where((obs) => obs.numericValue != null)
              .map((obs) => VitalHistoryPoint(
                    timestamp: obs.effectiveDateTime ?? now,
                    value: obs.numericValue!,
                  ))
              .toList();

          logger?.debug(
            'PatientRepositoryImpl: Got ${remotePoints.length} remote '
            'points for $vitalId',
          );
        } else {
          logger?.debug(
            'PatientRepositoryImpl: No LOINC mapping for "$vitalId", '
            'skipping remote fetch',
          );
        }
      }
    } catch (e) {
      logger?.warn(
        'PatientRepositoryImpl: Error fetching remote history for '
        '$vitalId: $e',
      );
      // Continue — local data alone is still valuable
    }

    // ── Step 2: Fetch Local history (all Hive items for this type) ──
    List<VitalHistoryPoint> localPoints = [];
    try {
      final localHistory = await localDatasource.getVitalHistory(
        vitalId,
        since: since,
      );

      localPoints = localHistory
          .map((m) => VitalHistoryPoint(
                timestamp: m.timestamp,
                value: m.value,
              ))
          .toList();

      logger?.debug(
        'PatientRepositoryImpl: Got ${localPoints.length} local '
        'points for $vitalId',
      );
    } catch (e) {
      logger?.warn(
        'PatientRepositoryImpl: Error reading local history for '
        '$vitalId: $e',
      );
    }

    // ── Step 3: Fetch unsynced (dirty) items ────────────────────
    // These are measurements collected by BLE but not yet pushed
    // to the backend — we still want them on the chart so the user
    // sees their latest readings immediately.
    List<VitalHistoryPoint> dirtyPoints = [];
    try {
      final dirtyItems = await localDatasource.getDirtyMeasurements();

      dirtyPoints = dirtyItems
          .where((m) =>
              m.vitalType == vitalId && m.timestamp.isAfter(since))
          .map((m) => VitalHistoryPoint(
                timestamp: m.timestamp,
                value: m.value,
              ))
          .toList();

      if (dirtyPoints.isNotEmpty) {
        logger?.debug(
          'PatientRepositoryImpl: Including ${dirtyPoints.length} '
          'unsynced points for $vitalId',
        );
      }
    } catch (e) {
      logger?.warn(
        'PatientRepositoryImpl: Error reading dirty measurements: $e',
      );
    }

    // ── Step 4: Merge, deduplicate & sort ───────────────────────
    // Remote data is the source of truth. Local + dirty data fills
    // gaps (recent BLE readings not yet on the server).
    //
    // Deduplication: two points are considered the same if their
    // timestamps match within a 1-second window AND their values
    // are identical. This prevents duplicates when a measurement
    // has been synced but still exists in Hive.
    final merged = <VitalHistoryPoint>[];

    // Add remote first (source of truth)
    merged.addAll(remotePoints);

    // Then add local points that don't overlap with remote
    for (final local in [...localPoints, ...dirtyPoints]) {
      final isDuplicate = merged.any((existing) =>
          (existing.timestamp.difference(local.timestamp).inSeconds).abs() <
              2 &&
          (existing.value - local.value).abs() < 0.001);
      if (!isDuplicate) {
        merged.add(local);
      }
    }

    // Sort ascending by timestamp (charts expect chronological order)
    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    logger?.debug(
      'PatientRepositoryImpl: Returning ${merged.length} merged '
      'history points for $vitalId '
      '(${remotePoints.length} remote + '
      '${localPoints.length} local + '
      '${dirtyPoints.length} dirty, deduplicated)',
    );

    return merged;
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

  @override
  Future<void> saveVitalMeasurement({
    required String vitalType,
    required double value,
    String? unit,
  }) async {
    // ── WAL Step 1: Persist locally with SyncStatus.dirty ──────────
    // This guarantees that data is never lost, even if the network
    // call below fails or the app is killed before it completes.
    final measurement = VitalHistoryHiveModel.fromMeasurement(
      vitalType: vitalType,
      value: value,
      unit: unit,
      syncStatus: SyncStatus.dirty,
    );

    try {
      await localDatasource.saveVitalMeasurement(measurement);
    } catch (e) {
      logger?.warn(
        'PatientRepositoryImpl: Error saving vital measurement to Hive: $e',
      );
      // If even local persistence fails, there's nothing more we can do.
      return;
    }

    // ── WAL Step 2: Optimistic network push ────────────────────────
    // Try to send immediately. If it works we mark as synced right
    // away; if it fails, the measurement stays dirty and will be
    // picked up by the TelemetrySyncWorker later.
    try {
      final profile = await fetchUserProfile();

      if (profile.hasThingsboardDevice) {
        final dto = TelemetryRequestDto.fromHiveModel(
          model: measurement,
          deviceId: profile.thingsboardDeviceId!,
          tenantId: profile.id, // tenant derived from user profile
        );

        await telemetryDatasource.pushTelemetry(dto);

        // ── WAL Step 3a: Mark synced ──────────────────────────────
        measurement.syncStatus = SyncStatus.synced;
        await measurement.save(); // HiveObject.save() updates in-place

        logger?.debug(
          'PatientRepositoryImpl: Measurement pushed & synced '
          '($vitalType = $value)',
        );
      } else {
        logger?.debug(
          'PatientRepositoryImpl: No thingsboardDeviceId — '
          'measurement saved locally as dirty',
        );
      }
    } catch (e) {
      // ── WAL Step 3b: Leave as dirty ─────────────────────────────
      // Network/server error — the TelemetrySyncWorker will retry.
      logger?.warn(
        'PatientRepositoryImpl: Optimistic push failed for '
        '$vitalType=$value, will retry later. Error: $e',
      );
    }
  }

  // ============================================================
  // Vitals History
  // ============================================================

  // ============================================================
  // Additional Data Methods
  // ============================================================

  /// Get vital signs history for a date range
  Future<List<VitalSignEntity>> getVitalsHistory({
    required DateTime startDate,
    required DateTime endDate,
    List<String>? keys,
  }) async {
    final userProfile = await fetchUserProfile();

    try {
      if (userProfile.hasThingsboardDevice) {
        final history = await telemetryDatasource.fetchTelemetryHistory(
          userProfile.thingsboardDeviceId!,
          startTs: startDate.millisecondsSinceEpoch,
          endTs: endDate.millisecondsSinceEpoch,
          keys: keys,
        );
        return _mapTelemetryHistoryToVitals(history);
      } else {
        // Fallback to legacy endpoint
        final historyData = await telemetryDatasource.fetchVitalsHistory(
          startTs: startDate.millisecondsSinceEpoch,
          endTs: endDate.millisecondsSinceEpoch,
          keys: keys,
        );
        return _parseVitalsHistoryData(historyData);
      }
    } on NestApiException catch (e) {
      if (e.statusCode == 404) {
        logger?.warn(
          'PatientRepositoryImpl: Vitals history endpoint returned 404 — '
          'returning empty history.',
        );
        return [];
      }
      rethrow;
    }
  }

  /// Get patient's clinical observations from Medplum (raw data)
  Future<List<Map<String, dynamic>>> _fetchClinicalObservationsRaw() async {
    final userProfile = await fetchUserProfile();

    try {
      if (userProfile.hasMedplumPatient) {
        return await medplumDatasource.fetchObservations(
          userProfile.medplumPatientId!,
        );
      } else {
        return await medplumDatasource.fetchPatientObservations();
      }
    } on NestApiException catch (e) {
      if (e.statusCode == 404) {
        logger?.warn(
          'PatientRepositoryImpl: Observations endpoint returned 404 — '
          'returning empty observations list.',
        );
        return [];
      }
      rethrow;
    }
  }

  /// Get patient's clinical observations (IPatientRepository interface)
  Future<List<ClinicalObservation>> getClinicalObservations(
    String patientId,
  ) async {
    final rawObservations = await _fetchClinicalObservationsRaw();
    return _parseClinicalObservations(rawObservations);
  }

  /// Get patient's conditions from Medplum
  Future<List<Map<String, dynamic>>> getConditions() async {
    final userProfile = await fetchUserProfile();

    if (userProfile.hasMedplumPatient) {
      try {
        return await medplumDatasource.fetchConditions(
          userProfile.medplumPatientId!,
        );
      } on NestApiException catch (e) {
        if (e.statusCode == 404) {
          logger?.warn(
            'PatientRepositoryImpl: Conditions endpoint returned 404 — '
            'returning empty list.',
          );
          return [];
        }
        rethrow;
      }
    }
    return [];
  }

  /// Get patient's medications from Medplum
  Future<List<Map<String, dynamic>>> getMedications() async {
    final userProfile = await fetchUserProfile();

    if (userProfile.hasMedplumPatient) {
      try {
        return await medplumDatasource.fetchMedications(
          userProfile.medplumPatientId!,
        );
      } on NestApiException catch (e) {
        if (e.statusCode == 404) {
          logger?.warn(
            'PatientRepositoryImpl: Medications endpoint returned 404 — '
            'returning empty list.',
          );
          return [];
        }
        rethrow;
      }
    }
    return [];
  }

  // ============================================================
  // Legacy IPatientRepository Methods (for BLoC compatibility)
  // ============================================================

  /// Get combined patient health summary (legacy method)
  ///
  /// Each data source is fetched independently with its own error handling.
  /// If one source fails (e.g. 404 because backend hasn't implemented it),
  /// the other sources still contribute data and the UI renders with
  /// whatever is available — rather than crashing the entire summary.
  @override
  Future<PatientHealthSummary> getPatientHealthSummary(String patientId) async {
    logger?.debug('PatientRepositoryImpl: Getting health summary');

    // ── Pre-fetch user profile once (deduplication via Completer) ───
    // This avoids 3–4 parallel calls to /auth/profile.
    await fetchUserProfile();

    // ── Fetch each data source independently ───────────────────────
    // Using individual try-catch instead of Future.wait so one 404
    // doesn't kill the entire summary.
    PatientEntity? patientEntity;
    List<VitalSignEntity> vitalEntities = [];
    List<Map<String, dynamic>> observations = [];
    List<HealthRecordEntity> healthRecords = [];

    // Fetch in parallel but handle errors individually
    await Future.wait([
      // 1. Patient profile
      (() async {
        try {
          patientEntity = await getPatientProfile();
        } catch (e) {
          logger?.warn(
            'PatientRepositoryImpl: Error fetching patient profile '
            'for health summary: $e',
          );
        }
      })(),
      // 2. Latest vitals
      (() async {
        try {
          vitalEntities = await getLatestVitals();
        } catch (e) {
          logger?.warn(
            'PatientRepositoryImpl: Error fetching latest vitals '
            'for health summary: $e',
          );
        }
      })(),
      // 3. Clinical observations
      (() async {
        try {
          observations = await _fetchClinicalObservationsRaw();
        } catch (e) {
          logger?.warn(
            'PatientRepositoryImpl: Error fetching observations '
            'for health summary: $e',
          );
        }
      })(),
      // 4. Health records (local — should never fail)
      (() async {
        try {
          healthRecords = await getHealthRecords();
        } catch (e) {
          logger?.warn(
            'PatientRepositoryImpl: Error fetching health records '
            'for health summary: $e',
          );
        }
      })(),
    ]);

    // ── Build summary from whatever data we got ────────────────────
    final patient = patientEntity ??
        _buildFallbackPatientEntity(
          _cachedProfile ??
              const UserProfileDTO(
                id: '0',
                email: '',
                medplumPatientId: null,
                thingsboardDeviceId: null,
              ),
        );

    final legacyVitalSigns =
        vitalEntities.map(_mapToLegacyVitalSign).toList();
    final clinicalObservations = _parseClinicalObservations(observations);

    logger?.debug(
      'PatientRepositoryImpl: Health summary assembled — '
      'patient: ${patient.fullName}, '
      'vitals: ${legacyVitalSigns.length}, '
      'observations: ${clinicalObservations.length}, '
      'records: ${healthRecords.length}',
    );

    return PatientHealthSummary(
      patientId: patientId,
      patientName: patient.fullName,
      lastUpdated: DateTime.now(),
      vitalSigns: legacyVitalSigns,
      recentObservations: clinicalObservations,
      recentRecords: healthRecords,
    );
  }

  /// Get patient's vital signs (legacy method)
  @override
  Future<List<LegacyVitalSign>> getVitalSigns(String patientId) async {
    final vitalEntities = await getLatestVitals();
    return vitalEntities.map(_mapToLegacyVitalSign).toList();
  }

  /// Get patient's health history (legacy method)
  @override
  Future<HealthHistory> getHealthHistory(
    String patientId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final vitalsHistory = await getVitalsHistory(
      startDate: startDate,
      endDate: endDate,
    );

    final dataPoints = vitalsHistory.map((vital) => HealthDataPoint(
      timestamp: vital.timestamp,
      metricName: vital.type.displayName,
      value: vital.numericValue ?? 0.0,
      unit: vital.unit,
    )).toList();

    return HealthHistory(
      patientId: patientId,
      startDate: startDate,
      endDate: endDate,
      dataPoints: dataPoints,
    );
  }

  // ============================================================
  // Private Mapping Methods
  // ============================================================

  /// Convert new VitalSignEntity to legacy VitalSign
  LegacyVitalSign _mapToLegacyVitalSign(VitalSignEntity entity) {
    // Map new VitalSignType to legacy VitalSignType
    final legacyType = switch (entity.type) {
      NewVitalSignType.heartRate => LegacyVitalSignType.heartRate,
      NewVitalSignType.bloodPressure => LegacyVitalSignType.bloodPressureSystolic,
      NewVitalSignType.temperature => LegacyVitalSignType.temperature,
      NewVitalSignType.oxygenSaturation => LegacyVitalSignType.oxygenSaturation,
      NewVitalSignType.respiratoryRate => LegacyVitalSignType.respiratoryRate,
      NewVitalSignType.bloodGlucose => LegacyVitalSignType.bloodGlucose,
      NewVitalSignType.weight => LegacyVitalSignType.weight,
      // Height and BMI don't have legacy equivalents, map to weight as fallback
      NewVitalSignType.height => LegacyVitalSignType.weight,
      NewVitalSignType.bmi => LegacyVitalSignType.weight,
    };

    return LegacyVitalSign(
      type: legacyType,
      value: entity.numericValue ?? 0.0,
      unit: entity.unit,
      timestamp: entity.timestamp,
      isNormal: !entity.isCritical,
    );
  }

  /// Parse clinical observations from raw data
  List<ClinicalObservation> _parseClinicalObservations(
    List<Map<String, dynamic>> observations,
  ) {
    return observations.map((obs) {
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

  /// Map MedplumPatientDTO to PatientEntity
  PatientEntity _mapMedplumPatientToEntity(
    MedplumPatientDTO medplumPatient,
    UserProfileDTO userProfile,
  ) {
    // Parse gender
    Gender gender = Gender.unknown;
    if (medplumPatient.gender != null) {
      gender = switch (medplumPatient.gender!.toLowerCase()) {
        'male' => Gender.male,
        'female' => Gender.female,
        'other' => Gender.other,
        _ => Gender.unknown,
      };
    }

    return PatientEntity(
      id: medplumPatient.id,
      fullName: medplumPatient.fullName,
      email: medplumPatient.email ?? userProfile.email,
      avatarUrl: medplumPatient.photoUrl,
      dateOfBirth: medplumPatient.birthDateTime,
      phoneNumber: medplumPatient.phone,
      gender: gender,
      address: medplumPatient.address?.firstOrNull?.fullAddress,
    );
  }

  /// Map ThingsboardTelemetryDTO to VitalSignEntity list
  List<VitalSignEntity> _mapTelemetryToVitals(ThingsboardTelemetryDTO telemetry) {
    final vitalsList = <VitalSignEntity>[];

    for (final key in telemetry.keys) {
      final type = _mapKeyToVitalType(key);
      if (type == null) continue;

      final telemetryValue = telemetry.getLatestValue(key);
      if (telemetryValue == null) continue;

      final numValue = telemetryValue.numericValue;
      final isCritical = numValue != null ? !type.isValueNormal(numValue) : false;

      vitalsList.add(VitalSignEntity(
        type: type,
        value: telemetryValue.value,
        unit: type.defaultUnit,
        timestamp: telemetryValue.timestamp,
        isCritical: isCritical,
      ));
    }

    return vitalsList;
  }

  /// Map TelemetryHistoryDTO to VitalSignEntity list
  List<VitalSignEntity> _mapTelemetryHistoryToVitals(TelemetryHistoryDTO history) {
    final vitalsList = <VitalSignEntity>[];

    for (final key in history.keys) {
      final type = _mapKeyToVitalType(key);
      if (type == null) continue;

      for (final value in history.getValues(key)) {
        final numValue = value.numericValue;
        final isCritical = numValue != null ? !type.isValueNormal(numValue) : false;

        vitalsList.add(VitalSignEntity(
          type: type,
          value: value.value,
          unit: type.defaultUnit,
          timestamp: value.timestamp,
          isCritical: isCritical,
        ));
      }
    }

    // Sort by timestamp descending
    vitalsList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return vitalsList;
  }

  /// Parse legacy profile data to PatientEntity
  PatientEntity _parsePatientEntity(
    Map<String, dynamic> data,
    UserProfileDTO userProfile,
  ) {
    final firstName = data['firstName'] as String? ?? userProfile.firstName ?? '';
    final lastName = data['lastName'] as String? ?? userProfile.lastName ?? '';
    final fullName = data['fullName'] as String? ??
        data['name'] as String? ??
        '$firstName $lastName'.trim();

    Gender gender = Gender.unknown;
    final genderStr = data['gender'] as String?;
    if (genderStr != null) {
      gender = switch (genderStr.toLowerCase()) {
        'male' || 'm' => Gender.male,
        'female' || 'f' => Gender.female,
        'other' || 'o' => Gender.other,
        _ => Gender.unknown,
      };
    }

    DateTime? dob;
    final dobStr = data['dateOfBirth'] as String? ?? data['birthDate'] as String?;
    if (dobStr != null) {
      dob = DateTime.tryParse(dobStr);
    }

    return PatientEntity(
      id: data['id'] as String? ?? userProfile.id,
      fullName: fullName.isNotEmpty ? fullName : userProfile.fullName,
      email: data['email'] as String? ?? userProfile.email,
      avatarUrl: data['avatarUrl'] as String? ?? data['photo'] as String?,
      dateOfBirth: dob,
      phoneNumber: data['phone'] as String? ?? data['phoneNumber'] as String?,
      gender: gender,
      address: data['address'] as String?,
    );
  }

  /// Parse legacy vitals data to VitalSignEntity list
  List<VitalSignEntity> _parseVitalSignEntities(Map<String, dynamic> data) {
    final vitalsList = <VitalSignEntity>[];

    for (final entry in data.entries) {
      final type = _mapKeyToVitalType(entry.key);
      if (type == null || entry.value == null) continue;

      dynamic value = entry.value;
      DateTime timestamp = DateTime.now();

      // Handle nested format: { "value": 72, "ts": 1234567890 }
      if (value is Map) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(
          (value['ts'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        );
        value = value['value'];
      }

      final numValue = value is num ? value.toDouble() : null;
      final isCritical = numValue != null ? !type.isValueNormal(numValue) : false;

      vitalsList.add(VitalSignEntity(
        type: type,
        value: value,
        unit: type.defaultUnit,
        timestamp: timestamp,
        isCritical: isCritical,
      ));
    }

    return vitalsList;
  }

  /// Parse legacy history data to VitalSignEntity list
  List<VitalSignEntity> _parseVitalsHistoryData(List<Map<String, dynamic>> data) {
    final vitalsList = <VitalSignEntity>[];

    for (final item in data) {
      final key = item['key'] as String? ?? '';
      final type = _mapKeyToVitalType(key);
      if (type == null) continue;

      final value = item['value'];
      final ts = item['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(ts);

      final numValue = value is num ? value.toDouble() : null;
      final isCritical = numValue != null ? !type.isValueNormal(numValue) : false;

      vitalsList.add(VitalSignEntity(
        type: type,
        value: value,
        unit: type.defaultUnit,
        timestamp: timestamp,
        isCritical: isCritical,
      ));
    }

    vitalsList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return vitalsList;
  }

  /// Map telemetry key to VitalSignType
  NewVitalSignType? _mapKeyToVitalType(String key) {
    return switch (key.toLowerCase()) {
      'heartrate' || 'heart_rate' || 'hr' => NewVitalSignType.heartRate,
      'bloodpressure' || 'blood_pressure' || 'bp' => NewVitalSignType.bloodPressure,
      'temperature' || 'temp' || 'body_temp' => NewVitalSignType.temperature,
      'oxygensaturation' || 'spo2' || 'oxygen' => NewVitalSignType.oxygenSaturation,
      'respiratoryrate' || 'respiratory_rate' || 'rr' => NewVitalSignType.respiratoryRate,
      'bloodglucose' || 'glucose' || 'bg' => NewVitalSignType.bloodGlucose,
      'weight' || 'body_weight' => NewVitalSignType.weight,
      _ => null,
    };
  }

  // ============================================================
  // LOINC Code Mapping (vitalId → FHIR Observation code)
  // ============================================================

  /// Map an app-level vital ID (e.g., `"temperature"`) to its
  /// corresponding LOINC code for FHIR Observation queries.
  ///
  /// **Standard LOINC codes used:**
  /// | vitalId             | LOINC   | Description              |
  /// |---------------------|---------|--------------------------|
  /// | temperature         | 8310-5  | Body Temperature         |
  /// | heartrate / hr      | 8867-4  | Heart Rate               |
  /// | bloodpressure / bp  | 85354-9 | Blood Pressure Panel     |
  /// | spo2 / oxygen       | 2708-6  | SpO2                     |
  /// | respiratoryrate     | 9279-1  | Respiratory Rate         |
  /// | bloodglucose        | 2339-0  | Blood Glucose            |
  /// | weight              | 29463-7 | Body Weight              |
  /// | humidity            | —       | No standard LOINC        |
  ///
  /// Returns `null` if no mapping exists (e.g. humidity, which is
  /// device-specific and not a clinical vital sign).
  static String? _vitalIdToLoincCode(String vitalId) {
    return switch (vitalId.toLowerCase()) {
      'temperature' || 'temp' || 'body_temp' => '8310-5',
      'heartrate' || 'heart_rate' || 'hr' => '8867-4',
      'bloodpressure' || 'blood_pressure' || 'bp' => '85354-9',
      'oxygensaturation' || 'spo2' || 'oxygen' => '2708-6',
      'respiratoryrate' || 'respiratory_rate' || 'rr' => '9279-1',
      'bloodglucose' || 'glucose' || 'bg' => '2339-0',
      'weight' || 'body_weight' => '29463-7',
      _ => null,
    };
  }
}
