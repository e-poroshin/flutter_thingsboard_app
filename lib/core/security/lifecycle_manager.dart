import 'package:flutter/material.dart';
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
  DateTime? _lastSuccessfulAuth;
  final TbLogger _logger = getIt<TbLogger>();
  
  // Prevent re-locking immediately after successful authentication
  // The biometric dialog causes app to go background/resume, which would trigger re-lock
  static const Duration _authCooldown = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _biometricService = BiometricService(
      storage: getIt(),
      logger: _logger,
    );

    // CRITICAL: Check biometric status on cold start
    // Don't wait for lifecycle events - check immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialBiometricStatus();
    });
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
      // BUT: Skip if we just successfully authenticated (biometric dialog causes background/resume)
      if (_lastSuccessfulAuth != null &&
          DateTime.now().difference(_lastSuccessfulAuth!) < _authCooldown) {
        _logger.debug(
          'LifecycleManager: Skipping re-lock - recent successful authentication '
          '(${DateTime.now().difference(_lastSuccessfulAuth!).inMilliseconds}ms ago)',
        );
        return;
      }
      _handleAppResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App went to background - we'll lock on resume if biometrics enabled
      _logger.debug('LifecycleManager: App went to background');
    }
  }

  /// Check biometric status on app initialization (cold start)
  /// This ensures the lock screen appears even on fresh app launches
  Future<void> _checkInitialBiometricStatus() async {
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
        _logger.warn('LifecycleManager: Biometrics enabled but not available on cold start');
        _isChecking = false;
        return;
      }

      // Lock the app immediately on cold start
      if (mounted) {
        setState(() {
          _isLocked = true;
        });
      }

      _logger.debug('LifecycleManager: App locked on cold start, requiring biometric authentication');

      // Trigger authentication
      await _authenticate();
    } catch (e, s) {
      _logger.error('LifecycleManager: Error during initial biometric check', e, s);
      // On error, don't lock to prevent app from being stuck
      if (mounted) {
        setState(() {
          _isLocked = false;
        });
      }
    } finally {
      _isChecking = false;
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
      await _authenticate();
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

  /// Centralized authentication method
  /// Handles both cold start and resume scenarios
  /// Keeps app locked if authentication fails or is canceled
  /// Can be called multiple times (e.g., when user presses retry button)
  Future<void> _authenticate() async {
    if (!mounted) return;
    
    // Prevent multiple simultaneous authentication attempts
    if (_isChecking) {
      _logger.debug('LifecycleManager: Authentication already in progress');
      return;
    }

    _isChecking = true;

    // Update UI to show loading state
    if (mounted) {
      setState(() {
        // Trigger rebuild to show loading indicator on button
      });
    }

    try {
      final authenticated = await _biometricService.authenticate(
        reason: 'Please authenticate to access your health data',
        stickyAuth: true,
      );

      if (authenticated) {
        // Authentication successful - unlock
        // Record timestamp to prevent immediate re-lock when app resumes from biometric dialog
        _lastSuccessfulAuth = DateTime.now();
        
        // Use post-frame callback to ensure lock screen widgets are properly disposed
        // and the widget tree is stable before rebuilding
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isLocked = false;
                _isChecking = false;
              });
              _logger.debug('LifecycleManager: Authentication successful, app unlocked');
            }
          });
        }
      } else {
        // Authentication failed or canceled - keep locked
        // This allows the user to press "Authenticate" button to try again
        _logger.warn('LifecycleManager: Authentication failed or canceled, app remains locked');
        
        // Ensure we stay locked and allow retry
        if (mounted) {
          setState(() {
            _isLocked = true;
            _isChecking = false;
          });
        }
      }
    } catch (e, s) {
      _logger.error('LifecycleManager: Error during authentication', e, s);
      // On error, keep locked to maintain security but allow retry
      if (mounted) {
        setState(() {
          _isLocked = true;
          _isChecking = false;
        });
      }
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
                  onPressed: _isChecking ? null : _authenticate,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.fingerprint, size: 24),
                  label: Text(
                    _isChecking ? 'Authenticating...' : 'Authenticate',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    disabledBackgroundColor: Colors.grey[300],
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
