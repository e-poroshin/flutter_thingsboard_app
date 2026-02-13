import 'package:equatable/equatable.dart';

/// PATIENT APP: Health Record Entity (Domain Layer)
///
/// Represents a patient-reported health record containing
/// subjective data: mood, symptoms, and optional notes.
/// Used to correlate with objective sensor data from BLE devices.

class HealthRecordEntity extends Equatable {
  const HealthRecordEntity({
    required this.id,
    required this.timestamp,
    required this.mood,
    this.symptoms = const [],
    this.note,
  });

  /// Unique record identifier (UUID)
  final String id;

  /// When this record was created
  final DateTime timestamp;

  /// Mood on a 1-5 scale (1 = worst, 5 = best)
  final int mood;

  /// List of reported symptoms (e.g., ['Headache', 'Nausea'])
  final List<String> symptoms;

  /// Optional free-text note from the patient
  final String? note;

  /// Get a mood emoji for display
  String get moodEmoji {
    switch (mood) {
      case 1:
        return '😫';
      case 2:
        return '🤢';
      case 3:
        return '😐';
      case 4:
        return '🙂';
      case 5:
        return '😊';
      default:
        return '😐';
    }
  }

  /// Get a mood label for display
  String get moodLabel {
    switch (mood) {
      case 1:
        return 'Very Bad';
      case 2:
        return 'Bad';
      case 3:
        return 'Okay';
      case 4:
        return 'Good';
      case 5:
        return 'Great';
      default:
        return 'Unknown';
    }
  }

  /// Get a short summary for list display
  String get summary {
    if (symptoms.isEmpty) {
      return '$moodEmoji $moodLabel - No symptoms';
    }
    return '$moodEmoji $moodLabel - ${symptoms.join(', ')}';
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
  List<Object?> get props => [id, timestamp, mood, symptoms, note];

  @override
  String toString() =>
      'HealthRecordEntity(id: $id, mood: $mood, symptoms: $symptoms)';

  /// Create a copy with updated fields
  HealthRecordEntity copyWith({
    String? id,
    DateTime? timestamp,
    int? mood,
    List<String>? symptoms,
    String? note,
  }) {
    return HealthRecordEntity(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      mood: mood ?? this.mood,
      symptoms: symptoms ?? this.symptoms,
      note: note ?? this.note,
    );
  }
}

/// Common symptoms that can be selected in the UI
class CommonSymptoms {
  CommonSymptoms._();

  static const List<String> all = [
    'Headache',
    'Fever',
    'Cough',
    'Fatigue',
    'Dizziness',
    'Nausea',
    'Chest Pain',
    'Shortness of Breath',
  ];
}
