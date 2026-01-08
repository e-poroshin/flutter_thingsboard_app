import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_config.dart';
import 'package:thingsboard_app/core/network/nest_api_exceptions.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/auth_response.dart';

/// PATIENT APP: NestJS Authentication Remote Datasource
///
/// Handles authentication API calls to the NestJS BFF server.
/// This replaces the default ThingsBoard authentication.

abstract interface class INestAuthRemoteDatasource {
  /// Login with email and password
  /// Returns [AuthResponse] containing the access token
  Future<AuthResponse> login(String email, String password);

  /// Register a new patient account
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });

  /// Refresh the access token using refresh token
  Future<AuthResponse> refreshToken(String refreshToken);

  /// Logout and invalidate tokens on server
  Future<void> logout();

  /// Get current user profile
  Future<Map<String, dynamic>> getProfile();
}

class NestAuthRemoteDatasource implements INestAuthRemoteDatasource {
  const NestAuthRemoteDatasource({
    required this.apiClient,
  });

  final NestApiClient apiClient;

  @override
  Future<AuthResponse> login(String email, String password) async {
    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        NestApiConfig.authLogin,
        data: {
          'email': email,
          'password': password,
        },
      );

      return AuthResponse.fromJson(response);
    } on NestApiException catch (e) {
      // Re-throw with more specific auth error
      if (e.statusCode == 401) {
        throw NestAuthException.invalidCredentials();
      }
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
      final response = await apiClient.post<Map<String, dynamic>>(
        NestApiConfig.authRefresh,
        data: {
          'refreshToken': refreshToken,
        },
      );

      return AuthResponse.fromJson(response);
    } on NestApiException catch (e) {
      if (e.statusCode == 401) {
        throw NestAuthException.tokenExpired();
      }
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
  Future<Map<String, dynamic>> getProfile() async {
    final response = await apiClient.get<Map<String, dynamic>>(
      NestApiConfig.authProfile,
    );
    return response;
  }
}

