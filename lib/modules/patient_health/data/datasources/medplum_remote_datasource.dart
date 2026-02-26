import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_config.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/models.dart';

/// PATIENT APP: Medplum FHIR Remote Datasource
///
/// This datasource communicates with the NestJS BFF server, which proxies
/// requests to Medplum for FHIR clinical data.
///
/// **Architecture:**
/// - App calls NestJS endpoints (e.g., /patient/profile, /patient/observations)
/// - NestJS decodes the JWT token to identify the patient
/// - NestJS handles Medplum authentication with server-side credentials
/// - NestJS returns FHIR resources
///
/// **Token-based identity:** The mobile client does NOT need to provide
/// `medplumPatientId` — the backend resolves it from the JWT token.

abstract interface class IMedplumRemoteDatasource {
  /// Fetch patient record from Medplum (by explicit ID)
  /// Endpoint: GET /medplum/Patient/{patientId}
  Future<MedplumPatientDTO> fetchPatient(String patientId);

  /// Fetch patient's health observations (by explicit ID)
  /// Endpoint: GET /medplum/Observation?patient={patientId}
  Future<List<Map<String, dynamic>>> fetchObservations(String patientId);

  /// Fetch patient's observations filtered by LOINC/SNOMED code.
  ///
  /// Endpoint: GET /medplum/Observation?code={code}
  /// Backend resolves the patient from the JWT token.
  ///
  /// Supports optional date range filtering using FHIR `date` search
  /// parameters (`ge` = greater-or-equal, `le` = less-or-equal).
  ///
  /// Returns parsed [VitalObservationDto] objects ready for the UI.
  Future<List<VitalObservationDto>> fetchObservationsByCode({
    required String code,
    DateTime? from,
    DateTime? to,
  });

  /// Fetch patient's conditions/diagnoses (by explicit ID)
  /// Endpoint: GET /medplum/Condition?patient={patientId}
  Future<List<Map<String, dynamic>>> fetchConditions(String patientId);

  /// Fetch patient's medications (by explicit ID)
  /// Endpoint: GET /medplum/MedicationRequest?patient={patientId}
  Future<List<Map<String, dynamic>>> fetchMedications(String patientId);

  // ==========================================================================
  // Token-Authenticated Endpoints (backend resolves patient from JWT)
  // ==========================================================================

  /// Fetch patient's profile (token-based)
  /// Endpoint: GET /patient/profile
  Future<Map<String, dynamic>> fetchPatientProfile();

  /// Fetch patient's observations (token-based)
  /// Endpoint: GET /patient/observations
  Future<List<Map<String, dynamic>>> fetchPatientObservations();

  /// Fetch patient's conditions (token-based)
  /// Endpoint: GET /patient/conditions
  Future<List<Map<String, dynamic>>> fetchPatientConditions();

  /// Fetch patient's medications (token-based)
  /// Endpoint: GET /patient/medications
  Future<List<Map<String, dynamic>>> fetchPatientMedications();
}

class MedplumRemoteDatasource implements IMedplumRemoteDatasource {
  const MedplumRemoteDatasource({
    required this.apiClient,
  });

  final NestApiClient apiClient;

  // ==========================================================================
  // Explicit-ID API Implementation (kept for backwards compatibility)
  // ==========================================================================

  @override
  Future<MedplumPatientDTO> fetchPatient(String patientId) async {
    // GET /medplum/Patient/{patientId}
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.medplumPatient(patientId),
    );
    return MedplumPatientDTO.fromJson(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchObservations(String patientId) async {
    // GET /medplum/Observation?patient={patientId}
    final response = await apiClient.get<dynamic>(
      NestApiConfig.medplumObservations(patientId),
    );
    return _parseListResponse(response);
  }

  @override
  Future<List<VitalObservationDto>> fetchObservationsByCode({
    required String code,
    DateTime? from,
    DateTime? to,
  }) async {
    // GET /medplum/Observation?code={code}&date=ge{from}&date=le{to}
    //
    // Backend resolves the patient from the JWT token — no need to
    // pass `patient` as a query parameter.
    //
    // FHIR date search uses prefixes: ge (>=), le (<=), gt (>), lt (<).
    // Multiple `date` params are AND-ed by the server.
    final queryParams = <String, dynamic>{
      'code': code,
      if (from != null) 'date': [
        'ge${from.toUtc().toIso8601String()}',
        if (to != null) 'le${to.toUtc().toIso8601String()}',
      ] else if (to != null)
        'date': 'le${to.toUtc().toIso8601String()}',
      // Sort newest-first; _count limits the payload
      '_sort': '-date',
      '_count': '200',
    };

    final response = await apiClient.get<dynamic>(
      NestApiConfig.medplumObservation,
      queryParameters: queryParams,
    );

    return VitalObservationDto.fromJsonList(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchConditions(String patientId) async {
    // GET /medplum/Condition?patient={patientId}
    final response = await apiClient.get<dynamic>(
      NestApiConfig.medplumConditions(patientId),
    );
    return _parseListResponse(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMedications(String patientId) async {
    // GET /medplum/MedicationRequest?patient={patientId}
    final response = await apiClient.get<dynamic>(
      NestApiConfig.medplumMedications(patientId),
    );
    return _parseListResponse(response);
  }

  // ==========================================================================
  // Token-Authenticated Endpoints (backend resolves patient from JWT)
  // ==========================================================================

  @override
  Future<Map<String, dynamic>> fetchPatientProfile() async {
    // GET /patient/profile
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.patientProfile,
    );
    return response;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPatientObservations() async {
    // GET /patient/observations
    final response = await apiClient.get<dynamic>(
      NestApiConfig.patientObservations,
    );
    return _parseListResponse(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPatientConditions() async {
    // GET /patient/conditions
    final response = await apiClient.get<dynamic>(
      NestApiConfig.patientConditions,
    );
    return _parseListResponse(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPatientMedications() async {
    // GET /patient/medications
    final response = await apiClient.get<dynamic>(
      NestApiConfig.patientMedications,
    );
    return _parseListResponse(response);
  }

  // ==========================================================================
  // Private Helpers
  // ==========================================================================

  /// Parse response that could be:
  /// - Direct array: [...]
  /// - FHIR Bundle: { "entry": [{ "resource": {...} }, ...] }
  /// - Wrapped array: { "data": [...] }
  List<Map<String, dynamic>> _parseListResponse(dynamic response) {
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }

    if (response is Map<String, dynamic>) {
      // Check for FHIR Bundle format
      if (response['entry'] is List) {
        return (response['entry'] as List)
            .map((e) => (e['resource'] ?? e) as Map<String, dynamic>)
            .toList();
      }

      // Check for wrapped data format
      if (response['data'] is List) {
        return (response['data'] as List).cast<Map<String, dynamic>>();
      }

      // Check for results format
      if (response['results'] is List) {
        return (response['results'] as List).cast<Map<String, dynamic>>();
      }
    }

    return [];
  }
}
