import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/network/nest_api_exceptions.dart';

/// PATIENT APP: NestJS API Client
///
/// Central HTTP client for communicating with the NestJS BFF server.
/// Handles JWT authentication, token storage, and error mapping.
///
/// **Architecture:**
/// - App authenticates against NestJS (not ThingsBoard directly)
/// - NestJS proxies requests to ThingsBoard/Medplum using server-side credentials
/// - App only stores and uses NestJS JWT tokens

class NestApiClient {
  NestApiClient({
    required this.baseUrl,
    required this.storage,
    required this.logger,
  }) {
    _dio = Dio(_createBaseOptions());
    _setupInterceptors();
  }

  final String baseUrl;
  final FlutterSecureStorage storage;
  final TbLogger logger;

  late final Dio _dio;

  // Storage keys for tokens
  static const _accessTokenKey = 'nest_access_token';
  static const _refreshTokenKey = 'nest_refresh_token';

  /// Get the underlying Dio instance (for advanced use cases)
  Dio get dio => _dio;

  /// Check if user is currently authenticated (has valid token stored)
  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Get the stored access token
  Future<String?> getAccessToken() async {
    return await storage.read(key: _accessTokenKey);
  }

  /// Get the stored refresh token
  Future<String?> getRefreshToken() async {
    return await storage.read(key: _refreshTokenKey);
  }

  /// Store authentication tokens
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    logger.debug('NestApiClient: Tokens saved successfully');
  }

  /// Clear stored tokens (logout)
  Future<void> clearTokens() async {
    await storage.delete(key: _accessTokenKey);
    await storage.delete(key: _refreshTokenKey);
    logger.debug('NestApiClient: Tokens cleared');
  }

  /// Create base Dio options
  BaseOptions _createBaseOptions() {
    return BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
  }

  /// Setup Dio interceptors for auth and error handling
  void _setupInterceptors() {
    // Auth interceptor - attach JWT to requests
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Skip auth header for login/register endpoints
          final isAuthEndpoint = options.path.contains('/auth/login') ||
              options.path.contains('/auth/register');

          if (!isAuthEndpoint) {
            final token = await getAccessToken();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }

          logger.debug(
            'NestApiClient: ${options.method} ${options.path}',
          );
          handler.next(options);
        },
        onResponse: (response, handler) {
          logger.debug(
            'NestApiClient: Response ${response.statusCode} '
            'for ${response.requestOptions.path}',
          );
          handler.next(response);
        },
        onError: (error, handler) async {
          logger.error(
            'NestApiClient: Error ${error.response?.statusCode} '
            'for ${error.requestOptions.path}: ${error.message}',
          );

          // Handle 401 Unauthorized - token expired
          if (error.response?.statusCode == 401) {
            // TODO: Implement token refresh logic if needed
            // For now, just clear tokens and let the app redirect to login
            await clearTokens();
          }

          handler.next(error);
        },
      ),
    );

    // Logging interceptor (debug mode only)
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
          logPrint: (obj) => logger.debug('Dio: $obj'),
        ),
      );
    }
  }

  // ============================================================
  // HTTP Methods with Error Mapping
  // ============================================================

  /// Perform GET request
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
      );
      return _handleResponse(response, parser);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Perform POST request
  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return _handleResponse(response, parser);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Perform PUT request
  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
  }) async {
    try {
      final response = await _dio.put<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return _handleResponse(response, parser);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Perform DELETE request
  Future<T> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic data)? parser,
  }) async {
    try {
      final response = await _dio.delete<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return _handleResponse(response, parser);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Handle response and parse data
  T _handleResponse<T>(Response response, T Function(dynamic)? parser) {
    if (response.data == null) {
      if (null is T) {
        return null as T;
      }
      throw const NestApiException(
        message: 'Empty response from server',
        statusCode: 0,
      );
    }

    if (parser != null) {
      return parser(response.data);
    }

    return response.data as T;
  }

  /// Map Dio errors to app-specific exceptions
  NestApiException _mapDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NestApiException(
          message: 'Connection timeout. Please check your internet connection.',
          statusCode: 0,
          type: NestApiExceptionType.timeout,
        );

      case DioExceptionType.connectionError:
        return const NestApiException(
          message: 'Unable to connect to server. Please check your internet connection.',
          statusCode: 0,
          type: NestApiExceptionType.network,
        );

      case DioExceptionType.badResponse:
        return _mapHttpError(error.response);

      case DioExceptionType.cancel:
        return const NestApiException(
          message: 'Request was cancelled',
          statusCode: 0,
          type: NestApiExceptionType.cancelled,
        );

      default:
        return NestApiException(
          message: error.message ?? 'An unexpected error occurred',
          statusCode: error.response?.statusCode ?? 0,
          type: NestApiExceptionType.unknown,
        );
    }
  }

  /// Map HTTP status codes to specific exceptions
  NestApiException _mapHttpError(Response? response) {
    final statusCode = response?.statusCode ?? 0;
    final data = response?.data;

    // Try to extract error message from response
    String message = 'An error occurred';
    if (data is Map<String, dynamic>) {
      message = data['message']?.toString() ??
          data['error']?.toString() ??
          'An error occurred';
    }

    switch (statusCode) {
      case 400:
        return NestApiException(
          message: message,
          statusCode: statusCode,
          type: NestApiExceptionType.badRequest,
          data: data,
        );

      case 401:
        return NestApiException(
          message: 'Authentication required. Please log in again.',
          statusCode: statusCode,
          type: NestApiExceptionType.unauthorized,
          data: data,
        );

      case 403:
        return NestApiException(
          message: 'Access denied. You do not have permission.',
          statusCode: statusCode,
          type: NestApiExceptionType.forbidden,
          data: data,
        );

      case 404:
        return NestApiException(
          message: 'Resource not found.',
          statusCode: statusCode,
          type: NestApiExceptionType.notFound,
          data: data,
        );

      case 422:
        return NestApiException(
          message: message,
          statusCode: statusCode,
          type: NestApiExceptionType.validation,
          data: data,
        );

      case 500:
      case 502:
      case 503:
        return NestApiException(
          message: 'Server error. Please try again later.',
          statusCode: statusCode,
          type: NestApiExceptionType.server,
          data: data,
        );

      default:
        return NestApiException(
          message: message,
          statusCode: statusCode,
          type: NestApiExceptionType.unknown,
          data: data,
        );
    }
  }

  /// Update the base URL (e.g., for environment switching)
  void updateBaseUrl(String newBaseUrl) {
    _dio.options.baseUrl = newBaseUrl;
    logger.debug('NestApiClient: Base URL updated to $newBaseUrl');
  }
}

