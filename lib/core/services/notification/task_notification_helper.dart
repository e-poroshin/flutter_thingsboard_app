import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/services/notification/notification_service.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';

/// PATIENT APP: Task Notification Helper
///
/// Helper service to schedule notifications for treatment plan tasks.
/// This bridges the gap between TaskEntity (domain) and NotificationService (infrastructure).
class TaskNotificationHelper {
  TaskNotificationHelper({
    required this.notificationService,
    required this.logger,
  });

  final INotificationService notificationService;
  final TbLogger logger;

  /// Schedule notifications for all incomplete tasks that are in the future
  /// [tasks] - List of tasks from the treatment plan
  /// 
  /// This method:
  /// 1. Cancels all existing notifications (to avoid duplicates)
  /// 2. Filters tasks that are NOT completed and are in the future
  /// 3. Parses the task time string (e.g., "08:00 AM") to DateTime
  /// 4. Schedules a notification for each task
  Future<void> scheduleTaskNotifications(List<TaskEntity> tasks) async {
    try {
      // Cancel all existing notifications first (to avoid duplicates when reloading)
      await notificationService.cancelAll();
      logger.debug(
        'TaskNotificationHelper: Cancelled all existing notifications',
      );

      // Filter tasks: only schedule incomplete tasks that are in the future
      final tasksToSchedule = tasks.where((task) {
        if (task.isCompleted) {
          logger.debug(
            'TaskNotificationHelper: Skipping completed task - ${task.id}',
          );
          return false;
        }

        final scheduledTime = _parseTaskTime(task.time);
        if (scheduledTime == null) {
          logger.warn(
            'TaskNotificationHelper: Could not parse time for task - '
            '${task.id}, time: ${task.time}',
          );
          return false;
        }

        // Only schedule if the time is in the future
        if (scheduledTime.isBefore(DateTime.now())) {
          logger.debug(
            'TaskNotificationHelper: Skipping past task - ${task.id}, '
            'time: ${task.time}',
          );
          return false;
        }

        return true;
      }).toList();

      logger.debug(
        'TaskNotificationHelper: Scheduling ${tasksToSchedule.length} '
        'notifications out of ${tasks.length} tasks',
      );

      // Schedule notifications for each task
      for (final task in tasksToSchedule) {
        final scheduledTime = _parseTaskTime(task.time);
        if (scheduledTime == null) continue;

        // Convert task ID to int for notification ID
        // Use a hash of the task ID to ensure uniqueness
        final notificationId = _taskIdToNotificationId(task.id);

        // Build notification title and body
        final title = task.displayTitle;
        final body = _buildNotificationBody(task);

        await notificationService.scheduleTaskReminder(
          notificationId,
          title,
          body,
          scheduledTime,
        );
      }

      logger.debug(
        'TaskNotificationHelper: Successfully scheduled all task notifications',
      );
    } catch (e, s) {
      logger.error(
        'TaskNotificationHelper: Error scheduling task notifications',
        e,
        s,
      );
    }
  }

  /// Parse task time string (e.g., "08:00 AM") to DateTime for today
  /// Returns null if parsing fails
  DateTime? _parseTaskTime(String timeString) {
    try {
      // Parse formats like "08:00 AM", "8:00 PM", "10:30 AM"
      final timeRegex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
      final match = timeRegex.firstMatch(timeString.trim());

      if (match == null) {
        logger.warn(
          'TaskNotificationHelper: Could not parse time format - $timeString',
        );
        return null;
      }

      var hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final period = match.group(3)!.toUpperCase();

      // Convert to 24-hour format
      if (period == 'PM' && hour != 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }

      // Create DateTime for today at the specified time
      final now = DateTime.now();
      final scheduledTime = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      return scheduledTime;
    } catch (e, s) {
      logger.error(
        'TaskNotificationHelper: Error parsing time - $timeString',
        e,
        s,
      );
      return null;
    }
  }

  /// Convert task ID string to int notification ID
  /// Uses hash code to ensure uniqueness
  int _taskIdToNotificationId(String taskId) {
    // Use hash code, but ensure it's positive (notification IDs must be positive)
    final hash = taskId.hashCode;
    return hash.abs() % 2147483647; // Max int32 value
  }

  /// Build notification body text from task
  String _buildNotificationBody(TaskEntity task) {
    final parts = <String>[];

    // Add task type
    parts.add('${task.type.displayName}');

    // Add description if available
    if (task.description != null && task.description!.isNotEmpty) {
      parts.add(task.description!);
    }

    // Add medication info if applicable
    if (task.type == TaskType.medication && task.formattedMedication != null) {
      parts.add('Dosage: ${task.formattedMedication}');
    }

    return parts.join(' • ');
  }
}
