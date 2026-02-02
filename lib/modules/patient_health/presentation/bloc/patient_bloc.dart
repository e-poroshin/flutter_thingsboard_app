import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/services/notification/notification_service.dart';
import 'package:thingsboard_app/core/services/notification/task_notification_helper.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
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

  Future<void> _onLoadHealthSummary(
    PatientLoadHealthSummaryEvent event,
    Emitter<PatientState> emit,
  ) async {
    logger.debug('PatientBloc: Loading health summary for ${event.patientId}');
    emit(const PatientLoadingState());

    try {
      _currentPatientId = event.patientId;
      final summary = await repository.getPatientHealthSummary(event.patientId);
      emit(PatientHealthLoadedState(healthSummary: summary));
    } catch (e, s) {
      logger.error('PatientBloc: Error loading health summary', e, s);
      emit(PatientErrorState(
        message: 'Failed to load health summary',
        exception: e,
      ));
    }
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

