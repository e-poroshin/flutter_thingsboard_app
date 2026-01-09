import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_config.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/models.dart';

/// PATIENT APP: Medplum FHIR Remote Datasource
///
/// This datasource communicates with the NestJS BFF server, which proxies
/// requests to Medplum for FHIR clinical data.
///
/// **Architecture:**
/// - App calls NestJS endpoints (e.g., /medplum/Patient/{id})
/// - NestJS handles Medplum authentication with server-side credentials
/// - NestJS returns FHIR resources
///
/// **Required ID:** medplumPatientId (obtained from GET /auth/profile)

abstract interface class IMedplumRemoteDatasource {
  /// Fetch patient record from Medplum
  /// Endpoint: GET /medplum/Patient/{patientId}
  Future<MedplumPatientDTO> fetchPatient(String patientId);

  /// Fetch patient's health observations
  /// Endpoint: GET /medplum/Observation?patient={patientId}
  Future<List<Map<String, dynamic>>> fetchObservations(String patientId);

  /// Fetch patient's conditions/diagnoses
  /// Endpoint: GET /medplum/Condition?patient={patientId}
  Future<List<Map<String, dynamic>>> fetchConditions(String patientId);

  /// Fetch patient's medications
  /// Endpoint: GET /medplum/MedicationRequest?patient={patientId}
  Future<List<Map<String, dynamic>>> fetchMedications(String patientId);

  // ==========================================================================
  // Legacy Endpoints (for backwards compatibility / alternative API structure)
  // ==========================================================================

  /// Fetch patient's profile from legacy endpoint
  /// Endpoint: GET /patient/profile
  Future<Map<String, dynamic>> fetchPatientProfile();

  /// Fetch patient's observations from legacy endpoint
  /// Endpoint: GET /patient/observations
  Future<List<Map<String, dynamic>>> fetchPatientObservations();
}

class MedplumRemoteDatasource implements IMedplumRemoteDatasource {
  const MedplumRemoteDatasource({
    required this.apiClient,
  });

  final NestApiClient apiClient;

  // ==========================================================================
  // Real API Implementation (using medplumPatientId)
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
  // Legacy Endpoints (for backwards compatibility)
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
