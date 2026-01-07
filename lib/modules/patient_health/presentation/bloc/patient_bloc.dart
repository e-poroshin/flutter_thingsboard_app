import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
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
  }

  final IPatientRepository repository;
  final TbLogger logger;

  String? _currentPatientId;

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
}

