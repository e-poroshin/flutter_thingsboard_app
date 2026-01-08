import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/network/nest_api_exceptions.dart';
import 'package:thingsboard_app/modules/patient_health/data/repositories/nest_auth_repository.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/login/patient_login_event.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/login/patient_login_state.dart';

/// PATIENT APP: Patient Login BLoC
///
/// Handles authentication flow using the NestJS BFF server.
/// Bypasses the default ThingsBoard authentication.
///
/// **Flow:**
/// 1. User enters credentials
/// 2. Credentials sent to NestJS `/api/auth/login`
/// 3. NestJS validates and returns JWT
/// 4. JWT stored locally for subsequent API calls
/// 5. Navigate to main app

class PatientLoginBloc extends Bloc<PatientLoginEvent, PatientLoginState> {
  PatientLoginBloc({
    required this.authRepository,
    required this.logger,
  }) : super(const PatientLoginInitialState()) {
    on<PatientLoginSubmitEvent>(_onLoginSubmit);
    on<PatientRegisterSubmitEvent>(_onRegisterSubmit);
    on<PatientLogoutEvent>(_onLogout);
    on<PatientCheckAuthEvent>(_onCheckAuth);
    on<PatientLoginResetEvent>(_onReset);
  }

  final INestAuthRepository authRepository;
  final TbLogger logger;

  /// Handle login submission
  Future<void> _onLoginSubmit(
    PatientLoginSubmitEvent event,
    Emitter<PatientLoginState> emit,
  ) async {
    logger.debug('PatientLoginBloc: Login attempt for ${event.email}');
    emit(const PatientLoginLoadingState(message: 'Signing in...'));

    try {
      final response = await authRepository.login(
        event.email,
        event.password,
      );

      logger.debug('PatientLoginBloc: Login successful');
      emit(PatientLoginSuccessState(authResponse: response));
    } on NestAuthException catch (e) {
      logger.error('PatientLoginBloc: Auth error - ${e.message}');
      emit(PatientLoginErrorState(
        message: e.message,
        isValidationError: e.isValidationError,
        validationErrors: e.validationErrors,
      ));
    } on NestApiException catch (e) {
      logger.error('PatientLoginBloc: API error - ${e.message}');
      emit(PatientLoginErrorState(
        message: e.message,
        isValidationError: e.isValidationError,
        validationErrors: e.validationErrors,
      ));
    } catch (e, s) {
      logger.error('PatientLoginBloc: Unexpected error', e, s);
      emit(PatientLoginErrorState(
        message: 'An unexpected error occurred. Please try again.',
      ));
    }
  }

  /// Handle registration submission
  Future<void> _onRegisterSubmit(
    PatientRegisterSubmitEvent event,
    Emitter<PatientLoginState> emit,
  ) async {
    logger.debug('PatientLoginBloc: Registration attempt for ${event.email}');
    emit(const PatientLoginLoadingState(message: 'Creating account...'));

    try {
      final response = await authRepository.register(
        email: event.email,
        password: event.password,
        firstName: event.firstName,
        lastName: event.lastName,
      );

      logger.debug('PatientLoginBloc: Registration successful');
      emit(PatientLoginSuccessState(authResponse: response));
    } on NestApiException catch (e) {
      logger.error('PatientLoginBloc: Registration error - ${e.message}');
      emit(PatientLoginErrorState(
        message: e.message,
        isValidationError: e.isValidationError,
        validationErrors: e.validationErrors,
      ));
    } catch (e, s) {
      logger.error('PatientLoginBloc: Unexpected error', e, s);
      emit(PatientLoginErrorState(
        message: 'An unexpected error occurred. Please try again.',
      ));
    }
  }

  /// Handle logout
  Future<void> _onLogout(
    PatientLogoutEvent event,
    Emitter<PatientLoginState> emit,
  ) async {
    logger.debug('PatientLoginBloc: Logout requested');
    emit(const PatientLoginLoadingState(message: 'Signing out...'));

    try {
      await authRepository.logout();
      logger.debug('PatientLoginBloc: Logout successful');
      emit(const PatientLoginLoggedOutState());
    } catch (e, s) {
      logger.error('PatientLoginBloc: Logout error', e, s);
      // Still emit logged out state even if server call fails
      emit(const PatientLoginLoggedOutState());
    }
  }

  /// Check if user is already authenticated
  Future<void> _onCheckAuth(
    PatientCheckAuthEvent event,
    Emitter<PatientLoginState> emit,
  ) async {
    logger.debug('PatientLoginBloc: Checking authentication status');

    try {
      final isAuthenticated = await authRepository.isAuthenticated();

      if (isAuthenticated) {
        logger.debug('PatientLoginBloc: User is authenticated');
        emit(const PatientLoginAuthenticatedState());
      } else {
        logger.debug('PatientLoginBloc: User is not authenticated');
        emit(const PatientLoginInitialState());
      }
    } catch (e, s) {
      logger.error('PatientLoginBloc: Auth check error', e, s);
      emit(const PatientLoginInitialState());
    }
  }

  /// Reset to initial state (clear errors)
  void _onReset(
    PatientLoginResetEvent event,
    Emitter<PatientLoginState> emit,
  ) {
    emit(const PatientLoginInitialState());
  }
}

