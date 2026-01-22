import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:thingsboard_app/constants/database_keys.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/thingsboard_client.dart';

/// PATIENT APP: Biometric Authentication Service
///
/// Provides biometric authentication (Face ID, Touch ID, Fingerprint) for HIPAA compliance.
/// Handles hardware checks, authentication prompts, and preference storage.

class BiometricService {
  BiometricService({
    required this.storage,
    required this.logger,
  }) : _localAuth = LocalAuthentication();

  final TbStorage storage;
  final TbLogger logger;
  final LocalAuthentication _localAuth;

  /// Check if biometric authentication is available on the device
  Future<bool> isBiometricAvailable() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      
      logger.debug(
        'BiometricService: isAvailable=$isAvailable, isDeviceSupported=$isDeviceSupported',
      );
      
      return isAvailable || isDeviceSupported;
    } catch (e, s) {
      logger.error('BiometricService: Error checking biometric availability', e, s);
      return false;
    }
  }

  /// Get available biometric types (Face ID, Touch ID, Fingerprint, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e, s) {
      logger.error('BiometricService: Error getting available biometrics', e, s);
      return [];
    }
  }

  /// Trigger biometric authentication prompt
  /// Returns true if authentication succeeds, false otherwise
  Future<bool> authenticate({
    String reason = 'Please authenticate to continue',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    try {
      // Check if biometrics are available first
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        logger.warn('BiometricService: Biometrics not available on this device');
        return false;
      }

      // Configure authentication options
      final options = const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: true,
      );

      // Trigger authentication
      // Note: Platform-specific messages are handled automatically by local_auth
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: options,
      );

      logger.debug('BiometricService: Authentication result: $didAuthenticate');
      return didAuthenticate;
    } on PlatformException catch (e, s) {
      // Handle platform-specific errors
      if (e.code == 'no_fragment_activity') {
        logger.error(
          'BiometricService: Android MainActivity must extend FlutterFragmentActivity. '
          'Please update MainActivity.kt to extend FlutterFragmentActivity()',
          e,
          s,
        );
      } else {
        logger.error('BiometricService: Platform error during authentication', e, s);
      }
      return false;
    } catch (e, s) {
      logger.error('BiometricService: Error during authentication', e, s);
      return false;
    }
  }

  /// Check if biometric authentication is enabled in user preferences
  Future<bool> isBiometricEnabled() async {
    try {
      final enabled = await storage.getItem(DatabaseKeys.biometricEnabled) as bool?;
      return enabled ?? false;
    } catch (e, s) {
      logger.error('BiometricService: Error reading biometric preference', e, s);
      return false;
    }
  }

  /// Save biometric enabled preference
  Future<void> setBiometricEnabled(bool isEnabled) async {
    try {
      await storage.setItem(DatabaseKeys.biometricEnabled, isEnabled);
      logger.debug('BiometricService: Biometric enabled set to $isEnabled');
    } catch (e, s) {
      logger.error('BiometricService: Error saving biometric preference', e, s);
      rethrow;
    }
  }

  /// Stop authentication (if in progress)
  Future<void> stopAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } catch (e, s) {
      logger.error('BiometricService: Error stopping authentication', e, s);
    }
  }
}
