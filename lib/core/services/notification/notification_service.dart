import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';

/// PATIENT APP: Notification Service Interface
///
/// Abstract interface for notification services.
/// This allows easy swapping between Local and Remote (FCM) implementations
/// without changing the display logic.
abstract interface class INotificationService {
  /// Initialize the notification service
  /// Must be called before any other methods
  Future<void> init();

  /// Request notification permissions from the user
  /// Returns true if permissions are granted
  Future<bool> requestPermissions();

  /// Schedule a task reminder notification
  /// [id] - Unique identifier for the notification (use TaskEntity.id)
  /// [title] - Notification title
  /// [body] - Notification body/message
  /// [scheduledTime] - When to show the notification (absolute time)
  Future<void> scheduleTaskReminder(
    int id,
    String title,
    String body,
    DateTime scheduledTime,
  );

  /// Cancel all scheduled notifications
  /// Useful when reloading tasks to avoid duplicates
  Future<void> cancelAll();

  /// Cancel a specific notification by ID
  Future<void> cancel(int id);
}

/// PATIENT APP: Local Notification Service Implementation
///
/// Handles scheduling and displaying local notifications for task reminders.
/// Designed to be easily replaceable with FCM-based remote notifications.
class LocalNotificationService implements INotificationService {
  LocalNotificationService({
    required this.logger,
  });

  final TbLogger logger;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  @override
  Future<void> init() async {
    if (_isInitialized) {
      logger.debug('LocalNotificationService: Already initialized');
      return;
    }

    try {
      // Initialize timezone data (CRUCIAL for scheduled notifications)
      tz.initializeTimeZones();
      
      // Set default timezone to local
      final locationName = tz.local.name;
      tz.setLocalLocation(tz.getLocation(locationName));

      logger.debug(
        'LocalNotificationService: Timezone initialized - $locationName',
      );

      // Android initialization settings
      // Note: Icon name must match android:icon in AndroidManifest.xml
      const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');

      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // Initialize plugin
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final initialized = await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (initialized == true) {
        _isInitialized = true;
        logger.debug('LocalNotificationService: Initialized successfully');
        
        // Request exact alarms permission for Android 12+ (API 31+)
        // This is required for scheduling exact-time notifications
        try {
          final androidPlatform = _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>();
          if (androidPlatform != null) {
            // Request exact alarms permission if available
            // This method may not exist in all plugin versions, so we wrap in try-catch
            final granted = await androidPlatform.requestExactAlarmsPermission();
            if (granted == true) {
              logger.debug(
                'LocalNotificationService: Exact alarms permission granted',
              );
            } else {
              logger.warn(
                'LocalNotificationService: Exact alarms permission denied or not available',
              );
            }
          }
        } catch (e) {
          // Method may not exist in older plugin versions - this is okay
          logger.debug(
            'LocalNotificationService: Exact alarms permission request not available: $e',
          );
        }
      } else {
        logger.warn('LocalNotificationService: Initialization returned false or null');
      }
    } catch (e, s) {
      logger.error('LocalNotificationService: Initialization failed', e, s);
      rethrow;
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    logger.debug(
      'LocalNotificationService: Notification tapped - '
      'ID: ${response.id}, Payload: ${response.payload}',
    );
    // TODO: Navigate to task detail or treatment page
    // This can be handled via a stream or callback if needed
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      // Android 13+ requires POST_NOTIFICATIONS permission
      final isDenied = await Permission.notification.isDenied;
      if (isDenied) {
        final status = await Permission.notification.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          logger.warn(
            'LocalNotificationService: Notification permission denied',
          );
          return false;
        }
      }

      // iOS permissions are requested during initialization
      // Additional check for iOS if needed
      final androidInfo = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidInfo != null) {
        final granted = await androidInfo.requestNotificationsPermission();
        if (granted != true) {
          logger.warn(
            'LocalNotificationService: Android notification permission denied',
          );
          return false;
        }
      }

      logger.debug('LocalNotificationService: Permissions granted');
      return true;
    } catch (e, s) {
      logger.error(
        'LocalNotificationService: Error requesting permissions',
        e,
        s,
      );
      return false;
    }
  }

  @override
  Future<void> scheduleTaskReminder(
    int id,
    String title,
    String body,
    DateTime scheduledTime,
  ) async {
    if (!_isInitialized) {
      logger.warn(
        'LocalNotificationService: Not initialized. Call init() first.',
      );
      return;
    }

    try {
      // Convert DateTime to TZDateTime (CRUCIAL for accurate scheduling)
      final tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);

      // Don't schedule notifications in the past
      if (tzDateTime.isBefore(tz.TZDateTime.now(tz.local))) {
        logger.debug(
          'LocalNotificationService: Skipping past notification - '
          'ID: $id, Time: $scheduledTime',
        );
        return;
      }

      // Android notification details
      // Note: Icon name must match android:icon in AndroidManifest.xml
      const androidDetails = AndroidNotificationDetails(
        'task_reminders', // Channel ID
        'Task Reminders', // Channel Name
        channelDescription: 'Notifications for daily treatment plan tasks',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/launcher_icon',
      );

      // iOS notification details
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      // Notification details
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Schedule the notification (one-time, not repeating)
      // Tasks are reloaded daily, so notifications will be rescheduled
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzDateTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // Works in Doze mode
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime, // Use absolute time
      );

      logger.debug(
        'LocalNotificationService: Scheduled notification - '
        'ID: $id, Title: $title, Time: $scheduledTime',
      );
    } catch (e, s) {
      logger.error(
        'LocalNotificationService: Error scheduling notification - ID: $id',
        e,
        s,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _notificationsPlugin.cancelAll();
      logger.debug('LocalNotificationService: Cancelled all notifications');
    } catch (e, s) {
      logger.error(
        'LocalNotificationService: Error cancelling all notifications',
        e,
        s,
      );
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
      logger.debug('LocalNotificationService: Cancelled notification - ID: $id');
    } catch (e, s) {
      logger.error(
        'LocalNotificationService: Error cancelling notification - ID: $id',
        e,
        s,
      );
    }
  }
}
