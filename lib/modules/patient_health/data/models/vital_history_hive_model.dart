import 'package:hive/hive.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_history_point.dart';

/// PATIENT APP: Sync status for the Write-Ahead Log (WAL) pattern.
///
/// Tracks whether a locally-stored vital measurement has been
/// successfully pushed to the SmartBean Proxy backend.
///
/// State machine:
/// ```
/// [new measurement] ──► dirty ──► syncing ──► synced
///                         ▲          │
///                         └──────────┘  (on network failure)
/// ```
enum SyncStatus {
  /// Saved locally, NOT yet sent to backend.
  /// Items in this state will be picked up by [TelemetrySyncWorker].
  dirty,

  /// Currently being uploaded to the backend.
  /// Prevents the sync worker from double-sending.
  syncing,

  /// Successfully confirmed by the backend.
  /// Safe to prune during Hive trimming.
  synced,
}

/// PATIENT APP: Vital History Hive Model (Data Layer)
///
/// Hive model for persisting vital sign measurements to local storage.
/// Each instance represents a single data point (timestamp + value) for
/// a given vital type (temperature, humidity, etc.).
///
/// **WAL Pattern:**
/// Every measurement is written to Hive first with [SyncStatus.dirty],
/// then an optimistic network push is attempted. If the push fails, the
/// [TelemetrySyncWorker] will retry later.
///
/// Note: Using manual adapter instead of code generation to avoid
/// dependency conflicts with freezed and custom_lint.

class VitalHistoryHiveModel extends HiveObject {
  VitalHistoryHiveModel({
    required this.vitalType,
    required this.timestamp,
    required this.value,
    this.unit,
    this.syncStatus = SyncStatus.dirty,
  });

  /// Type of vital sign (e.g., 'temperature', 'humidity')
  final String vitalType;

  /// When this measurement was taken
  final DateTime timestamp;

  /// The measured value
  final double value;

  /// Optional unit of measurement (e.g., '°C', '%')
  final String? unit;

  /// Sync status for the Write-Ahead Log pattern.
  ///
  /// - [SyncStatus.dirty]   — saved locally, not yet sent to backend
  /// - [SyncStatus.syncing] — currently being uploaded (prevents double-send)
  /// - [SyncStatus.synced]  — confirmed by backend (safe to prune)
  ///
  /// Mutable so it can be updated in-place via [HiveObject.save()].
  SyncStatus syncStatus;

  /// Whether this measurement still needs to be pushed to the backend.
  bool get needsSync => syncStatus == SyncStatus.dirty;

  /// Whether this measurement has been confirmed by the backend.
  bool get isSynced => syncStatus == SyncStatus.synced;

  /// Convert Hive model to Domain Entity
  VitalHistoryPoint toEntity() {
    return VitalHistoryPoint(
      timestamp: timestamp,
      value: value,
    );
  }

  /// Create Hive model from individual values.
  ///
  /// New measurements default to [SyncStatus.dirty] so they enter
  /// the sync queue automatically.
  factory VitalHistoryHiveModel.fromMeasurement({
    required String vitalType,
    required double value,
    String? unit,
    DateTime? timestamp,
    SyncStatus syncStatus = SyncStatus.dirty,
  }) {
    return VitalHistoryHiveModel(
      vitalType: vitalType,
      timestamp: timestamp ?? DateTime.now(),
      value: value,
      unit: unit,
      syncStatus: syncStatus,
    );
  }

  @override
  String toString() =>
      'VitalHistoryHiveModel(type: $vitalType, value: $value, '
      'timestamp: $timestamp, sync: ${syncStatus.name})';
}
