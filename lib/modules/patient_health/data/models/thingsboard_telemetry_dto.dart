/// PATIENT APP: ThingsBoard Telemetry DTO
///
/// Data Transfer Object for telemetry data from ThingsBoard.
/// Endpoint: GET /thingsboard/device/{deviceId}/telemetry

class ThingsboardTelemetryDTO {
  const ThingsboardTelemetryDTO({
    required this.data,
    this.deviceId,
    this.timestamp,
  });

  /// Telemetry data as key-value pairs
  /// Keys are telemetry keys (e.g., "heartRate", "temperature")
  /// Values can be numbers, strings, or lists of timestamped values
  final Map<String, dynamic> data;

  /// Device ID that this telemetry belongs to
  final String? deviceId;

  /// Timestamp of the response
  final DateTime? timestamp;

  /// Get all telemetry keys
  List<String> get keys => data.keys.toList();

  /// Get latest value for a key
  TelemetryValue? getLatestValue(String key) {
    final value = data[key];
    if (value == null) return null;

    if (value is List && value.isNotEmpty) {
      // ThingsBoard format: [{"ts": 1234567890, "value": 72}]
      final latest = value.last as Map<String, dynamic>;
      return TelemetryValue.fromJson(key, latest);
    } else if (value is Map) {
      // Single value format: {"ts": 1234567890, "value": 72}
      return TelemetryValue.fromJson(key, value as Map<String, dynamic>);
    } else {
      // Direct value
      return TelemetryValue(
        key: key,
        value: value,
        timestamp: DateTime.now(),
      );
    }
  }

  /// Get all latest values
  List<TelemetryValue> getAllLatestValues() {
    return keys.map((key) => getLatestValue(key)).whereType<TelemetryValue>().toList();
  }

  /// Parse from JSON response
  /// TODO: Verify field names with actual API response
  factory ThingsboardTelemetryDTO.fromJson(Map<String, dynamic> json) {
    // Check if response has a wrapper object
    final Map<String, dynamic> telemetryData;

    if (json.containsKey('data')) {
      telemetryData = json['data'] as Map<String, dynamic>? ?? {};
    } else if (json.containsKey('telemetry')) {
      telemetryData = json['telemetry'] as Map<String, dynamic>? ?? {};
    } else {
      // Assume the entire response is telemetry data
      telemetryData = Map<String, dynamic>.from(json);
    }

    return ThingsboardTelemetryDTO(
      data: telemetryData,
      deviceId: json['deviceId'] as String? ?? json['device_id'] as String?,
      timestamp: _parseTimestamp(json['timestamp'] ?? json['ts']),
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Single telemetry value with timestamp
class TelemetryValue {
  const TelemetryValue({
    required this.key,
    required this.value,
    required this.timestamp,
  });

  /// Telemetry key name
  final String key;

  /// The value (can be number, string, boolean)
  final dynamic value;

  /// When this value was recorded
  final DateTime timestamp;

  /// Get numeric value
  double? get numericValue {
    if (value is num) return (value as num).toDouble();
    if (value is String) return double.tryParse(value as String);
    return null;
  }

  /// Get string value
  String get stringValue => value?.toString() ?? '';

  /// Get boolean value
  bool? get boolValue {
    if (value is bool) return value as bool;
    if (value is String) {
      return (value as String).toLowerCase() == 'true';
    }
    if (value is num) return (value as num) != 0;
    return null;
  }

  factory TelemetryValue.fromJson(String key, Map<String, dynamic> json) {
    final ts = json['ts'] ?? json['timestamp'];
    final val = json['value'] ?? json['v'];

    return TelemetryValue(
      key: key,
      value: val,
      timestamp: ts is int
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : ts is String
              ? DateTime.tryParse(ts) ?? DateTime.now()
              : DateTime.now(),
    );
  }

  @override
  String toString() => 'TelemetryValue($key: $value @ $timestamp)';
}

/// Telemetry history response
class TelemetryHistoryDTO {
  const TelemetryHistoryDTO({
    required this.deviceId,
    required this.data,
    this.startTs,
    this.endTs,
  });

  final String deviceId;
  final Map<String, List<TelemetryValue>> data;
  final int? startTs;
  final int? endTs;

  /// Get all values for a key
  List<TelemetryValue> getValues(String key) => data[key] ?? [];

  /// Get all keys
  List<String> get keys => data.keys.toList();

  factory TelemetryHistoryDTO.fromJson(
    Map<String, dynamic> json, {
    String? deviceId,
  }) {
    final Map<String, List<TelemetryValue>> parsedData = {};

    // ThingsBoard format: { "heartRate": [{"ts": 123, "value": 72}, ...], ... }
    final telemetryData = json['data'] as Map<String, dynamic>? ??
        json['telemetry'] as Map<String, dynamic>? ??
        json;

    telemetryData.forEach((key, value) {
      if (value is List) {
        parsedData[key] = value
            .map((e) => TelemetryValue.fromJson(key, e as Map<String, dynamic>))
            .toList();
      }
    });

    return TelemetryHistoryDTO(
      deviceId: deviceId ?? json['deviceId'] as String? ?? '',
      data: parsedData,
      startTs: json['startTs'] as int?,
      endTs: json['endTs'] as int?,
    );
  }
}

