import 'package:thingsboard_app/modules/patient_health/data/models/vital_history_hive_model.dart';

/// PATIENT APP: Telemetry Request DTO (Data Layer — Outbound)
///
/// Data Transfer Object for `POST /api/proxy/telemetry`.
///
/// Sends BLE sensor measurements to the SmartBean Proxy,
/// which forwards them to ThingsBoard as device telemetry.
///
/// **Token-Based Identity:**
/// The backend decodes the JWT token to identify the patient.
/// `deviceId` and `tenantId` are optional — the backend can
/// resolve the device from the token. Once the
/// `GET /patient/{id}/devices` endpoint is available, the client
/// can fetch the device list and populate these fields.
///
/// **Swagger contract:**
/// ```json
/// {
///   "deviceId": "..." (optional — backend resolves from token),
///   "tenantId": "..." (optional — backend resolves from token),
///   "timestamp": "2026-02-18T10:30:00.000Z",
///   "data": { "temperature": 36.6 }
/// }
/// ```
class TelemetryRequestDto {
  const TelemetryRequestDto({
    this.deviceId,
    this.tenantId,
    required this.timestamp,
    required this.data,
  });

  /// ThingsBoard Device ID (optional — backend may resolve from token)
  ///
  /// TODO: Fetch from GET /patient/{id}/devices when available.
  final String? deviceId;

  /// ThingsBoard Tenant ID (optional — backend may resolve from token)
  final String? tenantId;

  /// ISO 8601 UTC timestamp of the measurement
  /// Example: `"2026-02-18T10:30:00.000Z"`
  final String timestamp;

  /// Key-value map of telemetry data points.
  ///
  /// Keys MUST match ThingsBoard telemetry key naming:
  /// - `"temperature"` (not `"temp"`)
  /// - `"humidity"`
  /// - `"heartRate"` (camelCase)
  /// - `"oxygenSaturation"`
  ///
  /// Values are numeric (double or int).
  final Map<String, dynamic> data;

  // ============================================================
  // Serialization
  // ============================================================

  /// Serialize to JSON for the POST request body.
  /// Only includes `deviceId` and `tenantId` if they are non-null.
  Map<String, dynamic> toJson() => {
        if (deviceId != null) 'deviceId': deviceId,
        if (tenantId != null) 'tenantId': tenantId,
        'timestamp': timestamp,
        'data': data,
      };

  /// Deserialize from JSON (e.g. for unit tests or echo responses).
  factory TelemetryRequestDto.fromJson(Map<String, dynamic> json) {
    return TelemetryRequestDto(
      deviceId: json['deviceId'] as String?,
      tenantId: json['tenantId'] as String?,
      timestamp: json['timestamp'] as String? ?? '',
      data: (json['data'] as Map<String, dynamic>?) ?? {},
    );
  }

  // ============================================================
  // Factories — Local → Network Mapping
  // ============================================================

  /// Create from a locally-stored [VitalHistoryHiveModel].
  ///
  /// This is the **heart of the Write-Ahead Log flush**:
  /// every dirty Hive record is converted to this DTO and POSTed.
  ///
  /// The vital type key is normalised via [_normalizeVitalKey] so
  /// that Hive keys like `"temp"` become `"temperature"` for
  /// ThingsBoard.
  factory TelemetryRequestDto.fromHiveModel({
    required VitalHistoryHiveModel model,
    String? deviceId,
    String? tenantId,
  }) {
    return TelemetryRequestDto(
      deviceId: deviceId,
      tenantId: tenantId,
      timestamp: model.timestamp.toUtc().toIso8601String(),
      data: {
        _normalizeVitalKey(model.vitalType): model.value,
      },
    );
  }

  /// Create from a live BLE sensor reading (real-time push).
  ///
  /// Used for the optimistic-send path in `_persistBleData` —
  /// we attempt to push immediately without waiting for the
  /// sync worker.
  factory TelemetryRequestDto.fromBleReading({
    required double temperature,
    required double humidity,
    String? deviceId,
    String? tenantId,
    DateTime? timestamp,
  }) {
    final ts = (timestamp ?? DateTime.now()).toUtc();
    return TelemetryRequestDto(
      deviceId: deviceId,
      tenantId: tenantId,
      timestamp: ts.toIso8601String(),
      data: {
        'temperature': temperature,
        if (humidity > 0) 'humidity': humidity,
      },
    );
  }

  /// Create a batch-ready list of DTOs from multiple Hive models.
  ///
  /// Useful if the backend supports array payloads in the future.
  static List<TelemetryRequestDto> fromHiveModels({
    required List<VitalHistoryHiveModel> models,
    String? deviceId,
    String? tenantId,
  }) {
    return models
        .map((model) => TelemetryRequestDto.fromHiveModel(
              model: model,
              deviceId: deviceId,
              tenantId: tenantId,
            ))
        .toList();
  }

  // ============================================================
  // Helpers
  // ============================================================

  /// Normalise Hive / BLE vital-type keys to ThingsBoard telemetry
  /// key names.
  ///
  /// ThingsBoard expects **camelCase** keys. The BLE parser and
  /// Hive layer may use abbreviations or snake_case.
  ///
  /// Mapping table:
  /// | Input (local)         | Output (ThingsBoard)  |
  /// |-----------------------|-----------------------|
  /// | `temp`, `body_temp`   | `temperature`         |
  /// | `spo2`, `oxygen`      | `oxygenSaturation`    |
  /// | `hr`, `heart_rate`    | `heartRate`           |
  /// | `rr`, `respiratory_rate` | `respiratoryRate`  |
  /// | `bp`, `blood_pressure`| `bloodPressure`       |
  /// | `bg`, `glucose`       | `bloodGlucose`        |
  /// | `body_weight`         | `weight`              |
  static String _normalizeVitalKey(String vitalType) {
    return switch (vitalType.toLowerCase()) {
      'temperature' || 'temp' || 'body_temp' => 'temperature',
      'humidity' => 'humidity',
      'oxygensaturation' || 'spo2' || 'oxygen' => 'oxygenSaturation',
      'heartrate' || 'heart_rate' || 'hr' || 'pulse' => 'heartRate',
      'respiratoryrate' || 'respiratory_rate' || 'rr' => 'respiratoryRate',
      'bloodpressure' || 'blood_pressure' || 'bp' => 'bloodPressure',
      'bloodglucose' || 'blood_glucose' || 'glucose' || 'bg' =>
        'bloodGlucose',
      'weight' || 'body_weight' => 'weight',
      _ => vitalType, // pass-through for unknown keys
    };
  }

  /// Expose the normaliser for use in mappers / tests.
  static String normalizeVitalKey(String vitalType) =>
      _normalizeVitalKey(vitalType);

  // ============================================================
  // Object overrides
  // ============================================================

  @override
  String toString() =>
      'TelemetryRequestDto(device: $deviceId, ts: $timestamp, data: $data)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelemetryRequestDto &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          tenantId == other.tenantId &&
          timestamp == other.timestamp &&
          _mapEquals(data, other.data);

  @override
  int get hashCode =>
      deviceId.hashCode ^
      tenantId.hashCode ^
      timestamp.hashCode ^
      data.hashCode;

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
