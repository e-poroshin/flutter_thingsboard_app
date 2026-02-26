/// PATIENT APP: Authentication Response Models
///
/// **Cookie-Based Auth Architecture (POST /api/patient/login):**
///
/// The backend returns tokens in HTTP-only `set-cookie` headers, NOT
/// in the response body. Mobile apps cannot read HttpOnly cookies via
/// standard cookie jars, so the [NestAuthRemoteDatasource] manually
/// parses the raw `set-cookie` header strings and stores the tokens
/// in FlutterSecureStorage.
///
/// **Response Body:** `{ "id": 1, "role": "PATIENT", "success": true }`
/// **Response Headers:** `set-cookie: Authentication=<jwt>; ..., Refresh=<jwt>; ...`

// ============================================================
// Login Response DTO (Response Body)
// ============================================================

/// DTO for the POST /api/patient/login response body.
///
/// The body only contains user metadata — tokens are in cookies.
class LoginResponseDto {
  const LoginResponseDto({
    required this.id,
    required this.role,
    required this.success,
  });

  /// Backend user ID
  final int id;

  /// User role (e.g., "PATIENT", "PRACTITIONER")
  final String role;

  /// Whether the login was successful
  final bool success;

  factory LoginResponseDto.fromJson(Map<String, dynamic> json) {
    return LoginResponseDto(
      id: json['id'] as int? ?? 0,
      role: json['role'] as String? ?? '',
      success: json['success'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'success': success,
      };

  @override
  String toString() =>
      'LoginResponseDto(id: $id, role: $role, success: $success)';
}

// ============================================================
// Auth Response (Internal — carries extracted tokens)
// ============================================================

/// Internal auth response used by the Repository and BLoC layers.
///
/// Constructed by [NestAuthRemoteDatasource] from:
/// - **Tokens** extracted from `set-cookie` response headers
/// - **User info** from the response body ([LoginResponseDto])
///
/// The [NestAuthRepository] reads [accessToken] / [refreshToken]
/// from this object and persists them via [NestApiClient.saveTokens].
class AuthResponse {
  const AuthResponse({
    required this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.tokenType = 'Bearer',
    this.user,
    this.loginResponse,
  });

  /// JWT access token extracted from the `Authentication` cookie.
  final String accessToken;

  /// Refresh token extracted from the `Refresh` cookie.
  final String? refreshToken;

  /// Token expiration time in seconds (from `Max-Age` cookie attribute).
  final int? expiresIn;

  /// Token type (always "Bearer" — used when attaching to requests).
  final String tokenType;

  /// User information (optional, from response body or profile).
  final UserInfo? user;

  /// Raw login response body (id, role, success).
  /// Useful for downstream checks (e.g., role-based routing).
  final LoginResponseDto? loginResponse;

  /// Construct from the login response body + extracted cookie tokens.
  ///
  /// This is the primary factory used by [NestAuthRemoteDatasource].
  factory AuthResponse.fromCookieAuth({
    required LoginResponseDto body,
    required String accessToken,
    String? refreshToken,
    int? maxAge,
  }) {
    return AuthResponse(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: maxAge,
      loginResponse: body,
      user: UserInfo(
        id: body.id.toString(),
        email: '', // Email not in body — fetched later via /patient/profile
        role: body.role,
      ),
    );
  }

  /// Legacy factory: parse from a JSON body that contains tokens directly.
  /// Kept for backwards compatibility with other endpoints (register, refresh).
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
      if (loginResponse != null) 'loginResponse': loginResponse!.toJson(),
    };
  }

  /// Whether this response contains a usable access token.
  bool get isValid => accessToken.isNotEmpty;

  @override
  String toString() {
    final tokenPreview = accessToken.length > 10
        ? '${accessToken.substring(0, 10)}...'
        : accessToken;
    return 'AuthResponse(token: $tokenPreview, '
        'hasRefresh: ${refreshToken != null}, '
        'role: ${loginResponse?.role ?? user?.role ?? "?"})';
  }
}

// ============================================================
// User Information
// ============================================================

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
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
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
