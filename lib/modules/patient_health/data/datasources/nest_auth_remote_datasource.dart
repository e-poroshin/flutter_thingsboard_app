import 'package:dio/dio.dart';
import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_config.dart';
import 'package:thingsboard_app/core/network/nest_api_exceptions.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/models.dart';

/// PATIENT APP: NestJS Authentication Remote Datasource
///
/// Handles authentication API calls to the NestJS BFF server.
///
/// **Cookie-Based Auth (POST /api/patient/login):**
/// The backend returns tokens in `set-cookie` HTTP headers, NOT in the
/// response body. This datasource:
/// 1. POSTs credentials using `apiClient.dio` (raw Dio) to access headers.
/// 2. Parses `set-cookie` headers to extract `Authentication` + `Refresh` JWTs.
/// 3. Constructs an [AuthResponse] carrying the tokens.
/// 4. The [NestAuthRepository] then persists these tokens via
///    [NestApiClient.saveTokens].
///
/// **Endpoints:**
/// - POST /api/patient/login — Login with email/password (cookies)
/// - GET  /auth/profile      — Get user profile with linked IDs

abstract interface class INestAuthRemoteDatasource {
  /// Login with email and password.
  ///
  /// Tokens are extracted from `set-cookie` response headers (not body).
  /// Returns [AuthResponse] containing the extracted JWT tokens.
  Future<AuthResponse> login(String email, String password);

  /// Register a new patient account
  /// Endpoint: POST /auth/register
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });

  /// Refresh the access token using refresh token
  /// Endpoint: POST /auth/refresh
  Future<AuthResponse> refreshToken(String refreshToken);

  /// Logout and invalidate tokens on server
  /// Endpoint: POST /auth/logout
  Future<void> logout();

  /// Get current user profile with linked IDs
  /// Endpoint: GET /auth/profile
  /// Returns: userId, medplumPatientId, thingsboardDeviceId
  Future<UserProfileDTO> getProfile();
}

class NestAuthRemoteDatasource implements INestAuthRemoteDatasource {
  const NestAuthRemoteDatasource({
    required this.apiClient,
  });

  final NestApiClient apiClient;

  // ============================================================
  // Login (Cookie-Based Auth)
  // ============================================================

  @override
  Future<AuthResponse> login(String email, String password) async {
    try {
      // Use raw Dio to access full Response (including headers).
      // NestApiClient.post() only returns the body, which doesn't
      // contain tokens — they're in set-cookie headers.
      final response = await apiClient.dio.post<dynamic>(
        NestApiConfig.authLogin,
        data: {
          'email': email,
          'password': password,
        },
      );

      // ── Parse response body ──────────────────────────────────
      final bodyData = response.data;
      if (bodyData is! Map<String, dynamic>) {
        throw const NestApiException(
          message: 'Invalid login response format',
          statusCode: 500,
        );
      }

      final loginDto = LoginResponseDto.fromJson(bodyData);

      if (!loginDto.success) {
        throw const NestAuthException(
          message: 'Login failed. Please check your credentials.',
          statusCode: 401,
        );
      }

      // ── Extract tokens from set-cookie headers ───────────────
      final cookies = response.headers.map['set-cookie'];
      final (accessToken, refreshToken) = _extractTokensFromCookies(cookies);

      if (accessToken == null || accessToken.isEmpty) {
        throw const NestApiException(
          message: 'No authentication token received from server',
          statusCode: 500,
        );
      }

      // ── Parse optional Max-Age for token expiry ──────────────
      final maxAge = _extractMaxAge(cookies);

      apiClient.logger.debug(
        'NestAuthRemoteDatasource: Login successful — '
        'id: ${loginDto.id}, role: ${loginDto.role}, '
        'hasRefreshToken: ${refreshToken != null}',
      );

      // Construct AuthResponse with extracted tokens
      return AuthResponse.fromCookieAuth(
        body: loginDto,
        accessToken: accessToken,
        refreshToken: refreshToken,
        maxAge: maxAge,
      );
    } on DioException catch (e) {
      // Map Dio errors to our exception types
      if (e.response?.statusCode == 401) {
        throw NestAuthException.invalidCredentials();
      }
      throw NestApiException(
        message: e.response?.data?['message']?.toString() ??
            e.message ??
            'Login failed',
        statusCode: e.response?.statusCode ?? 0,
        type: NestApiExceptionType.unknown,
      );
    } on NestApiException {
      rethrow;
    }
  }

  // ============================================================
  // Cookie Parsing Helpers
  // ============================================================

  /// Extract access and refresh tokens from raw `set-cookie` header values.
  ///
  /// **Expected cookie format (NestJS standard):**
  /// ```
  /// Authentication=eyJhbGciOi...; HttpOnly; Path=/; Max-Age=3600; Secure
  /// Refresh=eyJhbGciOi...; HttpOnly; Path=/; Max-Age=604800; Secure
  /// ```
  ///
  /// The method is flexible and checks multiple common cookie names:
  /// - Access: `Authentication`, `accessToken`, `access_token`, `token`
  /// - Refresh: `Refresh`, `refreshToken`, `refresh_token`
  ///
  /// Returns a `(String? accessToken, String? refreshToken)` record.
  static (String?, String?) _extractTokensFromCookies(List<String>? cookies) {
    if (cookies == null || cookies.isEmpty) {
      return (null, null);
    }

    String? accessToken;
    String? refreshToken;

    // Common cookie names for access token (case-insensitive match)
    const accessNames = [
      'authentication',
      'accesstoken',
      'access_token',
      'token',
    ];

    // Common cookie names for refresh token (case-insensitive match)
    const refreshNames = [
      'refresh',
      'refreshtoken',
      'refresh_token',
    ];

    for (final rawCookie in cookies) {
      // Each raw cookie string looks like:
      // "Authentication=eyJhbGci...; HttpOnly; Path=/; Max-Age=3600"
      //
      // Split on ';' to get attributes, the first part is "name=value".
      final parts = rawCookie.split(';');
      if (parts.isEmpty) continue;

      final nameValue = parts.first.trim();
      final equalsIndex = nameValue.indexOf('=');
      if (equalsIndex < 1) continue;

      final cookieName = nameValue.substring(0, equalsIndex).trim().toLowerCase();
      final cookieValue = nameValue.substring(equalsIndex + 1).trim();

      if (cookieValue.isEmpty) continue;

      // Match against known access token cookie names
      if (accessToken == null && accessNames.contains(cookieName)) {
        accessToken = cookieValue;
      }

      // Match against known refresh token cookie names
      if (refreshToken == null && refreshNames.contains(cookieName)) {
        refreshToken = cookieValue;
      }

      // Both found — no need to keep scanning
      if (accessToken != null && refreshToken != null) break;
    }

    return (accessToken, refreshToken);
  }

  /// Extract `Max-Age` value (in seconds) from the access token cookie.
  ///
  /// Returns `null` if not found.
  static int? _extractMaxAge(List<String>? cookies) {
    if (cookies == null || cookies.isEmpty) return null;

    for (final rawCookie in cookies) {
      final lower = rawCookie.toLowerCase();
      // Only check the cookie that contains the access token
      if (!lower.startsWith('authentication=') &&
          !lower.startsWith('accesstoken=') &&
          !lower.startsWith('token=')) {
        continue;
      }

      // Look for Max-Age attribute
      final parts = rawCookie.split(';');
      for (final attr in parts) {
        final trimmed = attr.trim().toLowerCase();
        if (trimmed.startsWith('max-age=')) {
          final valueStr = trimmed.substring('max-age='.length).trim();
          return int.tryParse(valueStr);
        }
      }
    }

    return null;
  }

  // ============================================================
  // Other Auth Endpoints (unchanged)
  // ============================================================

  @override
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        NestApiConfig.authRegister,
        data: {
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
        },
      );

      return AuthResponse.fromJson(response);
    } on NestApiException {
      rethrow;
    }
  }

  @override
  Future<AuthResponse> refreshToken(String refreshToken) async {
    try {
      // Refresh may also use cookies — try raw Dio first
      final response = await apiClient.dio.post<dynamic>(
        NestApiConfig.authRefresh,
        data: {
          'refreshToken': refreshToken,
        },
      );

      // Check if new tokens are in cookies
      final cookies = response.headers.map['set-cookie'];
      final (newAccessToken, newRefreshToken) =
          _extractTokensFromCookies(cookies);

      if (newAccessToken != null && newAccessToken.isNotEmpty) {
        // Cookie-based refresh response
        return AuthResponse(
          accessToken: newAccessToken,
          refreshToken: newRefreshToken ?? refreshToken,
        );
      }

      // Fallback: tokens in response body (legacy format)
      if (response.data is Map<String, dynamic>) {
        return AuthResponse.fromJson(response.data as Map<String, dynamic>);
      }

      throw NestAuthException.tokenExpired();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw NestAuthException.tokenExpired();
      }
      throw NestApiException(
        message: e.message ?? 'Token refresh failed',
        statusCode: e.response?.statusCode ?? 0,
      );
    } on NestApiException {
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    try {
      await apiClient.post<void>(NestApiConfig.authLogout);
    } on NestApiException {
      // Ignore errors on logout - we'll clear tokens anyway
    }
  }

  @override
  Future<UserProfileDTO> getProfile() async {
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.authProfile,
    );
    return UserProfileDTO.fromJson(response);
  }
}
