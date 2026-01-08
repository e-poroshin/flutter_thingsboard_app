import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_config.dart';

/// PATIENT APP: Medplum FHIR Remote Datasource
///
/// This datasource communicates with the NestJS BFF server, which proxies
/// requests to Medplum for FHIR clinical data.
///
/// **Architecture:**
/// - App calls NestJS endpoints (e.g., /api/patient/profile)
/// - NestJS handles Medplum authentication with server-side credentials
/// - NestJS transforms FHIR resources to simplified JSON for the app

abstract interface class IMedplumRemoteDatasource {
  /// Fetch patient's profile from NestJS (proxied from Medplum FHIR Patient)
  Future<Map<String, dynamic>> fetchPatientProfile();

  /// Fetch patient's health observations (proxied from Medplum FHIR Observation)
  Future<List<Map<String, dynamic>>> fetchPatientObservations();

  /// Fetch patient's conditions/diagnoses (proxied from Medplum FHIR Condition)
  Future<List<Map<String, dynamic>>> fetchPatientConditions();

  /// Fetch patient's medications (proxied from Medplum FHIR MedicationRequest)
  Future<List<Map<String, dynamic>>> fetchPatientMedications();
}

class MedplumRemoteDatasource implements IMedplumRemoteDatasource {
  const MedplumRemoteDatasource({
    required this.apiClient,
  });

  final NestApiClient apiClient;

  @override
  Future<Map<String, dynamic>> fetchPatientProfile() async {
    // GET /api/patient/profile
    // NestJS proxies to Medplum: GET /fhir/R4/Patient/{patientId}
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.patientProfile,
    );
    return response;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPatientObservations() async {
    // GET /api/patient/observations
    // NestJS proxies to Medplum: GET /fhir/R4/Observation?patient={patientId}
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.patientObservations,
    );

    // Handle response format: { "data": [...] } or just [...]
    if (response['data'] != null) {
      return (response['data'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPatientConditions() async {
    // GET /api/patient/conditions
    // NestJS proxies to Medplum: GET /fhir/R4/Condition?patient={patientId}
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.patientConditions,
    );

    if (response['data'] != null) {
      return (response['data'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPatientMedications() async {
    // GET /api/patient/medications
    // NestJS proxies to Medplum: GET /fhir/R4/MedicationRequest?patient={patientId}
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.patientMedications,
    );

    if (response['data'] != null) {
      return (response['data'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }
}
