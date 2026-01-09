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
  const NestAuthRepository({
    required this.datasource,
    required this.apiClient,
    required this.logger,
  });

  final INestAuthRemoteDatasource datasource;
  final NestApiClient apiClient;
  final TbLogger logger;

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

    // Always clear local tokens
    await apiClient.clearTokens();
    logger.debug('NestAuthRepository: Logout complete');
  }

  @override
  Future<bool> isAuthenticated() async {
    return await apiClient.isAuthenticated();
  }

  @override
  Future<UserProfileDTO> getProfile() async {
    logger.debug('NestAuthRepository: Fetching user profile');
    return await datasource.getProfile();
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

