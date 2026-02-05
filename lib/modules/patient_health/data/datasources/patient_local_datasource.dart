import 'package:hive_flutter/hive_flutter.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/task_hive_model.dart';

/// PATIENT APP: Patient Local Datasource
///
/// Handles local persistence of tasks using Hive.
/// Provides CRUD operations for tasks stored locally on the device.

class PatientLocalDatasource {
  PatientLocalDatasource({
    required this.logger,
  });

  final TbLogger logger;
  static const String _boxName = 'tasks_box';
  Box<TaskHiveModel>? _box;

  /// Initialize Hive box for tasks
  /// Must be called before any other operations
  Future<void> init() async {
    try {
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
      _ensureInitialized();
      // Use a settings box or store in the existing box with a special key
      // For simplicity, we'll use a separate settings box
      if (!Hive.isBoxOpen('settings_box')) {
        await Hive.openBox('settings_box');
      }
      final settingsBox = Hive.box('settings_box');
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
  /// Returns the stored BLE device remote ID, or null if not set
  String? getPairedSensorId() {
    try {
      if (!Hive.isBoxOpen('settings_box')) {
        return null;
      }
      final settingsBox = Hive.box('settings_box');
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

  /// Ensure the box is initialized
  void _ensureInitialized() {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
        'PatientLocalDatasource: Box not initialized. Call init() first.',
      );
    }
  }
}
