import 'package:equatable/equatable.dart';

/// PATIENT APP: Vital Sign Entity (Domain Layer)
///
/// Represents a health metric/vital sign measurement.
/// This is a pure domain entity, independent of data sources.

class VitalSignEntity extends Equatable {
  const VitalSignEntity({
    required this.type,
    required this.value,
    required this.unit,
    required this.timestamp,
    this.isCritical = false,
    this.deviceId,
    this.notes,
  });

  /// Type of vital sign (heart rate, blood pressure, etc.)
  final VitalSignType type;

  /// The measured value (can be numeric or string for complex values like BP)
  final dynamic value;

  /// Unit of measurement (bpm, mmHg, °C, %, etc.)
  final String unit;

  /// When this measurement was taken
  final DateTime timestamp;

  /// Whether this value is outside normal/safe range
  final bool isCritical;

  /// ID of the device that recorded this measurement (optional)
  final String? deviceId;

  /// Additional notes or context (optional)
  final String? notes;

  /// Get the numeric value (for single-value vitals)
  double? get numericValue {
    if (value is num) return (value as num).toDouble();
    if (value is String) return double.tryParse(value as String);
    return null;
  }

  /// Get a formatted display string for the value
  String get displayValue {
    if (value is Map) {
      // Handle blood pressure: { "systolic": 120, "diastolic": 80 }
      final map = value as Map;
      if (map.containsKey('systolic') && map.containsKey('diastolic')) {
        return '${map['systolic']}/${map['diastolic']}';
      }
    }
    return '$value';
  }

  /// Get full display with unit
  String get displayWithUnit => '$displayValue $unit';

  /// Check if this is a normal value based on type-specific ranges
  bool get isNormal => !isCritical;

  /// Get the status color name based on value
  String get statusColorName {
    if (isCritical) return 'red';
    return 'green';
  }

  /// Get time ago string
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  List<Object?> get props => [
        type,
        value,
        unit,
        timestamp,
        isCritical,
        deviceId,
        notes,
      ];

  @override
  String toString() =>
      'VitalSignEntity(type: ${type.name}, value: $displayValue $unit)';

  /// Create a copy with updated fields
  VitalSignEntity copyWith({
    VitalSignType? type,
    dynamic value,
    String? unit,
    DateTime? timestamp,
    bool? isCritical,
    String? deviceId,
    String? notes,
  }) {
    return VitalSignEntity(
      type: type ?? this.type,
      value: value ?? this.value,
      unit: unit ?? this.unit,
      timestamp: timestamp ?? this.timestamp,
      isCritical: isCritical ?? this.isCritical,
      deviceId: deviceId ?? this.deviceId,
      notes: notes ?? this.notes,
    );
  }
}

/// Types of vital signs that can be tracked
enum VitalSignType {
  heartRate,
  bloodPressure,
  temperature,
  oxygenSaturation,
  respiratoryRate,
  bloodGlucose,
  weight,
  height,
  bmi;

  /// Display name for UI
  String get displayName {
    switch (this) {
      case VitalSignType.heartRate:
        return 'Heart Rate';
      case VitalSignType.bloodPressure:
        return 'Blood Pressure';
      case VitalSignType.temperature:
        return 'Temperature';
      case VitalSignType.oxygenSaturation:
        return 'Oxygen Saturation';
      case VitalSignType.respiratoryRate:
        return 'Respiratory Rate';
      case VitalSignType.bloodGlucose:
        return 'Blood Glucose';
      case VitalSignType.weight:
        return 'Weight';
      case VitalSignType.height:
        return 'Height';
      case VitalSignType.bmi:
        return 'BMI';
    }
  }

  /// Default unit for this vital type
  String get defaultUnit {
    switch (this) {
      case VitalSignType.heartRate:
        return 'bpm';
      case VitalSignType.bloodPressure:
        return 'mmHg';
      case VitalSignType.temperature:
        return '°C';
      case VitalSignType.oxygenSaturation:
        return '%';
      case VitalSignType.respiratoryRate:
        return '/min';
      case VitalSignType.bloodGlucose:
        return 'mg/dL';
      case VitalSignType.weight:
        return 'kg';
      case VitalSignType.height:
        return 'cm';
      case VitalSignType.bmi:
        return 'kg/m²';
    }
  }

  /// Icon name for this vital type
  String get iconName {
    switch (this) {
      case VitalSignType.heartRate:
        return 'favorite';
      case VitalSignType.bloodPressure:
        return 'speed';
      case VitalSignType.temperature:
        return 'thermostat';
      case VitalSignType.oxygenSaturation:
        return 'air';
      case VitalSignType.respiratoryRate:
        return 'airline_seat_flat';
      case VitalSignType.bloodGlucose:
        return 'bloodtype';
      case VitalSignType.weight:
        return 'monitor_weight';
      case VitalSignType.height:
        return 'height';
      case VitalSignType.bmi:
        return 'calculate';
    }
  }

  /// Normal range for this vital type (min, max)
  /// Returns null if range check not applicable
  (double min, double max)? get normalRange {
    switch (this) {
      case VitalSignType.heartRate:
        return (60, 100);
      case VitalSignType.temperature:
        return (36.1, 37.2);
      case VitalSignType.oxygenSaturation:
        return (95, 100);
      case VitalSignType.respiratoryRate:
        return (12, 20);
      case VitalSignType.bloodGlucose:
        return (70, 140);
      case VitalSignType.bloodPressure:
        return null; // Complex range check needed
      case VitalSignType.weight:
      case VitalSignType.height:
      case VitalSignType.bmi:
        return null; // Depends on individual
    }
  }

  /// Check if a value is within normal range
  bool isValueNormal(double value) {
    final range = normalRange;
    if (range == null) return true;
    return value >= range.$1 && value <= range.$2;
  }
}

