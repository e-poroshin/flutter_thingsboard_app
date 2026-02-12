import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/services/ble/ble_data_parser.dart';
import 'package:thingsboard_app/core/services/ble/ble_sensor_service.dart';
import 'package:thingsboard_app/core/services/notification/notification_service.dart';
import 'package:thingsboard_app/core/services/notification/task_notification_helper.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart'
    show IPatientRepository, PatientHealthSummary, VitalSign, VitalSignType;
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_event.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_state.dart';

/// PATIENT APP: Patient Health BLoC
/// 
/// Manages the state for the patient health dashboard.
/// Handles loading patient health data from both ThingsBoard and Medplum.

class PatientBloc extends Bloc<PatientEvent, PatientState> {
  PatientBloc({
    required this.repository,
    required this.logger,
  }) : super(const PatientInitialState()) {
    on<PatientLoadHealthSummaryEvent>(_onLoadHealthSummary);
    on<PatientRefreshEvent>(_onRefresh);
    on<PatientLoadVitalSignsEvent>(_onLoadVitalSigns);
    on<PatientLoadHistoryEvent>(_onLoadHistory);
    on<PatientLoadVitalHistoryEvent>(_onLoadVitalHistory);
    on<PatientLoadTasksEvent>(_onLoadTasks);
    on<PatientAddTaskEvent>(_onAddTask);
    on<PatientBleUpdateEvent>(_onBleUpdate);
    on<PatientConnectSensorEvent>(_onConnectSensor);
  }

  final IPatientRepository repository;
  final TbLogger logger;

  String? _currentPatientId;
  List<TaskEntity> _currentTasks = [];
  StreamSubscription<List<ScanResult>>? _bleSubscription;
  IBleSensorService? _bleService;

  /// Cached health summary that persists across state changes.
  /// BLE updates always apply to this cache so sensor data is never lost
  /// when the user navigates to detail pages (which change the bloc state).
  PatientHealthSummary? _cachedHealthSummary;

  Future<void> _onLoadHealthSummary(
    PatientLoadHealthSummaryEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug('PatientBloc: Loading health summary for ${event.patientId}');

    try {
      _currentPatientId = event.patientId;

      // If we have a cached health summary with BLE data, use it immediately
      // This preserves live sensor readings across page navigations
      if (_cachedHealthSummary != null) {
        logger.debug('PatientBloc: Restoring cached health summary (preserves BLE data)');
        emit(PatientHealthLoadedState(healthSummary: _cachedHealthSummary!));
        
        // Ensure BLE listener is running
        final sensorId = await repository.getSensorId();
        if (sensorId != null && _bleSubscription == null) {
          logger.debug('PatientBloc: Restarting BLE listener for sensor $sensorId');
          _startBleListener(sensorId).catchError((e, StackTrace s) {
            logger.warn('PatientBloc: Error starting BLE listener: $e', e, s);
          });
        }
        return;
      }

      // No cache — first load. Show loading indicator and fetch from repository.
      emit(const PatientLoadingState());
      
      // Step 1: Fetch initial data (Hive/Mock)
      final summary = await repository.getPatientHealthSummary(event.patientId);
      
      // Step 2: Cache and emit loaded state FIRST (critical: before starting BLE)
      _cachedHealthSummary = summary;
      emit(PatientHealthLoadedState(healthSummary: summary));
      
      // Step 3: Check for paired sensor and start BLE listener (non-blocking)
      final sensorId = await repository.getSensorId();
      if (sensorId != null) {
        logger.debug('PatientBloc: Sensor paired ($sensorId), starting BLE listener');
        // Start BLE listener asynchronously without blocking or awaiting
        _startBleListener(sensorId).catchError((e, StackTrace s) {
          logger.warn('PatientBloc: Error starting BLE listener: $e', e, s);
          // Don't emit error state - BLE is optional, UI should still work
        });
      }
    } catch (e, s) {
      logger.error('PatientBloc: Error loading health summary', e, s);
      emit(PatientErrorState(
        message: 'Failed to load health summary',
        exception: e,
      ));
    }
  }

  /// Start listening to BLE sensor data
  /// This is called asynchronously and should not block the main flow
  /// Uses events to update state instead of directly emitting
  Future<void> _startBleListener(String sensorId) async {
    try {
      // Get BLE service
      _bleService = getIt<IBleSensorService>();
      
      // Initialize if needed (with timeout to prevent hanging)
      try {
        await _bleService!.init().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('BLE initialization timed out');
          },
        );
      } catch (e) {
        logger.warn('PatientBloc: BLE service init failed, continuing without BLE: $e');
        return;
      }

      // Cancel existing subscription if any
      _bleSubscription?.cancel();
      
      // Start scanning and listening (non-blocking)
      _bleSubscription = _bleService!.scanForSensors().listen(
        (results) {
          // Safety guard: Don't add events if bloc is closed
          if (isClosed) {
            logger.debug('PatientBloc: Ignoring BLE data - bloc is closed');
            return;
          }

          // Find our paired sensor
          for (final result in results) {
            if (result.device.remoteId.toString() == sensorId) {
              // Parse temperature and humidity
              final temperature = BleDataParser.parseTemperature(result);
              final humidity = BleDataParser.parseHumidity(result);

              if (temperature != null) {
                logger.debug(
                  'PatientBloc: Received BLE data - Temp: $temperature°C, Humidity: ${humidity ?? 0}%',
                );
                
                // Safety guard: Check again before adding event
                if (!isClosed) {
                  // Dispatch event to update state (non-blocking, event-driven)
                  add(PatientBleUpdateEvent(
                    temperature: temperature,
                    humidity: humidity ?? 0.0,
                  ));
                }
              }
              break;
            }
          }
        },
        onError: (error) {
          logger.warn('PatientBloc: BLE scan error: $error');
        },
      );
    } catch (e, s) {
      logger.error('PatientBloc: Error starting BLE listener', e, s);
      // Don't rethrow - BLE is optional, UI should still work
    }
  }

  /// Handle BLE update event
  /// ALWAYS updates the cached health summary so sensor data is never lost.
  /// Only emits a new state when the Home page is active (PatientHealthLoadedState).
  /// When another page is active (e.g. chart detail), the cache is silently updated
  /// and will be restored when the user navigates back to Home.
  void _onBleUpdate(
    PatientBleUpdateEvent event,
    Emitter<PatientState> emit,
  ) {
    // Determine which summary to update: current state or cache
    final currentState = state;
    final summaryToUpdate = (currentState is PatientHealthLoadedState)
        ? currentState.healthSummary
        : _cachedHealthSummary;

    if (summaryToUpdate == null) {
      logger.debug('PatientBloc: Ignoring BLE update - no health summary available yet');
      return;
    }

    logger.debug(
      'PatientBloc: Updating vitals with BLE data - Temp: ${event.temperature}°C, Humidity: ${event.humidity}%',
    );

    // Update vitals in the health summary
    final updatedVitals = _updateVitalValue(
      summaryToUpdate.vitalSigns,
      event.temperature,
      event.humidity,
    );

    final updatedSummary = PatientHealthSummary(
      patientId: summaryToUpdate.patientId,
      patientName: summaryToUpdate.patientName,
      lastUpdated: DateTime.now(),
      vitalSigns: updatedVitals,
      recentObservations: summaryToUpdate.recentObservations,
    );

    // ALWAYS update the cache so BLE data is preserved across page navigations
    _cachedHealthSummary = updatedSummary;

    // Only emit to UI if the Home page is active (PatientHealthLoadedState)
    // When a detail page is active, the cache is updated silently
    if (currentState is PatientHealthLoadedState) {
      emit(PatientHealthLoadedState(healthSummary: updatedSummary));
    }

    // Persist measurements to local history (non-blocking, fire-and-forget)
    _persistBleData(event.temperature, event.humidity);
  }

  /// Persist BLE data to local Hive history for charts.
  /// Runs asynchronously — errors are logged but never propagate.
  void _persistBleData(double? temperature, double? humidity) {
    try {
      if (temperature != null) {
        repository.saveVitalMeasurement(
          vitalType: 'temperature',
          value: temperature,
          unit: '°C',
        );
      }
      if (humidity != null && humidity > 0) {
        repository.saveVitalMeasurement(
          vitalType: 'oxygenSaturation',
          value: humidity,
          unit: '%',
        );
      }
    } catch (e) {
      logger.warn('PatientBloc: Error persisting BLE data: $e');
    }
  }

  /// Handle connect sensor event
  /// Immediately starts listening to BLE data for the newly paired sensor
  Future<void> _onConnectSensor(
    PatientConnectSensorEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug('PatientBloc: Connect sensor event received');
    
    // Read the sensor ID from repository
    final sensorId = await repository.getSensorId();
    if (sensorId == null) {
      logger.debug('PatientBloc: No sensor ID found, skipping connection');
      return;
    }

    logger.debug('PatientBloc: Connecting to sensor: $sensorId');
    
    // Cancel existing subscription before starting a new one
    await _bleSubscription?.cancel();
    _bleSubscription = null;
    
    // Start BLE listener (non-blocking)
    _startBleListener(sensorId).catchError((e, StackTrace s) {
      logger.warn('PatientBloc: Error connecting to sensor: $e', e, s);
    });
  }

  /// Update vital values with BLE data
  List<VitalSign> _updateVitalValue(
    List<VitalSign> currentVitals,
    double? temperature,
    double? humidity,
  ) {
    final updatedVitals = <VitalSign>[];
    bool temperatureUpdated = false;
    bool humidityUpdated = false;

    // Update existing vitals or add new ones
    for (final vital in currentVitals) {
      if (vital.type == VitalSignType.temperature && temperature != null) {
        // Check if temperature is normal (36.1-37.2°C)
        final isNormal = temperature >= 36.1 && temperature <= 37.2;
        updatedVitals.add(VitalSign(
          type: vital.type,
          value: temperature,
          unit: vital.unit,
          timestamp: DateTime.now(),
          deviceId: 'ble-sensor', // Mark as live BLE data for icon display
          isNormal: isNormal,
        ));
        temperatureUpdated = true;
      } else if (vital.type == VitalSignType.oxygenSaturation && humidity != null) {
        // Map humidity to oxygen saturation for now (or create separate humidity vital)
        // Check if humidity/oxygen saturation is normal (95-100%)
        final isNormal = humidity >= 95 && humidity <= 100;
        updatedVitals.add(VitalSign(
          type: vital.type,
          value: humidity,
          unit: vital.unit,
          timestamp: DateTime.now(),
          deviceId: 'ble-sensor', // Mark as live BLE data
          isNormal: isNormal,
        ));
        humidityUpdated = true;
      } else {
        updatedVitals.add(vital);
      }
    }

    // Add temperature if it doesn't exist
    if (temperature != null && !temperatureUpdated) {
      final isNormal = temperature >= 36.1 && temperature <= 37.2;
      updatedVitals.add(VitalSign(
        type: VitalSignType.temperature,
        value: temperature,
        unit: '°C',
        timestamp: DateTime.now(),
        deviceId: 'ble-sensor', // Mark as BLE sensor for icon display
        isNormal: isNormal,
      ));
    }

    // Add humidity as oxygen saturation if it doesn't exist
    if (humidity != null && !humidityUpdated) {
      final isNormal = humidity >= 95 && humidity <= 100;
      updatedVitals.add(VitalSign(
        type: VitalSignType.oxygenSaturation,
        value: humidity,
        unit: '%',
        timestamp: DateTime.now(),
        isNormal: isNormal,
      ));
    }

    return updatedVitals;
  }

  @override
  Future<void> close() async {
    // Cancel BLE subscription before closing the bloc
    await _bleSubscription?.cancel();
    _bleSubscription = null;
    
    // Stop BLE scan if service is available
    try {
      _bleService?.stopScan();
    } catch (e) {
      // Ignore errors when stopping scan during disposal
    }
    
    return super.close();
  }

  Future<void> _onRefresh(
    PatientRefreshEvent event,
    Emitter<PatientState> emit,
  ) async {
    if (_currentPatientId == null) {
      logger.warn('PatientBloc: Cannot refresh - no patient ID set');
      return;
    }

    logger.debug('PatientBloc: Refreshing health data (clearing cache)');
    
    // Clear the cache so fresh data is fetched from repository
    _cachedHealthSummary = null;
    emit(const PatientLoadingState());

    try {
      // Fetch fresh data
      final summary = await repository.getPatientHealthSummary(
        _currentPatientId!,
      );
      
      // Cache and emit loaded state
      _cachedHealthSummary = summary;
      emit(PatientHealthLoadedState(healthSummary: summary));
      
      // Restart BLE listener if sensor is paired
      final sensorId = await repository.getSensorId();
      if (sensorId != null) {
        logger.debug('PatientBloc: Restarting BLE listener for sensor $sensorId');
        _startBleListener(sensorId).catchError((e, StackTrace s) {
          logger.warn('PatientBloc: Error restarting BLE listener: $e', e, s);
        });
      }
    } catch (e, s) {
      logger.error('PatientBloc: Error refreshing health data', e, s);
      emit(PatientErrorState(
        message: 'Failed to refresh health data',
        exception: e,
      ));
    }
  }

  Future<void> _onLoadVitalSigns(
    PatientLoadVitalSignsEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug('PatientBloc: Loading vital signs for ${event.patientId}');
    emit(const PatientLoadingState());

    try {
      final vitalSigns = await repository.getVitalSigns(event.patientId);
      emit(PatientVitalSignsLoadedState(vitalSigns: vitalSigns));
    } catch (e, s) {
      logger.error('PatientBloc: Error loading vital signs', e, s);
      emit(PatientErrorState(
        message: 'Failed to load vital signs',
        exception: e,
      ));
    }
  }

  Future<void> _onLoadHistory(
    PatientLoadHistoryEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug(
      'PatientBloc: Loading history for ${event.patientId} '
      'from ${event.startDate} to ${event.endDate}',
    );
    emit(const PatientLoadingState());

    try {
      final history = await repository.getHealthHistory(
        event.patientId,
        startDate: event.startDate,
        endDate: event.endDate,
      );
      emit(PatientHistoryLoadedState(history: history));
    } catch (e, s) {
      logger.error('PatientBloc: Error loading history', e, s);
      emit(PatientErrorState(
        message: 'Failed to load health history',
        exception: e,
      ));
    }
  }

  Future<void> _onLoadVitalHistory(
    PatientLoadVitalHistoryEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug(
      'PatientBloc: Loading vital history for ${event.vitalId} '
      'with range ${event.range}',
    );
    emit(const PatientLoadingState());

    try {
      final historyPoints = await repository.getVitalHistory(
        event.vitalId,
        event.range,
      );

      // Calculate current value (average of last few points or latest)
      double? currentValue;
      if (historyPoints.isNotEmpty) {
        final recentPoints = historyPoints.length > 5
            ? historyPoints.sublist(historyPoints.length - 5)
            : historyPoints;
        currentValue = recentPoints
            .map((p) => p.value)
            .reduce((a, b) => a + b) /
            recentPoints.length;
      }

      emit(PatientVitalHistoryLoadedState(
        vitalId: event.vitalId,
        range: event.range,
        historyPoints: historyPoints,
        currentValue: currentValue,
      ));
    } catch (e, s) {
      logger.error('PatientBloc: Error loading vital history', e, s);
      emit(PatientErrorState(
        message: 'Failed to load vital history',
        exception: e,
      ));
    }
  }

  Future<void> _onLoadTasks(
    PatientLoadTasksEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug('PatientBloc: Loading ${event.tasks.length} tasks');
    _currentTasks = List.from(event.tasks);
    emit(PatientTasksLoadedState(tasks: _currentTasks));
  }

  Future<void> _onAddTask(
    PatientAddTaskEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug('PatientBloc: Adding new task - ${event.task.title}');

    try {
      // Save task to repository (persists to local storage)
      try {
        await repository.addTask(event.task);
        logger.debug('PatientBloc: Task saved to repository');
      } catch (e, s) {
        logger.warn(
          'PatientBloc: Error saving task to repository (continuing anyway)',
          e,
          s,
        );
        // Continue even if save fails - task is still added to state
      }

      // Reload all tasks from repository to get the complete list
      // This ensures we have all tasks including the newly added one
      final allTasks = await repository.getDailyTasks();
      _currentTasks = allTasks;

      // Emit updated state with complete task list
      emit(PatientTasksLoadedState(tasks: allTasks));

      // Schedule notification for the new task
      try {
        final notificationService = getIt<INotificationService>();
        final notificationHelper = TaskNotificationHelper(
          notificationService: notificationService,
          logger: logger,
        );
        
        // Schedule notification for just this new task
        await notificationHelper.scheduleTaskNotifications([event.task]);
        
        logger.debug(
          'PatientBloc: Successfully scheduled notification for task - ${event.task.id}',
        );
      } catch (e, s) {
        // Log but don't fail the entire operation if notification scheduling fails
        logger.warn(
          'PatientBloc: Error scheduling notification for new task',
          e,
          s,
        );
      }
    } catch (e, s) {
      logger.error('PatientBloc: Error adding task', e, s);
      emit(PatientErrorState(
        message: 'Failed to add task',
        exception: e,
      ));
    }
  }
}

