/// PATIENT APP: User Profile DTO
///
/// Data Transfer Object for the user profile response from NestJS.
///
/// **Backend Contract (GET /patient/profile):**
/// The backend decodes the JWT token to identify the patient. The mobile
/// client does NOT need `medplumPatientId` or `thingsboardDeviceId` —
/// the backend resolves these server-side.
///
/// Devices are fetched from a separate endpoint:
///   GET /patient/{patientId}/devices  (TODO: integrate when available)

class UserProfileDTO {
  const UserProfileDTO({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.role,
    this.updatedAt,
  });

  /// User ID in the NestJS system
  final String id;

  /// User's email address
  final String email;

  /// User's first name
  final String? firstName;

  /// User's last name
  final String? lastName;

  /// User's role (e.g., "PATIENT", "PRACTITIONER")
  final String? role;

  /// Last update timestamp (from Medplum `lastUpdated`)
  final DateTime? updatedAt;

  /// Get full name
  String get fullName {
    final parts = [firstName, lastName].whereType<String>().toList();
    return parts.isNotEmpty ? parts.join(' ') : email;
  }

  /// Parse from JSON response
  factory UserProfileDTO.fromJson(Map<String, dynamic> json) {
    return UserProfileDTO(
      // Try multiple possible field names for ID
      id: json['id']?.toString() ??
          json['_id']?.toString() ??
          json['userId']?.toString() ??
          '',
      email: json['email']?.toString() ?? '',
      firstName: json['firstName'] as String? ??
          json['first_name'] as String? ??
          json['givenName'] as String?,
      lastName: json['lastName'] as String? ??
          json['last_name'] as String? ??
          json['familyName'] as String?,
      role: json['role'] as String? ?? json['userRole'] as String?,
      updatedAt: _parseDateTime(json['updatedAt'] ?? json['updated_at']),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (role != null) 'role': role,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  String toString() =>
      'UserProfileDTO(id: $id, email: $email, role: $role)';
}
