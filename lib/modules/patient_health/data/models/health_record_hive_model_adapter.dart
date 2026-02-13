import 'package:hive/hive.dart';
import 'package:thingsboard_app/constants/hive_type_adapter_ids.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/health_record_hive_model.dart';

/// PATIENT APP: Manual Hive Adapter for HealthRecordHiveModel
///
/// Manual implementation to avoid dependency conflicts with code generators.
/// This adapter handles serialization/deserialization of HealthRecordHiveModel.

class HealthRecordHiveModelAdapter extends TypeAdapter<HealthRecordHiveModel> {
  @override
  final int typeId = HiveTypeAdapterIds.healthRecordHiveModelAdapterId;

  @override
  HealthRecordHiveModel read(BinaryReader reader) {
    final id = reader.readString();
    final timestamp = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final mood = reader.readInt();

    // Read symptoms list
    final symptomCount = reader.readInt();
    final symptoms = <String>[];
    for (var i = 0; i < symptomCount; i++) {
      symptoms.add(reader.readString());
    }

    // Read optional note
    final hasNote = reader.readBool();
    final note = hasNote ? reader.readString() : null;

    return HealthRecordHiveModel(
      id: id,
      timestamp: timestamp,
      mood: mood,
      symptoms: symptoms,
      note: note,
    );
  }

  @override
  void write(BinaryWriter writer, HealthRecordHiveModel obj) {
    writer.writeString(obj.id);
    writer.writeInt(obj.timestamp.millisecondsSinceEpoch);
    writer.writeInt(obj.mood);

    // Write symptoms list
    writer.writeInt(obj.symptoms.length);
    for (final symptom in obj.symptoms) {
      writer.writeString(symptom);
    }

    // Write optional note
    writer.writeBool(obj.note != null);
    if (obj.note != null) {
      writer.writeString(obj.note!);
    }
  }
}
