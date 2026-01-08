/// PATIENT APP: NestJS API Configuration
///
/// Configuration constants for the NestJS BFF server.
///
/// **How to Configure:**
/// 1. For development, change [devBaseUrl] to your local NestJS server
/// 2. For production, change [prodBaseUrl] to your production server
/// 3. Set [useProdEnvironment] to true for production builds
///
/// Alternatively, use environment variables:
/// ```
/// flutter run --dart-define=NEST_API_URL=https://your-server.com/api
/// ```

class NestApiConfig {
  NestApiConfig._();

  /// Development environment base URL
  /// Change this to your local NestJS server URL
  static const String devBaseUrl = 'http://localhost:3000/api';

  /// Production environment base URL
  /// Change this to your production NestJS server URL
  static const String prodBaseUrl = 'https://api.yourpatientapp.com/api';

  /// Set to true to use production environment
  static const bool useProdEnvironment = false;

  /// Get the current base URL based on environment
  static String get baseUrl {
    // Check for environment variable override first
    const envUrl = String.fromEnvironment('NEST_API_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    return useProdEnvironment ? prodBaseUrl : devBaseUrl;
  }

  // ============================================================
  // API Endpoints
  // ============================================================

  /// Authentication endpoints
  static const String authLogin = '/auth/login';
  static const String authRegister = '/auth/register';
  static const String authRefresh = '/auth/refresh';
  static const String authLogout = '/auth/logout';
  static const String authProfile = '/auth/profile';

  /// Patient endpoints
  static const String patientProfile = '/patient/profile';
  static const String patientVitalsLatest = '/patient/vitals/latest';
  static const String patientVitalsHistory = '/patient/vitals/history';
  static const String patientObservations = '/patient/observations';
  static const String patientConditions = '/patient/conditions';
  static const String patientMedications = '/patient/medications';

  /// Health data endpoints (proxied from ThingsBoard)
  static const String healthTelemetry = '/health/telemetry';
  static const String healthDevices = '/health/devices';

  /// FHIR endpoints (proxied from Medplum)
  static const String fhirPatient = '/fhir/patient';
  static const String fhirObservation = '/fhir/observation';
}

