import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_config.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/models.dart';

/// PATIENT APP: ThingsBoard Telemetry Datasource
///
/// This datasource communicates with the NestJS BFF server, which proxies
/// requests to ThingsBoard for IoT telemetry data.
///
/// **Architecture:**
/// - App calls NestJS endpoints (e.g., /thingsboard/device/{deviceId}/telemetry)
/// - NestJS handles ThingsBoard authentication with server-side credentials
/// - NestJS fetches telemetry from ThingsBoard and returns to app
///
/// **Token-Based Identity:** The backend decodes the JWT token to identify
/// the patient and resolve the appropriate device.

abstract interface class ITbTelemetryDatasource {
  /// Fetch latest telemetry values for a device
  /// Endpoint: GET /thingsboard/device/{deviceId}/telemetry/latest
  Future<ThingsboardTelemetryDTO> fetchLatestTelemetry(String deviceId);

  /// Fetch telemetry history for a device
  /// Endpoint: GET /thingsboard/device/{deviceId}/telemetry/history
  Future<TelemetryHistoryDTO> fetchTelemetryHistory(
    String deviceId, {
    required int startTs,
    required int endTs,
    List<String>? keys,
  });

  // ==========================================================================
  // Telemetry Sync (BLE → Backend)
  // ==========================================================================

  /// Push a BLE-collected measurement to the backend.
  /// Endpoint: POST /api/proxy/telemetry
  ///
  /// Used by the WAL flush logic in [PatientRepositoryImpl] and
  /// the [TelemetrySyncWorker] to upload sensor data.
  Future<void> pushTelemetry(TelemetryRequestDto dto);

  // ==========================================================================
  // Legacy Endpoints (for backwards compatibility / alternative API structure)
  // ==========================================================================

  /// Fetch latest vital signs from legacy endpoint
  /// Endpoint: GET /patient/vitals/latest
  Future<Map<String, dynamic>> fetchLatestVitals();

  /// Fetch vital signs history from legacy endpoint
  /// Endpoint: GET /patient/vitals/history
  Future<List<Map<String, dynamic>>> fetchVitalsHistory({
    required int startTs,
    required int endTs,
    List<String>? keys,
  });
}

class TbTelemetryDatasource implements ITbTelemetryDatasource {
  const TbTelemetryDatasource({
    required this.apiClient,
  });

  final NestApiClient apiClient;

  // ==========================================================================
  // Real API Implementation (explicit device ID — for future use)
  // ==========================================================================

  @override
  Future<ThingsboardTelemetryDTO> fetchLatestTelemetry(String deviceId) async {
    // GET /thingsboard/device/{deviceId}/telemetry/latest
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.thingsboardLatestTelemetry(deviceId),
    );
    return ThingsboardTelemetryDTO.fromJson(response);
  }

  @override
  Future<TelemetryHistoryDTO> fetchTelemetryHistory(
    String deviceId, {
    required int startTs,
    required int endTs,
    List<String>? keys,
  }) async {
    // GET /thingsboard/device/{deviceId}/telemetry/history
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.thingsboardTelemetryHistory(
        deviceId,
        startTs: startTs,
        endTs: endTs,
        keys: keys,
      ),
    );
    return TelemetryHistoryDTO.fromJson(response, deviceId: deviceId);
  }

  // ==========================================================================
  // Telemetry Sync (BLE → Backend)
  // ==========================================================================

  @override
  Future<void> pushTelemetry(TelemetryRequestDto dto) async {
    // POST /api/proxy/telemetry
    await apiClient.post<dynamic>(
      NestApiConfig.proxyTelemetry,
      data: dto.toJson(),
    );
  }

  // ==========================================================================
  // Legacy Endpoints (for backwards compatibility)
  // ==========================================================================

  @override
  Future<Map<String, dynamic>> fetchLatestVitals() async {
    // GET /patient/vitals/latest
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.patientVitalsLatest,
    );
    return response;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchVitalsHistory({
    required int startTs,
    required int endTs,
    List<String>? keys,
  }) async {
    // GET /patient/vitals/history?startTs=...&endTs=...&keys=...
    final response = await apiClient.get<dynamic>(
      NestApiConfig.patientVitalsHistory,
      queryParameters: {
        'startTs': startTs,
        'endTs': endTs,
        if (keys != null && keys.isNotEmpty) 'keys': keys.join(','),
      },
    );

    return _parseListResponse(response);
  }

  // ==========================================================================
  // Private Helpers
  // ==========================================================================

  List<Map<String, dynamic>> _parseListResponse(dynamic response) {
    if (response is List) {
      return response.cast<Map<String, dynamic>>();
    }

    if (response is Map<String, dynamic>) {
      if (response['data'] is List) {
        return (response['data'] as List).cast<Map<String, dynamic>>();
      }
      if (response['results'] is List) {
        return (response['results'] as List).cast<Map<String, dynamic>>();
      }
    }

    return [];
  }
}
