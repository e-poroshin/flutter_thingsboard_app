import 'package:hive/hive.dart';
import 'package:thingsboard_app/constants/hive_type_adapter_ids.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/vital_history_hive_model.dart';

/// PATIENT APP: Manual Hive Adapter for VitalHistoryHiveModel
///
/// Manual implementation to avoid dependency conflicts with code generators.
/// This adapter handles serialization/deserialization of VitalHistoryHiveModel.
///
/// **Field layout (binary order):**
/// | Index | Field       | Type     | Notes                               |
/// |-------|-------------|----------|-------------------------------------|
/// | 0     | vitalType   | String   |                                     |
/// | 1     | timestamp   | int      | millisecondsSinceEpoch              |
/// | 2     | value       | double   |                                     |
/// | 3     | unit        | String?  | bool flag + optional string         |
/// | 4     | syncStatus  | int      | SyncStatus enum index (v2, WAL)     |
///
/// **Migration note (v1 → v2):**
/// Existing Hive entries written before the WAL update won't have field 4.
/// The [read] method handles this gracefully by catching the read error
/// and defaulting to [SyncStatus.synced] for pre-existing data (since it
/// was never meant to be synced).

class VitalHistoryHiveModelAdapter extends TypeAdapter<VitalHistoryHiveModel> {
  @override
  final int typeId = HiveTypeAdapterIds.vitalHistoryHiveModelAdapterId;

  @override
  VitalHistoryHiveModel read(BinaryReader reader) {
    // Read the original 4 fields (v1 format)
    final vitalType = reader.readString();
    final timestampMs = reader.readInt();
    final value = reader.readDouble();
    final hasUnit = reader.readBool();
    final unit = hasUnit ? reader.readString() : null;

    // Read the new syncStatus field (v2 — WAL).
    // If the entry was written before the WAL update, the reader will
    // have no more bytes and will throw. We catch that and default to
    // SyncStatus.synced (legacy data is considered already "synced"
    // since there was no backend to sync to).
    SyncStatus syncStatus;
    try {
      final syncIndex = reader.readInt();
      syncStatus = SyncStatus.values[
          syncIndex.clamp(0, SyncStatus.values.length - 1)];
    } catch (_) {
      // Pre-WAL entry — treat as already synced
      syncStatus = SyncStatus.synced;
    }

    return VitalHistoryHiveModel(
      vitalType: vitalType,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      value: value,
      unit: unit,
      syncStatus: syncStatus,
    );
  }

  @override
  void write(BinaryWriter writer, VitalHistoryHiveModel obj) {
    // v1 fields
    writer.writeString(obj.vitalType);
    writer.writeInt(obj.timestamp.millisecondsSinceEpoch);
    writer.writeDouble(obj.value);
    writer.writeBool(obj.unit != null);
    if (obj.unit != null) {
      writer.writeString(obj.unit!);
    }

    // v2 field — syncStatus (WAL)
    writer.writeInt(obj.syncStatus.index);
  }
}
