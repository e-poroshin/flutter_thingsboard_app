import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/medplum_remote_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/nest_auth_remote_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/tb_telemetry_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/repositories/nest_auth_repository.dart';
import 'package:thingsboard_app/modules/patient_health/data/repositories/patient_repository_impl.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/login/patient_login_bloc.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/thingsboard_client.dart';

/// PATIENT APP: Dependency Injection for Patient Health Module
///
/// Sets up scoped DI using GetIt's pushNewScope pattern.
/// This ensures proper cleanup when the module is disposed.
///
/// **BFF Architecture:**
/// - All datasources use NestApiClient to communicate with NestJS server
/// - NestJS handles ThingsBoard/Medplum authentication server-side
/// - App only stores NestJS JWT tokens

class PatientHealthDi {
  PatientHealthDi._();

  /// Initialize the Patient Health module dependencies
  ///
  /// Creates a new DI scope and registers all module dependencies:
  /// - Datasources (NestJS BFF endpoints)
  /// - Repositories
  /// - BLoCs for state management
  static void init(
    String scopeName, {
    required ThingsboardClient tbClient,
    required TbLogger logger,
  }) {
    final apiClient = getIt<NestApiClient>();

    getIt.pushNewScope(
      scopeName: scopeName,
      init: (locator) {
        // Register NestJS Auth datasource
        locator.registerFactory<INestAuthRemoteDatasource>(
          () => NestAuthRemoteDatasource(
            apiClient: apiClient,
          ),
        );

        // Register NestJS Auth repository
        locator.registerFactory<INestAuthRepository>(
          () => NestAuthRepository(
            datasource: locator(),
            apiClient: apiClient,
            logger: logger,
          ),
        );

        // Register Medplum datasource (via NestJS BFF)
        locator.registerFactory<IMedplumRemoteDatasource>(
          () => MedplumRemoteDatasource(
            apiClient: apiClient,
          ),
        );

        // Register ThingsBoard telemetry datasource (via NestJS BFF)
        locator.registerFactory<ITbTelemetryDatasource>(
          () => TbTelemetryDatasource(
            apiClient: apiClient,
          ),
        );

        // Register Patient repository
        locator.registerFactory<IPatientRepository>(
          () => PatientRepositoryImpl(
            medplumDatasource: locator(),
            telemetryDatasource: locator(),
          ),
        );

        // Register Patient Login BLoC (singleton within this scope)
        locator.registerLazySingleton(
          () => PatientLoginBloc(
            authRepository: locator(),
            logger: logger,
          ),
        );

        // Register Patient Health BLoC (singleton within this scope)
        locator.registerLazySingleton(
          () => PatientBloc(
            repository: locator(),
            logger: logger,
          ),
        );
      },
    );
  }

  /// Dispose the Patient Health module dependencies
  ///
  /// Closes BLoCs and drops the DI scope to free resources.
  static void dispose(String scopeName) {
    // Close BLoCs before dropping the scope
    try {
      getIt<PatientBloc>().close();
    } catch (_) {}

    try {
      getIt<PatientLoginBloc>().close();
    } catch (_) {}

    // Drop the scope to cleanup all registered dependencies
    getIt.dropScope(scopeName);
  }
}
