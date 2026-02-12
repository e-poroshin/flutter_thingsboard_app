import 'package:hive/hive.dart';
import 'package:thingsboard_app/constants/hive_type_adapter_ids.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/vital_history_hive_model.dart';

/// PATIENT APP: Manual Hive Adapter for VitalHistoryHiveModel
///
/// Manual implementation to avoid dependency conflicts with code generators.
/// This adapter handles serialization/deserialization of VitalHistoryHiveModel.

class VitalHistoryHiveModelAdapter extends TypeAdapter<VitalHistoryHiveModel> {
  @override
  final int typeId = HiveTypeAdapterIds.vitalHistoryHiveModelAdapterId;

  @override
  VitalHistoryHiveModel read(BinaryReader reader) {
    return VitalHistoryHiveModel(
      vitalType: reader.readString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      value: reader.readDouble(),
      unit: reader.readBool() ? reader.readString() : null,
    );
  }

  @override
  void write(BinaryWriter writer, VitalHistoryHiveModel obj) {
    writer.writeString(obj.vitalType);
    writer.writeInt(obj.timestamp.millisecondsSinceEpoch);
    writer.writeDouble(obj.value);
    writer.writeBool(obj.unit != null);
    if (obj.unit != null) {
      writer.writeString(obj.unit!);
    }
  }
}
