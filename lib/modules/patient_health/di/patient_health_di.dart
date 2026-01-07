import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/medplum_remote_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/tb_telemetry_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/repositories/patient_repository_impl.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/thingsboard_client.dart';

/// PATIENT APP: Dependency Injection for Patient Health Module
/// 
/// Sets up scoped DI using GetIt's pushNewScope pattern.
/// This ensures proper cleanup when the module is disposed.

class PatientHealthDi {
  PatientHealthDi._();

  /// Initialize the Patient Health module dependencies
  /// 
  /// Creates a new DI scope and registers all module dependencies:
  /// - Datasources (Medplum FHIR, ThingsBoard Telemetry)
  /// - Repository implementation
  /// - BLoC for state management
  static void init(
    String scopeName, {
    required ThingsboardClient tbClient,
    required TbLogger logger,
    String? medplumBaseUrl,
    String? medplumAccessToken,
  }) {
    getIt.pushNewScope(
      scopeName: scopeName,
      init: (locator) {
        // Register Medplum FHIR datasource
        locator.registerFactory<IMedplumRemoteDatasource>(
          () => MedplumRemoteDatasource(
            baseUrl: medplumBaseUrl ?? 'https://api.medplum.com/fhir/R4',
            accessToken: medplumAccessToken,
          ),
        );

        // Register ThingsBoard telemetry datasource
        locator.registerFactory<ITbTelemetryDatasource>(
          () => TbTelemetryDatasource(
            thingsboardClient: tbClient,
          ),
        );

        // Register Patient repository
        locator.registerFactory<IPatientRepository>(
          () => PatientRepositoryImpl(
            medplumDatasource: locator(),
            telemetryDatasource: locator(),
          ),
        );

        // Register Patient BLoC (singleton within this scope)
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
  /// Closes the BLoC and drops the DI scope to free resources.
  static void dispose(String scopeName) {
    // Close the BLoC before dropping the scope
    getIt<PatientBloc>().close();
    
    // Drop the scope to cleanup all registered dependencies
    getIt.dropScope(scopeName);
  }
}

