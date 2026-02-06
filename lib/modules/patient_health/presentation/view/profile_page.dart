import 'package:flutter/material.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/security/biometric_service.dart';
import 'package:thingsboard_app/core/services/notification/notification_service.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/patient_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/view/sensor_scan_page.dart';
import 'package:thingsboard_app/widgets/tb_app_bar.dart';

/// PATIENT APP: Profile Page
///
/// Displays user information, app settings, and logout functionality.
/// This replaces the legacy Notifications tab.

class ProfilePage extends TbContextWidget {
  ProfilePage(super.tbContext, {super.key});

  @override
  State<StatefulWidget> createState() => _ProfilePageState();
}

class _ProfilePageState extends TbContextState<ProfilePage>
    with AutomaticKeepAliveClientMixin<ProfilePage> {
  PatientEntity? _patientProfile;
  bool _isLoading = true;
  bool _faceIdEnabled = false;
  bool _darkModeEnabled = false;
  late BiometricService _biometricService;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Initialize biometric service
    _biometricService = BiometricService(
      storage: getIt(),
      logger: getIt(),
    );

    // No local DI scope — uses the global scope from ThingsboardApp.initState

    // Load patient profile and biometric preference when page initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPatientProfile();
      _loadBiometricPreference();
    });
  }

  Future<void> _loadBiometricPreference() async {
    try {
      final enabled = await _biometricService.isBiometricEnabled();
      setState(() {
        _faceIdEnabled = enabled;
      });
    } catch (e) {
      final logger = getIt<TbLogger>();
      logger.error('ProfilePage: Error loading biometric preference', e);
    }
  }

  Future<void> _loadPatientProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final repository = getIt<IPatientRepository>();
      final profile = await repository.getPatientProfile();
      setState(() {
        _patientProfile = profile;
        _isLoading = false;
      });
    } catch (e, s) {
      final logger = getIt<TbLogger>();
      logger.error('ProfilePage: Error loading patient profile', e, s);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Call TbContext logout - this handles token clearing and navigation
      await widget.tbContext.logout(notifyUser: true);
    }
  }

  @override
  void dispose() {
    // No local DI scope to dispose — global scope is managed by ThingsboardApp
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: TbAppBar(
        tbContext,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // User Info Header
          _buildUserHeader(),
          const SizedBox(height: 16),

          // Devices Section
          _buildDevicesSection(),

          const SizedBox(height: 16),

          // Settings Section
          _buildSettingsSection(),

          const SizedBox(height: 24),

          // Logout Button
          _buildLogoutButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildUserHeader() {
    final patient = _patientProfile;
    final name = patient?.fullName ?? 'Patient';
    // Use patient email from profile, or fallback to userDetails if available
    final email = patient?.email ?? 
        widget.tbContext.userDetails?.email ?? 
        'No email';
    
    // Get initials from name
    final initials = _getInitials(name);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Theme.of(context).primaryColor,
            child: patient?.avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      patient!.avatarUrl!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildInitialsAvatar(initials);
                      },
                    ),
                  )
                : _buildInitialsAvatar(initials),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          if (patient?.phoneNumber != null) ...[
            const SizedBox(height: 8),
            Text(
              patient!.phoneNumber!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(String initials) {
    return Text(
      initials,
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Widget _buildDevicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Devices',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: ListTile(
            leading: const Icon(Icons.bluetooth_searching, color: Colors.blue),
            title: const Text('Connect Health Sensor'),
            subtitle: const Text('Pair Xiaomi LYWSD03MMC or other BLE devices'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SensorScanPage(widget.tbContext),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Enable Face ID'),
                subtitle: const Text('Use biometric authentication'),
                value: _faceIdEnabled,
                onChanged: _handleBiometricToggle,
                secondary: const Icon(Icons.face),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Switch to dark theme'),
                value: _darkModeEnabled,
                onChanged: (value) {
                  setState(() {
                    _darkModeEnabled = value;
                  });
                  // TODO: Implement dark mode toggle logic
                },
                secondary: const Icon(Icons.dark_mode),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Test Notification'),
                subtitle: const Text('Test notification (5s delay)'),
                leading: const Icon(Icons.notifications_active, color: Colors.blue),
                trailing: const Icon(Icons.chevron_right),
                onTap: _testNotification,
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Help & Support'),
                subtitle: const Text('Get help and contact support'),
                leading: const Icon(Icons.help_outline),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: Navigate to help & support page
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Help & Support coming soon'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _handleLogout,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout, size: 20),
              SizedBox(width: 8),
              Text(
                'Log Out',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle biometric toggle with authentication requirement
  Future<void> _handleBiometricToggle(bool value) async {
    if (value) {
      // User wants to enable biometrics - require authentication first
      final isAvailable = await _biometricService.isBiometricAvailable();
      
      if (!isAvailable) {
        // Show error if biometrics not available
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Biometric authentication is not available on this device.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Trigger authentication
      final authenticated = await _biometricService.authenticate(
        reason: 'Enable biometric authentication to secure your health data',
      );

      if (authenticated) {
        // Authentication successful - save preference
        await _biometricService.setBiometricEnabled(true);
        setState(() {
          _faceIdEnabled = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Biometric authentication enabled'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Authentication failed - keep switch off
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication failed. Biometrics not enabled.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else {
      // User wants to disable biometrics - just save preference
      await _biometricService.setBiometricEnabled(false);
      setState(() {
        _faceIdEnabled = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication disabled'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    }
  }

  /// Test notification functionality
  Future<void> _testNotification() async {
    final logger = getIt<TbLogger>();
    final now = DateTime.now();
    final scheduledTime = now.add(const Duration(seconds: 5));
    
    logger.debug(
      'ProfilePage: Test notification requested - '
      'Now: $now, Scheduled: $scheduledTime, '
      'Delay: 5 seconds',
    );
    
    try {
      final notificationService = getIt<INotificationService>();
      
      // Check if service is initialized
      logger.debug('ProfilePage: Notification service retrieved');
      
      // First, test immediate notification to verify channel works
      logger.debug('ProfilePage: Testing immediate notification first...');
      await notificationService.showImmediateNotification(
        998, // Different ID for immediate test
        'Immediate Test',
        'If you see this, notifications work! Scheduled test in 5s...',
      );
      
      // Then schedule a test notification in 5 seconds
      await notificationService.scheduleTaskReminder(
        999, // Test ID
        'Test Notification',
        'This is a test alarm to verify the system works.',
        scheduledTime,
      );

      logger.debug(
        'ProfilePage: ✅ Test notification scheduled successfully - '
        'Will appear at: $scheduledTime',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Immediate test shown! Scheduled test in 5 seconds.\n'
              'Scheduled for: ${scheduledTime.toString().substring(11, 19)}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e, s) {
      logger.error(
        'ProfilePage: ❌ Error scheduling test notification - Error: $e',
        e,
        s,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}
