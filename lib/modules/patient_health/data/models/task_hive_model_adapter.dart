import 'package:hive/hive.dart';
import 'package:thingsboard_app/constants/hive_type_adapter_ids.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/task_hive_model.dart';

/// PATIENT APP: Manual Hive Adapter for TaskHiveModel
///
/// Manual implementation to avoid dependency conflicts with code generators.
/// This adapter handles serialization/deserialization of TaskHiveModel.

class TaskHiveModelAdapter extends TypeAdapter<TaskHiveModel> {
  @override
  final int typeId = HiveTypeAdapterIds.taskHiveModelAdapterId;

  @override
  TaskHiveModel read(BinaryReader reader) {
    return TaskHiveModel(
      id: reader.readString(),
      title: reader.readString(),
      time: reader.readString(),
      type: reader.readInt(),
      isCompleted: reader.readBool(),
      description: reader.readBool() ? reader.readString() : null,
      medicationDosage: reader.readBool() ? reader.readDouble() : null,
      medicationUnit: reader.readBool() ? reader.readString() : null,
    );
  }

  @override
  void write(BinaryWriter writer, TaskHiveModel obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeString(obj.time);
    writer.writeInt(obj.type);
    writer.writeBool(obj.isCompleted);
    writer.writeBool(obj.description != null);
    if (obj.description != null) {
      writer.writeString(obj.description!);
    }
    writer.writeBool(obj.medicationDosage != null);
    if (obj.medicationDosage != null) {
      writer.writeDouble(obj.medicationDosage!);
    }
    writer.writeBool(obj.medicationUnit != null);
    if (obj.medicationUnit != null) {
      writer.writeString(obj.medicationUnit!);
    }
  }
}
