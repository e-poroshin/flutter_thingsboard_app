import 'package:equatable/equatable.dart';

/// PATIENT APP: Vital History Point (Domain Layer)
///
/// Represents a single data point in a vital sign's historical timeline.
/// Used for charting and trend analysis.

class VitalHistoryPoint extends Equatable {
  const VitalHistoryPoint({
    required this.timestamp,
    required this.value,
  });

  /// When this measurement was taken
  final DateTime timestamp;

  /// The measured value
  final double value;

  @override
  List<Object?> get props => [timestamp, value];

  @override
  String toString() => 'VitalHistoryPoint(timestamp: $timestamp, value: $value)';
}
