import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/thingsboard_client.dart';
import 'package:thingsboard_app/utils/services/endpoint/i_endpoint_service.dart';

/// PATIENT APP: Mock Authentication Helper
///
/// Provides mock authentication for UI development when backend is unavailable.
/// Uses the demo ThingsBoard server with demo credentials that have CUSTOMER_USER authority.
/// This allows authentication to work while patient health data comes from mock repositories.

class MockAuthHelper {
  MockAuthHelper._();

  static final _logger = TbLogger();

  /// Perform mock login using demo ThingsBoard server
  ///
  /// This uses the demo ThingsBoard server (https://demo.thingsboard.io) with
  /// demo credentials that have CUSTOMER_USER authority. This allows the app to
  /// authenticate successfully while patient health data comes from mock repositories.
  ///
  /// **Why demo server?**
  /// - ThingsboardClient requires valid JWT tokens, which are difficult to mock
  /// - Demo server provides real authentication with CUSTOMER_USER accounts
  /// - Patient health data still comes from MockPatientRepository
  ///
  /// **Note:** The caller should ensure TbContext is reinitialized if endpoint changes.
  static Future<void> performMockLogin(
    ThingsboardClient tbClient, {
    String? email,
  }) async {
    _logger.debug('MockAuthHelper: Performing mock login via demo server');

    try {
      // Use demo ThingsBoard server for authentication
      const demoEndpoint = 'https://demo.thingsboard.io';
      const demoEmail = 'testclient@thingsboard.io';
      const demoPassword = '1qaz!QAZ';

      // Ensure endpoint is set
      final endpointService = getIt<IEndpointService>();
      final currentEndpoint = await endpointService.getEndpoint();

      if (currentEndpoint != demoEndpoint) {
        _logger.debug('MockAuthHelper: Setting endpoint to $demoEndpoint');
        await endpointService.setEndpoint(demoEndpoint);
        _logger.debug('MockAuthHelper: Endpoint set to demo server');
      }

      // Use the provided email or default to demo email
      // For mock mode, we always use demo credentials regardless of user input
      final loginEmail = demoEmail; // Always use demo email for consistency

      _logger.debug('MockAuthHelper: Logging in as $loginEmail (mock mode)');

      // Perform login with demo credentials
      // These credentials have CUSTOMER_USER authority on the demo server
      await tbClient.login(
        LoginRequest(
          loginEmail,
          demoPassword, // Always use demo password for mock auth
        ),
      );

      _logger.debug('MockAuthHelper: Mock login successful');
    } catch (e, s) {
      _logger.error('MockAuthHelper: Mock login failed', e, s);
      rethrow;
    }
  }
}
