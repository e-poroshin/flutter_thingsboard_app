import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_config.dart';

/// PATIENT APP: ThingsBoard Telemetry Datasource
///
/// This datasource communicates with the NestJS BFF server, which proxies
/// requests to ThingsBoard for IoT telemetry data.
///
/// **Architecture:**
/// - App calls NestJS endpoints (e.g., /api/patient/vitals/latest)
/// - NestJS handles ThingsBoard authentication with server-side credentials
/// - NestJS fetches telemetry from ThingsBoard and transforms to app format

abstract interface class ITbTelemetryDatasource {
  /// Fetch latest vital signs from NestJS (proxied from ThingsBoard telemetry)
  Future<Map<String, dynamic>> fetchLatestVitals();

  /// Fetch vital signs history for a date range
  Future<List<Map<String, dynamic>>> fetchVitalsHistory({
    required int startTs,
    required int endTs,
    List<String>? keys,
  });

  /// Fetch telemetry data for specific keys
  Future<Map<String, dynamic>> fetchTelemetry({
    required List<String> keys,
  });
}

class TbTelemetryDatasource implements ITbTelemetryDatasource {
  const TbTelemetryDatasource({
    required this.apiClient,
  });

  final NestApiClient apiClient;

  @override
  Future<Map<String, dynamic>> fetchLatestVitals() async {
    // GET /api/patient/vitals/latest
    // NestJS proxies to ThingsBoard:
    //   GET /api/plugins/telemetry/DEVICE/{deviceId}/values/timeseries?keys=...
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
    // GET /api/patient/vitals/history?startTs=...&endTs=...&keys=...
    // NestJS proxies to ThingsBoard:
    //   GET /api/plugins/telemetry/DEVICE/{deviceId}/values/timeseries
    //       ?startTs=...&endTs=...&keys=...
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.patientVitalsHistory,
      queryParameters: {
        'startTs': startTs,
        'endTs': endTs,
        if (keys != null && keys.isNotEmpty) 'keys': keys.join(','),
      },
    );

    if (response['data'] != null) {
      return (response['data'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> fetchTelemetry({
    required List<String> keys,
  }) async {
    // GET /api/health/telemetry?keys=...
    // NestJS proxies to ThingsBoard telemetry API
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.healthTelemetry,
      queryParameters: {
        'keys': keys.join(','),
      },
    );
    return response;
  }
}
