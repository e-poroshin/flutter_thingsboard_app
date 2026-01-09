import 'package:equatable/equatable.dart';

/// PATIENT APP: Patient Entity (Domain Layer)
///
/// Represents a patient's profile information.
/// This is a pure domain entity, independent of data sources.

class PatientEntity extends Equatable {
  const PatientEntity({
    required this.id,
    required this.fullName,
    required this.email,
    this.avatarUrl,
    this.dateOfBirth,
    this.phoneNumber,
    this.gender,
    this.address,
  });

  /// Unique patient identifier
  final String id;

  /// Patient's full name (first + last name)
  final String fullName;

  /// Patient's email address
  final String email;

  /// URL to patient's avatar/profile picture
  final String? avatarUrl;

  /// Patient's date of birth
  final DateTime? dateOfBirth;

  /// Patient's phone number (optional)
  final String? phoneNumber;

  /// Patient's gender (optional)
  final Gender? gender;

  /// Patient's address (optional)
  final String? address;

  /// Get patient's age in years
  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int years = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      years--;
    }
    return years;
  }

  /// Get patient's initials for avatar fallback
  String get initials {
    final parts = fullName.split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  /// Get formatted date of birth string
  String? get formattedDateOfBirth {
    if (dateOfBirth == null) return null;
    return '${dateOfBirth!.year}-${dateOfBirth!.month.toString().padLeft(2, '0')}-${dateOfBirth!.day.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [
        id,
        fullName,
        email,
        avatarUrl,
        dateOfBirth,
        phoneNumber,
        gender,
        address,
      ];

  @override
  String toString() => 'PatientEntity(id: $id, fullName: $fullName)';

  /// Create a copy with updated fields
  PatientEntity copyWith({
    String? id,
    String? fullName,
    String? email,
    String? avatarUrl,
    DateTime? dateOfBirth,
    String? phoneNumber,
    Gender? gender,
    String? address,
  }) {
    return PatientEntity(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      gender: gender ?? this.gender,
      address: address ?? this.address,
    );
  }
}

/// Gender enum for patient demographics
enum Gender {
  male,
  female,
  other,
  unknown;

  String get displayName {
    switch (this) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.other:
        return 'Other';
      case Gender.unknown:
        return 'Unknown';
    }
  }
}

