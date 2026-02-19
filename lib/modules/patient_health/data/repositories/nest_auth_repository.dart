import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_exceptions.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/nest_auth_remote_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/models.dart';

/// PATIENT APP: NestJS Authentication Repository Interface
///
/// Defines the contract for authentication operations.

abstract interface class INestAuthRepository {
  /// Login with email and password, stores tokens
  Future<AuthResponse> login(String email, String password);

  /// Register new patient account
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });

  /// Logout and clear stored tokens
  Future<void> logout();

  /// Check if user is currently authenticated
  Future<bool> isAuthenticated();

  /// Get current user profile with linked IDs
  Future<UserProfileDTO> getProfile();

  /// Try to refresh the access token
  Future<bool> refreshToken();
}

/// PATIENT APP: NestJS Authentication Repository Implementation
///
/// Orchestrates authentication flow:
/// 1. Calls NestJS auth endpoints via datasource
/// 2. Stores tokens securely using NestApiClient
/// 3. Manages auth state

class NestAuthRepository implements INestAuthRepository {
  NestAuthRepository({
    required this.datasource,
    required this.apiClient,
    required this.logger,
  });

  final INestAuthRemoteDatasource datasource;
  final NestApiClient apiClient;
  final TbLogger logger;

  /// Cached login response (used as fallback when /auth/profile is unavailable).
  AuthResponse? _lastLoginResponse;

  /// The email used for the most recent successful login.
  String? _lastLoginEmail;

  @override
  Future<AuthResponse> login(String email, String password) async {
    logger.debug('NestAuthRepository: Attempting login for $email');

    try {
      final response = await datasource.login(email, password);

      if (!response.isValid) {
        throw const NestAuthException(
          message: 'Invalid authentication response',
          statusCode: 500,
        );
      }

      // Store tokens securely
      await apiClient.saveTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      );

      // Cache login response for fallback profile construction
      _lastLoginResponse = response;
      _lastLoginEmail = email;

      logger.debug('NestAuthRepository: Login successful for $email');
      return response;
    } on NestApiException catch (e) {
      logger.error('NestAuthRepository: Login failed - ${e.message}');
      rethrow;
    }
  }

  @override
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    logger.debug('NestAuthRepository: Attempting registration for $email');

    try {
      final response = await datasource.register(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );

      if (response.isValid) {
        // Auto-login after registration
        await apiClient.saveTokens(
          accessToken: response.accessToken,
          refreshToken: response.refreshToken,
        );
      }

      logger.debug('NestAuthRepository: Registration successful for $email');
      return response;
    } on NestApiException catch (e) {
      logger.error('NestAuthRepository: Registration failed - ${e.message}');
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    logger.debug('NestAuthRepository: Logging out');

    try {
      // Notify server of logout (invalidate refresh token)
      await datasource.logout();
    } catch (e) {
      logger.warn('NestAuthRepository: Server logout failed - $e');
      // Continue with local logout even if server call fails
    }

    // Always clear local tokens and cached state
    await apiClient.clearTokens();
    _lastLoginResponse = null;
    _lastLoginEmail = null;
    logger.debug('NestAuthRepository: Logout complete');
  }

  @override
  Future<bool> isAuthenticated() async {
    return await apiClient.isAuthenticated();
  }

  @override
  Future<UserProfileDTO> getProfile() async {
    logger.debug('NestAuthRepository: Fetching user profile');

    try {
      return await datasource.getProfile();
    } on NestApiException catch (e) {
      // ── Fallback: profile endpoint not available yet ──────────
      // The backend may not have GET /auth/profile implemented yet.
      // Construct a minimal UserProfileDTO from the login response
      // so the app doesn't crash. Features requiring medplumPatientId
      // or thingsboardDeviceId will gracefully degrade (skip remote
      // data, sync stays dirty).
      if (e.statusCode == 404) {
        logger.warn(
          'NestAuthRepository: /auth/profile returned 404 — '
          'using fallback profile from login data. '
          'Ask backend team to implement GET /auth/profile.',
        );
        return _buildFallbackProfile();
      }
      rethrow;
    }
  }

  /// Build a minimal [UserProfileDTO] from the cached login response.
  ///
  /// This is a degraded mode: `medplumPatientId` and `thingsboardDeviceId`
  /// will be null, so remote data features won't work until the backend
  /// provides the real profile endpoint.
  UserProfileDTO _buildFallbackProfile() {
    final login = _lastLoginResponse?.loginResponse;
    final user = _lastLoginResponse?.user;

    return UserProfileDTO(
      id: login?.id.toString() ?? user?.id ?? '0',
      email: _lastLoginEmail ?? user?.email ?? '',
      role: login?.role ?? user?.role,
      // These are null — the profile endpoint would provide them.
      // Without them: remote fetch skipped, telemetry push skipped.
      medplumPatientId: null,
      thingsboardDeviceId: null,
    );
  }

  @override
  Future<bool> refreshToken() async {
    logger.debug('NestAuthRepository: Attempting token refresh');

    try {
      final refreshToken = await apiClient.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        logger.warn('NestAuthRepository: No refresh token available');
        return false;
      }

      final response = await datasource.refreshToken(refreshToken);

      if (response.isValid) {
        await apiClient.saveTokens(
          accessToken: response.accessToken,
          refreshToken: response.refreshToken ?? refreshToken,
        );
        logger.debug('NestAuthRepository: Token refresh successful');
        return true;
      }

      return false;
    } on NestApiException catch (e) {
      logger.error('NestAuthRepository: Token refresh failed - ${e.message}');
      // Clear tokens if refresh fails with auth error
      if (e.isAuthError) {
        await apiClient.clearTokens();
      }
      return false;
    }
  }
}

