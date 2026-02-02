import 'package:flutter/services.dart';
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

  /// Show an immediate notification (for testing)
  /// This bypasses scheduling and shows the notification right away
  Future<void> showImmediateNotification(
    int id,
    String title,
    String body,
  );
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
      
      // Get the device's actual timezone offset
      final deviceOffset = DateTime.now().timeZoneOffset;
      final offsetHours = deviceOffset.inHours;
      
      logger.debug(
        'LocalNotificationService: Device timezone offset - ${offsetHours} hours',
      );
      
      // Try to find a timezone location that matches the device's offset
      // Common timezones for GMT+3: Europe/Istanbul, Africa/Nairobi, Asia/Baghdad, etc.
      String? timezoneName;
      if (offsetHours == 3) {
        // GMT+3 - try common locations
        final candidates = ['Europe/Istanbul', 'Africa/Nairobi', 'Asia/Baghdad', 'Europe/Moscow'];
        for (final candidate in candidates) {
          try {
            final location = tz.getLocation(candidate);
            final now = tz.TZDateTime.now(location);
            final locationOffset = now.timeZoneOffset.inHours;
            if (locationOffset == offsetHours) {
              timezoneName = candidate;
              break;
            }
          } catch (_) {
            continue;
          }
        }
      }
      
      // If we found a matching timezone, use it; otherwise use UTC and adjust manually
      if (timezoneName != null) {
        final location = tz.getLocation(timezoneName);
        tz.setLocalLocation(location);
        logger.debug(
          'LocalNotificationService: Timezone set to - $timezoneName (offset: ${offsetHours}h)',
        );
      } else {
        // Fallback: Use UTC and we'll handle offset manually in scheduling
        tz.setLocalLocation(tz.getLocation('UTC'));
        logger.debug(
          'LocalNotificationService: Using UTC as base (will adjust for ${offsetHours}h offset)',
        );
      }

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
        
        // Create notification channel for Android (required for Android 8.0+)
        try {
          final androidPlatform = _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>();
          if (androidPlatform != null) {
            // Create the notification channel
            const androidChannel = AndroidNotificationChannel(
              'task_reminders',
              'Task Reminders',
              description: 'Notifications for daily treatment plan tasks',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            );
            
            await androidPlatform.createNotificationChannel(androidChannel);
            logger.debug(
              'LocalNotificationService: Notification channel created - task_reminders',
            );
            
            // Request exact alarms permission for Android 12+ (API 31+)
            // This is required for scheduling exact-time notifications
            try {
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
            } catch (e) {
              // Method may not exist in older plugin versions - this is okay
              logger.debug(
                'LocalNotificationService: Exact alarms permission request not available: $e',
              );
            }
          }
        } catch (e, s) {
          logger.error(
            'LocalNotificationService: Error creating notification channel',
            e,
            s,
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
    logger.debug(
      'LocalNotificationService: scheduleTaskReminder called - '
      'ID: $id, Title: $title, ScheduledTime: $scheduledTime',
    );

    if (!_isInitialized) {
      logger.warn(
        'LocalNotificationService: Not initialized. Call init() first.',
      );
      return;
    }

    try {
      // Get device's actual timezone offset
      final deviceOffset = DateTime.now().timeZoneOffset;
      final offsetHours = deviceOffset.inHours;
      
      // Get the current local timezone location
      final localLocation = tz.local;
      final now = tz.TZDateTime.now(localLocation);
      
      // CRITICAL: DateTime objects in Dart are timezone-naive (they represent local time)
      // When we create a TZDateTime, we need to interpret the DateTime components
      // as being in the device's local timezone, not UTC
      
      // If the timezone location is UTC but device is GMT+3, we need to adjust
      // scheduledTime is in local time (GMT+3), so if tz.local is UTC, we need to
      // subtract the offset to get the UTC equivalent
      tz.TZDateTime tzDateTime;
      
      if (localLocation.name == 'UTC' && offsetHours != 0) {
        // Timezone is UTC but device is not - we need to convert local time to UTC
        // scheduledTime is in local time, so subtract the offset to get UTC
        final utcTime = scheduledTime.subtract(deviceOffset);
        tzDateTime = tz.TZDateTime(
          localLocation, // UTC
          utcTime.year,
          utcTime.month,
          utcTime.day,
          utcTime.hour,
          utcTime.minute,
          utcTime.second,
          utcTime.millisecond,
          utcTime.microsecond,
        );
        logger.debug(
          'LocalNotificationService: Converted local time to UTC - '
          'Local: $scheduledTime, UTC: $utcTime, Offset: ${offsetHours}h',
        );
      } else {
        // Timezone location matches device, use scheduledTime directly
        tzDateTime = tz.TZDateTime(
          localLocation,
          scheduledTime.year,
          scheduledTime.month,
          scheduledTime.day,
          scheduledTime.hour,
          scheduledTime.minute,
          scheduledTime.second,
          scheduledTime.millisecond,
          scheduledTime.microsecond,
        );
      }
      
      // Verify the timezone is correct
      final timezoneName = localLocation.name;
      final timezoneOffset = tzDateTime.timeZoneOffset;
      final actualDelay = tzDateTime.difference(now).inSeconds;
      final expectedDelay = scheduledTime.difference(DateTime.now()).inSeconds;
      
      logger.debug(
        'LocalNotificationService: Time conversion - '
        'Timezone: $timezoneName (offset: ${timezoneOffset.inHours}h), '
        'Device offset: ${offsetHours}h, '
        'Now: $now, '
        'Scheduled DateTime (local): $scheduledTime, '
        'TZDateTime: $tzDateTime, '
        'Expected delay: ${expectedDelay}s, Actual delay: ${actualDelay}s',
      );
      
      // Sanity check: if the difference is way off, there's a timezone issue
      if ((actualDelay - expectedDelay).abs() > 60) {
        logger.error(
          'LocalNotificationService: ❌ TIMEZONE MISMATCH! '
          'Expected delay: ${expectedDelay}s (${(expectedDelay / 60).toStringAsFixed(1)} min), '
          'Actual delay: ${actualDelay}s (${(actualDelay / 60).toStringAsFixed(1)} min). '
          'Difference: ${(actualDelay - expectedDelay).abs()}s. '
          'This will cause notifications to fire at the wrong time!',
        );
      }

      // Don't schedule notifications in the past
      if (tzDateTime.isBefore(now)) {
        logger.warn(
          'LocalNotificationService: Skipping past notification - '
          'ID: $id, ScheduledTime: $scheduledTime, '
          'TZDateTime: $tzDateTime, Now: $now',
        );
        return;
      }

      // Check permissions before scheduling
      final androidInfo = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidInfo != null) {
        final hasPermission = await androidInfo.areNotificationsEnabled();
        logger.debug(
          'LocalNotificationService: Android notifications enabled: $hasPermission',
        );
        
        if (hasPermission != true) {
          logger.warn(
            'LocalNotificationService: Android notifications are disabled. '
            'Please enable in system settings.',
          );
        }
        
        // Check exact alarms permission (Android 12+)
        try {
          // Check if we can schedule exact alarms
          final canScheduleExact = await androidInfo.canScheduleExactNotifications();
          logger.debug(
            'LocalNotificationService: Can schedule exact notifications: $canScheduleExact',
          );
          
          if (canScheduleExact != true) {
            logger.warn(
              'LocalNotificationService: Exact alarms permission not granted. '
              'Notifications may not fire at exact times.',
            );
          }
        } catch (e) {
          logger.debug(
            'LocalNotificationService: Cannot check exact alarms permission: $e',
          );
        }
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

      logger.debug(
        'LocalNotificationService: Creating notification channel - '
        'Channel ID: task_reminders',
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

      logger.debug(
        'LocalNotificationService: Calling zonedSchedule - '
        'ID: $id, TZDateTime: $tzDateTime, '
        'Mode: exactAllowWhileIdle',
      );

      // Schedule the notification (one-time, not repeating)
      // Tasks are reloaded daily, so notifications will be rescheduled
      try {
        // For very short delays (< 1 minute), also show immediately as a test
        final secondsUntilNotification = tzDateTime.difference(now).inSeconds;
        if (secondsUntilNotification < 60) {
          logger.debug(
            'LocalNotificationService: Short delay detected (${secondsUntilNotification}s). '
            'This might be suppressed by Android when app is in foreground.',
          );
        }

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
          'LocalNotificationService: ✅ Successfully scheduled notification - '
          'ID: $id, Title: $title, ScheduledTime: $scheduledTime, '
          'TZDateTime: $tzDateTime, Will fire in: ${secondsUntilNotification}s, '
          'Current timezone: ${tz.local.name}',
        );
        
        // Verify the notification was actually scheduled (Android only)
        if (androidInfo != null) {
          try {
            final pendingNotifications = await _notificationsPlugin.pendingNotificationRequests();
            final ourNotification = pendingNotifications.firstWhere(
              (n) => n.id == id,
              orElse: () => throw StateError('Not found'),
            );
            logger.debug(
              'LocalNotificationService: ✅ Verified notification in pending list - '
              'ID: ${ourNotification.id}, Title: ${ourNotification.title}, '
              'Body: ${ourNotification.body}',
            );
          } catch (e) {
            logger.warn(
              'LocalNotificationService: ⚠️ Could not verify notification in pending list - $e',
            );
          }
        }
        
        // Log a reminder about foreground suppression
        if (secondsUntilNotification < 60) {
          logger.debug(
            'LocalNotificationService: ⚠️ IMPORTANT: Android often suppresses scheduled '
            'notifications when the app is in the foreground. To test: '
            '1. Schedule the notification, 2. Minimize/close the app, 3. Wait for the time.',
          );
        }
      } on PlatformException catch (e) {
        // If exact alarms fail, try with inexact scheduling as fallback
        logger.warn(
          'LocalNotificationService: Exact scheduling failed: ${e.code} - ${e.message}. '
          'Trying inexact scheduling as fallback.',
        );
        
        try {
          await _notificationsPlugin.zonedSchedule(
            id,
            title,
            body,
            tzDateTime,
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          logger.debug(
            'LocalNotificationService: ✅ Scheduled with inexact mode (fallback)',
          );
        } catch (fallbackError) {
          logger.error(
            'LocalNotificationService: Fallback scheduling also failed',
            fallbackError,
          );
          rethrow;
        }
      }
    } catch (e, s) {
      logger.error(
        'LocalNotificationService: ❌ Error scheduling notification - '
        'ID: $id, Title: $title, Error: $e',
        e,
        s,
      );
      
      // Log additional details for common errors
      if (e.toString().contains('exact_alarms')) {
        logger.error(
          'LocalNotificationService: Exact alarms permission issue. '
          'Check if SCHEDULE_EXACT_ALARM permission is granted.',
        );
      } else if (e.toString().contains('permission')) {
        logger.error(
          'LocalNotificationService: Permission issue. '
          'Check if notification permissions are granted.',
        );
      }
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

  @override
  Future<void> showImmediateNotification(
    int id,
    String title,
    String body,
  ) async {
    logger.debug(
      'LocalNotificationService: showImmediateNotification called - '
      'ID: $id, Title: $title',
    );

    if (!_isInitialized) {
      logger.warn(
        'LocalNotificationService: Not initialized. Call init() first.',
      );
      return;
    }

    try {
      // Android notification details
      const androidDetails = AndroidNotificationDetails(
        'task_reminders',
        'Task Reminders',
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

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show notification immediately
      await _notificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
      );

      logger.debug(
        'LocalNotificationService: ✅ Immediate notification shown - '
        'ID: $id, Title: $title',
      );
    } catch (e, s) {
      logger.error(
        'LocalNotificationService: ❌ Error showing immediate notification - '
        'ID: $id, Error: $e',
        e,
        s,
      );
      rethrow;
    }
  }
}
