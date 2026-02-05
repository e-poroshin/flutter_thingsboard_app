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
  }

  final IPatientRepository repository;
  final TbLogger logger;

  String? _currentPatientId;
  List<TaskEntity> _currentTasks = [];
  StreamSubscription<List<ScanResult>>? _bleSubscription;
  IBleSensorService? _bleService;

  Future<void> _onLoadHealthSummary(
    PatientLoadHealthSummaryEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug('PatientBloc: Loading health summary for ${event.patientId}');
    emit(const PatientLoadingState());

    try {
      _currentPatientId = event.patientId;
      final summary = await repository.getPatientHealthSummary(event.patientId);
      
      // Check if a sensor is paired and start listening to BLE data
      final sensorId = await repository.getSensorId();
      if (sensorId != null) {
        logger.debug('PatientBloc: Sensor paired ($sensorId), starting BLE listener');
        await _startBleListener(sensorId, emit);
      }
      
      emit(PatientHealthLoadedState(healthSummary: summary));
    } catch (e, s) {
      logger.error('PatientBloc: Error loading health summary', e, s);
      emit(PatientErrorState(
        message: 'Failed to load health summary',
        exception: e,
      ));
    }
  }

  /// Start listening to BLE sensor data
  Future<void> _startBleListener(
    String sensorId,
    Emitter<PatientState> emit,
  ) async {
    try {
      // Get BLE service
      _bleService = getIt<IBleSensorService>();
      
      // Initialize if needed
      try {
        await _bleService!.init();
      } catch (e) {
        logger.warn('PatientBloc: BLE service init failed, continuing without BLE: $e');
        return;
      }

      // Start scanning and listening
      _bleSubscription?.cancel();
      _bleSubscription = _bleService!.scanForSensors().listen(
        (results) {
          // Find our paired sensor
          for (final result in results) {
            if (result.device.remoteId.toString() == sensorId) {
              // Parse temperature and humidity
              final temperature = BleDataParser.parseTemperature(result);
              final humidity = BleDataParser.parseHumidity(result);

              if (temperature != null || humidity != null) {
                logger.debug(
                  'PatientBloc: Received BLE data - Temp: $temperature°C, Humidity: $humidity%',
                );
                
                // Update current state with real BLE data
                _updateStateWithBleData(emit, temperature, humidity);
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
    }
  }

  /// Update current state with BLE sensor data
  void _updateStateWithBleData(
    Emitter<PatientState> emit,
    double? temperature,
    double? humidity,
  ) {
    final currentState = state;
    
    if (currentState is PatientHealthLoadedState) {
      // Update vitals in the health summary
      final updatedVitals = _updateVitalValue(
        currentState.healthSummary.vitalSigns,
        temperature,
        humidity,
      );

      final updatedSummary = PatientHealthSummary(
        patientId: currentState.healthSummary.patientId,
        patientName: currentState.healthSummary.patientName,
        lastUpdated: DateTime.now(),
        vitalSigns: updatedVitals,
        recentObservations: currentState.healthSummary.recentObservations,
      );

      emit(PatientHealthLoadedState(healthSummary: updatedSummary));
    }
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
          deviceId: vital.deviceId,
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
          deviceId: vital.deviceId,
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
  Future<void> close() {
    _bleSubscription?.cancel();
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

    logger.debug('PatientBloc: Refreshing health data');
    emit(const PatientLoadingState());

    try {
      final summary = await repository.getPatientHealthSummary(
        _currentPatientId!,
      );
      emit(PatientHealthLoadedState(healthSummary: summary));
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

