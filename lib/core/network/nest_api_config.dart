/// PATIENT APP: NestJS API Configuration
///
/// Configuration constants for the NestJS BFF server.
///
/// **Backend Configuration:**
/// - Base URL: http://167.172.178.76:30003
/// - Architecture: BFF (Backend for Frontend)
/// - We do NOT connect to ThingsBoard or Medplum directly
///
/// **How to Override:**
/// ```
/// flutter run --dart-define=NEST_API_URL=http://your-server.com
/// ```

class NestApiConfig {
  NestApiConfig._();

  /// Development/Staging environment base URL
  /// Official NestJS BFF server
  static const String devBaseUrl = 'http://167.172.178.76:30003';

  /// Production environment base URL
  /// TODO: Update when production server is ready
  static const String prodBaseUrl = 'http://167.172.178.76:30003';

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
  // Authentication Endpoints
  // ============================================================

  /// POST /auth/login - Authenticate user
  /// Body: { "email": "...", "password": "..." }
  /// Response: { "accessToken": "..." }
  static const String authLogin = '/auth/login';

  /// POST /auth/register - Register new user
  static const String authRegister = '/auth/register';

  /// POST /auth/refresh - Refresh access token
  static const String authRefresh = '/auth/refresh';

  /// POST /auth/logout - Logout user
  static const String authLogout = '/auth/logout';

  /// GET /auth/profile - Get current user profile
  /// Returns: userId, medplumPatientId, thingsboardDeviceId
  static const String authProfile = '/auth/profile';

  // ============================================================
  // User Endpoints
  // ============================================================

  /// GET /users/me - Alternative profile endpoint
  static const String usersMe = '/users/me';

  // ============================================================
  // Medplum (FHIR) Endpoints - Proxied through NestJS
  // ============================================================

  /// GET /medplum/Patient/{id} - Get patient record from Medplum
  static String medplumPatient(String patientId) => '/medplum/Patient/$patientId';

  /// GET /medplum/Observation - Get observations for patient
  static String medplumObservations(String patientId) =>
      '/medplum/Observation?patient=$patientId';

  /// GET /medplum/Condition - Get conditions for patient
  static String medplumConditions(String patientId) =>
      '/medplum/Condition?patient=$patientId';

  /// GET /medplum/MedicationRequest - Get medications for patient
  static String medplumMedications(String patientId) =>
      '/medplum/MedicationRequest?patient=$patientId';

  // ============================================================
  // ThingsBoard Endpoints - Proxied through NestJS
  // ============================================================

  /// GET /thingsboard/device/{deviceId}/telemetry - Get latest telemetry
  static String thingsboardTelemetry(String deviceId) =>
      '/thingsboard/device/$deviceId/telemetry';

  /// GET /thingsboard/device/{deviceId}/telemetry/latest - Get latest values
  static String thingsboardLatestTelemetry(String deviceId) =>
      '/thingsboard/device/$deviceId/telemetry/latest';

  /// GET /thingsboard/device/{deviceId}/telemetry/history - Get historical data
  static String thingsboardTelemetryHistory(
    String deviceId, {
    int? startTs,
    int? endTs,
    List<String>? keys,
  }) {
    final params = <String>[];
    if (startTs != null) params.add('startTs=$startTs');
    if (endTs != null) params.add('endTs=$endTs');
    if (keys != null && keys.isNotEmpty) params.add('keys=${keys.join(",")}');

    final queryString = params.isNotEmpty ? '?${params.join("&")}' : '';
    return '/thingsboard/device/$deviceId/telemetry/history$queryString';
  }

  // ============================================================
  // Legacy Endpoints (for backwards compatibility)
  // ============================================================

  static const String patientProfile = '/patient/profile';
  static const String patientVitalsLatest = '/patient/vitals/latest';
  static const String patientVitalsHistory = '/patient/vitals/history';
  static const String patientObservations = '/patient/observations';
  static const String patientConditions = '/patient/conditions';
  static const String patientMedications = '/patient/medications';
}

