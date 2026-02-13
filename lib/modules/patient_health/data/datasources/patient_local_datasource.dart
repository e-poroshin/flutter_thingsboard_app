import 'package:hive_flutter/hive_flutter.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/health_record_hive_model.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/task_hive_model.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/vital_history_hive_model.dart';

/// PATIENT APP: Patient Local Datasource
///
/// Handles local persistence of tasks and vital history using Hive.
/// Provides CRUD operations for tasks and time-series vital data.

class PatientLocalDatasource {
  PatientLocalDatasource({
    required this.logger,
  });

  final TbLogger logger;
  static const String _boxName = 'tasks_box';
  static const String _settingsBoxName = 'settings_box';
  static const String _vitalHistoryBoxName = 'vital_history_box';
  static const String _healthRecordBoxName = 'health_records_box';
  static const int _maxHistoryPointsPerType = 1000;
  Box<TaskHiveModel>? _box;
  Box<VitalHistoryHiveModel>? _vitalHistoryBox;
  Box<HealthRecordHiveModel>? _healthRecordBox;

  /// Initialize Hive boxes for tasks and settings
  /// Must be called before any other operations
  Future<void> init() async {
    try {
      // Open tasks box
      if (!Hive.isBoxOpen(_boxName)) {
        _box = await Hive.openBox<TaskHiveModel>(_boxName);
        logger.debug(
          'PatientLocalDatasource: Opened Hive box "$_boxName" with ${_box!.length} tasks',
        );
      } else {
        _box = Hive.box<TaskHiveModel>(_boxName);
        logger.debug(
          'PatientLocalDatasource: Using existing Hive box "$_boxName"',
        );
      }

      // Open settings box (stores paired sensor ID, etc.)
      // Must be opened eagerly so getPairedSensorId() works on cold startup
      if (!Hive.isBoxOpen(_settingsBoxName)) {
        await Hive.openBox(_settingsBoxName);
        logger.debug(
          'PatientLocalDatasource: Opened Hive box "$_settingsBoxName"',
        );
      }

      // Open vital history box (stores time-series vital measurements from BLE)
      if (!Hive.isBoxOpen(_vitalHistoryBoxName)) {
        _vitalHistoryBox =
            await Hive.openBox<VitalHistoryHiveModel>(_vitalHistoryBoxName);
        logger.debug(
          'PatientLocalDatasource: Opened Hive box "$_vitalHistoryBoxName" '
          'with ${_vitalHistoryBox!.length} measurements',
        );
      } else {
        _vitalHistoryBox =
            Hive.box<VitalHistoryHiveModel>(_vitalHistoryBoxName);
        logger.debug(
          'PatientLocalDatasource: Using existing Hive box "$_vitalHistoryBoxName"',
        );
      }

      // Open health records box (stores patient-reported symptoms/mood)
      if (!Hive.isBoxOpen(_healthRecordBoxName)) {
        _healthRecordBox =
            await Hive.openBox<HealthRecordHiveModel>(_healthRecordBoxName);
        logger.debug(
          'PatientLocalDatasource: Opened Hive box "$_healthRecordBoxName" '
          'with ${_healthRecordBox!.length} records',
        );
      } else {
        _healthRecordBox =
            Hive.box<HealthRecordHiveModel>(_healthRecordBoxName);
        logger.debug(
          'PatientLocalDatasource: Using existing Hive box "$_healthRecordBoxName"',
        );
      }
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error initializing Hive box',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Get all tasks from local storage
  Future<List<TaskHiveModel>> getTasks() async {
    try {
      _ensureInitialized();
      final tasks = _box!.values.toList();
      logger.debug('PatientLocalDatasource: Retrieved ${tasks.length} tasks');
      return tasks;
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error getting tasks',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Save a single task to local storage
  /// If task with same ID exists, it will be updated
  Future<void> saveTask(TaskHiveModel task) async {
    try {
      _ensureInitialized();
      await _box!.put(task.id, task);
      logger.debug('PatientLocalDatasource: Saved task "${task.id}"');
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error saving task',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Update an existing task
  /// This is essentially the same as saveTask, but kept for clarity
  Future<void> updateTask(TaskHiveModel task) async {
    await saveTask(task);
  }

  /// Cache a list of tasks (replaces all existing tasks)
  /// Useful for initial seeding or bulk updates
  Future<void> cacheTasks(List<TaskHiveModel> tasks) async {
    try {
      _ensureInitialized();
      
      // Clear existing tasks
      await _box!.clear();
      
      // Add all new tasks
      final Map<String, TaskHiveModel> tasksMap = {
        for (final task in tasks) task.id: task,
      };
      await _box!.putAll(tasksMap);
      
      logger.debug(
        'PatientLocalDatasource: Cached ${tasks.length} tasks (replaced existing)',
      );
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error caching tasks',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Delete a task by ID
  Future<void> deleteTask(String taskId) async {
    try {
      _ensureInitialized();
      await _box!.delete(taskId);
      logger.debug('PatientLocalDatasource: Deleted task "$taskId"');
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error deleting task',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Clear all tasks
  Future<void> clearAll() async {
    try {
      _ensureInitialized();
      await _box!.clear();
      logger.debug('PatientLocalDatasource: Cleared all tasks');
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error clearing tasks',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Save paired sensor ID
  /// Stores the BLE device remote ID for later retrieval
  Future<void> savePairedSensorId(String remoteId) async {
    try {
      // Ensure settings box is open (may not be if init() hasn't completed)
      if (!Hive.isBoxOpen(_settingsBoxName)) {
        await Hive.openBox(_settingsBoxName);
      }
      final settingsBox = Hive.box(_settingsBoxName);
      await settingsBox.put('paired_sensor_id', remoteId);
      logger.debug('PatientLocalDatasource: Saved paired sensor ID: $remoteId');
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error saving paired sensor ID',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Get paired sensor ID
  /// Returns the stored BLE device remote ID, or null if not set.
  /// Opens settings_box if not already open (handles cold startup race condition).
  Future<String?> getPairedSensorId() async {
    try {
      if (!Hive.isBoxOpen(_settingsBoxName)) {
        await Hive.openBox(_settingsBoxName);
      }
      final settingsBox = Hive.box(_settingsBoxName);
      final sensorId = settingsBox.get('paired_sensor_id') as String?;
      logger.debug('PatientLocalDatasource: Retrieved paired sensor ID: $sensorId');
      return sensorId;
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error getting paired sensor ID',
        e,
        s,
      );
      return null;
    }
  }

  // ============================================================
  // Vital History Methods
  // ============================================================

  /// Save a single vital measurement to history.
  /// Appends the measurement and trims oldest entries if the list
  /// exceeds [_maxHistoryPointsPerType] for that vital type.
  Future<void> saveVitalMeasurement(VitalHistoryHiveModel measurement) async {
    try {
      if (_vitalHistoryBox == null || !_vitalHistoryBox!.isOpen) {
        // Lazy-open if init() hasn't run yet
        if (!Hive.isBoxOpen(_vitalHistoryBoxName)) {
          _vitalHistoryBox =
              await Hive.openBox<VitalHistoryHiveModel>(_vitalHistoryBoxName);
        } else {
          _vitalHistoryBox =
              Hive.box<VitalHistoryHiveModel>(_vitalHistoryBoxName);
        }
      }

      // Add the new measurement (auto-incremented int key)
      await _vitalHistoryBox!.add(measurement);

      // Trim: keep only the latest _maxHistoryPointsPerType per type
      final allOfType = _vitalHistoryBox!.values
          .where((m) => m.vitalType == measurement.vitalType)
          .toList();

      if (allOfType.length > _maxHistoryPointsPerType) {
        // Sort ascending by timestamp
        allOfType.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // Delete the oldest entries beyond the limit
        final toRemove =
            allOfType.sublist(0, allOfType.length - _maxHistoryPointsPerType);
        for (final old in toRemove) {
          await old.delete(); // HiveObject.delete() removes from box
        }

        logger.debug(
          'PatientLocalDatasource: Trimmed ${toRemove.length} old '
          '${measurement.vitalType} measurements',
        );
      }
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error saving vital measurement',
        e,
        s,
      );
      // Don't rethrow — recording history is non-critical
    }
  }

  /// Get historical measurements for a specific vital type.
  /// Returns points sorted ascending by timestamp.
  /// Optional [since] parameter to filter by time range.
  Future<List<VitalHistoryHiveModel>> getVitalHistory(
    String vitalType, {
    DateTime? since,
  }) async {
    try {
      if (_vitalHistoryBox == null || !_vitalHistoryBox!.isOpen) {
        if (!Hive.isBoxOpen(_vitalHistoryBoxName)) {
          _vitalHistoryBox =
              await Hive.openBox<VitalHistoryHiveModel>(_vitalHistoryBoxName);
        } else {
          _vitalHistoryBox =
              Hive.box<VitalHistoryHiveModel>(_vitalHistoryBoxName);
        }
      }

      var results = _vitalHistoryBox!.values
          .where((m) => m.vitalType == vitalType)
          .toList();

      // Filter by time range if provided
      if (since != null) {
        results = results
            .where((m) => m.timestamp.isAfter(since))
            .toList();
      }

      // Sort ascending by timestamp
      results.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      logger.debug(
        'PatientLocalDatasource: Retrieved ${results.length} history points '
        'for $vitalType'
        '${since != null ? ' since $since' : ''}',
      );

      return results;
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error getting vital history',
        e,
        s,
      );
      return [];
    }
  }

  /// Clear all vital history data
  Future<void> clearVitalHistory() async {
    try {
      if (_vitalHistoryBox != null && _vitalHistoryBox!.isOpen) {
        await _vitalHistoryBox!.clear();
        logger.debug('PatientLocalDatasource: Cleared all vital history');
      }
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error clearing vital history',
        e,
        s,
      );
    }
  }

  // ============================================================
  // Health Record Methods
  // ============================================================

  /// Save a patient-reported health record
  Future<void> saveHealthRecord(HealthRecordHiveModel record) async {
    try {
      if (_healthRecordBox == null || !_healthRecordBox!.isOpen) {
        if (!Hive.isBoxOpen(_healthRecordBoxName)) {
          _healthRecordBox =
              await Hive.openBox<HealthRecordHiveModel>(_healthRecordBoxName);
        } else {
          _healthRecordBox =
              Hive.box<HealthRecordHiveModel>(_healthRecordBoxName);
        }
      }

      await _healthRecordBox!.put(record.id, record);
      logger.debug(
        'PatientLocalDatasource: Saved health record "${record.id}"',
      );
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error saving health record',
        e,
        s,
      );
      rethrow;
    }
  }

  /// Get all health records, sorted by timestamp descending (newest first)
  Future<List<HealthRecordHiveModel>> getHealthRecords() async {
    try {
      if (_healthRecordBox == null || !_healthRecordBox!.isOpen) {
        if (!Hive.isBoxOpen(_healthRecordBoxName)) {
          _healthRecordBox =
              await Hive.openBox<HealthRecordHiveModel>(_healthRecordBoxName);
        } else {
          _healthRecordBox =
              Hive.box<HealthRecordHiveModel>(_healthRecordBoxName);
        }
      }

      final records = _healthRecordBox!.values.toList();

      // Sort descending by timestamp (newest first)
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      logger.debug(
        'PatientLocalDatasource: Retrieved ${records.length} health records',
      );

      return records;
    } catch (e, s) {
      logger.error(
        'PatientLocalDatasource: Error getting health records',
        e,
        s,
      );
      return [];
    }
  }

  /// Ensure the tasks box is initialized
  void _ensureInitialized() {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
        'PatientLocalDatasource: Box not initialized. Call init() first.',
      );
    }
  }
}
