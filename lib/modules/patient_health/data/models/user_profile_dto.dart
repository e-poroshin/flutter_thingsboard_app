/// PATIENT APP: User Profile DTO
///
/// Data Transfer Object for the user profile response from NestJS.
/// This is the CRUCIAL model that provides the linked IDs needed for
/// fetching data from Medplum and ThingsBoard.
///
/// Endpoint: GET /auth/profile or GET /users/me

class UserProfileDTO {
  const UserProfileDTO({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.role,
    this.medplumPatientId,
    this.thingsboardDeviceId,
    this.thingsboardUserId,
    this.createdAt,
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

  /// User's role (e.g., "patient", "admin")
  final String? role;

  /// CRITICAL: Medplum Patient resource ID
  /// Used for: GET /medplum/Patient/{medplumPatientId}
  final String? medplumPatientId;

  /// CRITICAL: ThingsBoard Device ID linked to this patient
  /// Used for: GET /thingsboard/device/{thingsboardDeviceId}/telemetry
  final String? thingsboardDeviceId;

  /// ThingsBoard User ID (if applicable)
  final String? thingsboardUserId;

  /// Account creation timestamp
  final DateTime? createdAt;

  /// Last update timestamp
  final DateTime? updatedAt;

  /// Get full name
  String get fullName {
    final parts = [firstName, lastName].whereType<String>().toList();
    return parts.isNotEmpty ? parts.join(' ') : email;
  }

  /// Check if user has linked Medplum patient
  bool get hasMedplumPatient =>
      medplumPatientId != null && medplumPatientId!.isNotEmpty;

  /// Check if user has linked ThingsBoard device
  bool get hasThingsboardDevice =>
      thingsboardDeviceId != null && thingsboardDeviceId!.isNotEmpty;

  /// Parse from JSON response
  /// TODO: Verify field names with actual API response
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
      // CRITICAL: These IDs link to external systems
      medplumPatientId: json['medplumPatientId'] as String? ??
          json['medplum_patient_id'] as String? ??
          json['patientId'] as String? ??
          json['fhirPatientId'] as String?,
      thingsboardDeviceId: json['thingsboardDeviceId'] as String? ??
          json['thingsboard_device_id'] as String? ??
          json['deviceId'] as String? ??
          json['tbDeviceId'] as String?,
      thingsboardUserId: json['thingsboardUserId'] as String? ??
          json['thingsboard_user_id'] as String? ??
          json['tbUserId'] as String?,
      createdAt: _parseDateTime(json['createdAt'] ?? json['created_at']),
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
      if (medplumPatientId != null) 'medplumPatientId': medplumPatientId,
      if (thingsboardDeviceId != null) 'thingsboardDeviceId': thingsboardDeviceId,
      if (thingsboardUserId != null) 'thingsboardUserId': thingsboardUserId,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
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
      'UserProfileDTO(id: $id, email: $email, '
      'medplumPatientId: $medplumPatientId, '
      'thingsboardDeviceId: $thingsboardDeviceId)';
}

