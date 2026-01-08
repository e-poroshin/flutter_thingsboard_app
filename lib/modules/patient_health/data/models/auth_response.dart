/// PATIENT APP: Authentication Response Model
///
/// Data model for NestJS authentication responses.

class AuthResponse {
  const AuthResponse({
    required this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.tokenType = 'Bearer',
    this.user,
  });

  /// JWT access token for API authorization
  final String accessToken;

  /// Refresh token for obtaining new access tokens
  final String? refreshToken;

  /// Token expiration time in seconds
  final int? expiresIn;

  /// Token type (usually "Bearer")
  final String tokenType;

  /// User information (if included in response)
  final UserInfo? user;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['accessToken'] as String? ??
          json['access_token'] as String? ??
          '',
      refreshToken: json['refreshToken'] as String? ??
          json['refresh_token'] as String?,
      expiresIn: json['expiresIn'] as int? ?? json['expires_in'] as int?,
      tokenType: json['tokenType'] as String? ??
          json['token_type'] as String? ??
          'Bearer',
      user: json['user'] != null
          ? UserInfo.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      if (refreshToken != null) 'refreshToken': refreshToken,
      if (expiresIn != null) 'expiresIn': expiresIn,
      'tokenType': tokenType,
      if (user != null) 'user': user!.toJson(),
    };
  }

  /// Check if the token is valid (not empty)
  bool get isValid => accessToken.isNotEmpty;

  @override
  String toString() =>
      'AuthResponse(accessToken: ${accessToken.substring(0, 10)}..., '
      'hasRefreshToken: ${refreshToken != null})';
}

/// PATIENT APP: User Information Model
///
/// Basic user info returned with authentication.
class UserInfo {
  const UserInfo({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.role,
  });

  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? role;

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      firstName: json['firstName'] as String? ?? json['first_name'] as String?,
      lastName: json['lastName'] as String? ?? json['last_name'] as String?,
      role: json['role'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (role != null) 'role': role,
    };
  }

  String get fullName {
    final parts = [firstName, lastName].whereType<String>();
    return parts.isNotEmpty ? parts.join(' ') : email;
  }

  @override
  String toString() => 'UserInfo(id: $id, email: $email)';
}

