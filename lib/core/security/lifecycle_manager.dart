import 'package:flutter/material.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/security/biometric_service.dart';
import 'package:thingsboard_app/locator.dart';

/// PATIENT APP: App Lifecycle Manager
///
/// Handles app lifecycle events and implements auto-lock with biometric authentication.
/// When the app resumes from background and biometrics are enabled, it requires
/// authentication before allowing access to the app.

class LifecycleManager extends StatefulWidget {
  const LifecycleManager({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<LifecycleManager> createState() => _LifecycleManagerState();
}

class _LifecycleManagerState extends State<LifecycleManager>
    with WidgetsBindingObserver {
  late BiometricService _biometricService;
  bool _isLocked = false;
  bool _isChecking = false;
  final TbLogger _logger = getIt<TbLogger>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _biometricService = BiometricService(
      storage: getIt(),
      logger: _logger,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App came to foreground - check if we need to lock
      _handleAppResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App went to background - we'll lock on resume if biometrics enabled
      _logger.debug('LifecycleManager: App went to background');
    }
  }

  Future<void> _handleAppResumed() async {
    if (_isChecking || _isLocked) return;

    _isChecking = true;

    try {
      // Check if biometrics are enabled
      final isBiometricEnabled = await _biometricService.isBiometricEnabled();
      
      if (!isBiometricEnabled) {
        _isChecking = false;
        return; // No need to lock if biometrics not enabled
      }

      // Check if biometrics are available
      final isAvailable = await _biometricService.isBiometricAvailable();
      
      if (!isAvailable) {
        _logger.warn('LifecycleManager: Biometrics enabled but not available');
        _isChecking = false;
        return;
      }

      // Lock the app and require authentication
      if (mounted) {
        setState(() {
          _isLocked = true;
        });
      }

      _logger.debug('LifecycleManager: App locked, requiring biometric authentication');

      // Trigger authentication
      final authenticated = await _biometricService.authenticate(
        reason: 'Please authenticate to access your health data',
        stickyAuth: true,
      );

      if (authenticated) {
        // Authentication successful - unlock
        // Use post-frame callback to ensure lock screen widgets are properly disposed
        // and the widget tree is stable before rebuilding
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isLocked = false;
              });
              _logger.debug('LifecycleManager: Authentication successful, app unlocked');
            }
          });
        }
      } else {
        // Authentication failed - keep locked
        // Optionally, we could logout here for security
        _logger.warn('LifecycleManager: Authentication failed, app remains locked');
        
        // Note: Cannot use ScaffoldMessenger here because we're outside MaterialApp
        // The lock screen UI itself indicates the locked state
      }
    } catch (e, s) {
      _logger.error('LifecycleManager: Error during app resume handling', e, s);
      // On error, unlock to prevent app from being stuck
      if (mounted) {
        setState(() {
          _isLocked = false;
        });
      }
    } finally {
      _isChecking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return _buildLockScreen();
    }

    return widget.child;
  }

  Widget _buildLockScreen() {
    // Wrap with Directionality and Material to provide necessary context
    // since this is rendered outside MaterialApp
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.black87,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.grey[900]!,
                Colors.black,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                const Text(
                  'App Locked',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please authenticate to continue',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 48),
                ElevatedButton.icon(
                  onPressed: _handleAppResumed,
                  icon: const Icon(Icons.fingerprint, size: 24),
                  label: const Text(
                    'Authenticate',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
