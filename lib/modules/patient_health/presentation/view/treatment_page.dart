import 'package:flutter/material.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/services/notification/notification_service.dart';
import 'package:thingsboard_app/core/services/notification/task_notification_helper.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
import 'package:thingsboard_app/modules/patient_health/di/patient_health_di.dart';
import 'package:thingsboard_app/widgets/tb_app_bar.dart';

/// PATIENT APP: Treatment Plan Page
///
/// Displays daily tasks for the patient's treatment plan.
/// Tasks include medications, measurements, exercises, and appointments.

class TreatmentPage extends TbContextWidget {
  TreatmentPage(super.tbContext, {super.key});

  @override
  State<StatefulWidget> createState() => _TreatmentPageState();
}

class _TreatmentPageState extends TbContextState<TreatmentPage>
    with AutomaticKeepAliveClientMixin<TreatmentPage> {
  final _diScopeKey = UniqueKey();
  List<TaskEntity> _tasks = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Initialize Patient Health module DI if not already initialized
    if (!getIt.hasScope(_diScopeKey.toString())) {
      PatientHealthDi.init(
        _diScopeKey.toString(),
        tbClient: widget.tbContext.tbClient,
        logger: getIt(),
      );
    }

    // Request notification permissions when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermissions();
      _loadDailyTasks();
    });
  }

  Future<void> _requestNotificationPermissions() async {
    try {
      final notificationService = getIt<INotificationService>();
      await notificationService.requestPermissions();
    } catch (e, s) {
      final logger = getIt<TbLogger>();
      logger.warn(
        'TreatmentPage: Error requesting notification permissions',
        e,
        s,
      );
    }
  }

  Future<void> _loadDailyTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = getIt<IPatientRepository>();
      final tasks = await repository.getDailyTasks();
      
      // Schedule notifications for incomplete tasks
      try {
        final notificationService = getIt<INotificationService>();
        final logger = getIt<TbLogger>();
        final notificationHelper = TaskNotificationHelper(
          notificationService: notificationService,
          logger: logger,
        );
        await notificationHelper.scheduleTaskNotifications(tasks);
      } catch (e, s) {
        // Log but don't fail the entire task loading if notification scheduling fails
        final logger = getIt<TbLogger>();
        logger.warn(
          'TreatmentPage: Error scheduling notifications',
          e,
          s,
        );
      }
      
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e, s) {
      final logger = getIt<TbLogger>();
      logger.error('TreatmentPage: Error loading daily tasks', e, s);
      setState(() {
        _errorMessage = 'Failed to load daily tasks: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleTaskCompletion(TaskEntity task) async {
    // Update task completion status
    final updatedTask = task.copyWith(isCompleted: !task.isCompleted);
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = updatedTask;
      }
    });

    // TODO: In production, this would save to the backend
    // For now, we just update the local state
  }

  @override
  void dispose() {
    // Only dispose if we created the scope
    if (getIt.hasScope(_diScopeKey.toString())) {
      PatientHealthDi.dispose(_diScopeKey.toString());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: TbAppBar(
        tbContext,
        title: const Text(
          'Treatment Plan',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDailyTasks,
            tooltip: 'Refresh tasks',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your treatment plan...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDailyTasks,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.checklist,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No tasks scheduled for today',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your healthcare provider will add tasks here.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDailyTasks,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tasks.length,
        itemBuilder: (context, index) {
          final task = _tasks[index];
          return _buildTaskCard(task);
        },
      ),
    );
  }

  Widget _buildTaskCard(TaskEntity task) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: CheckboxListTile(
        value: task.isCompleted,
        onChanged: (value) => _toggleTaskCompletion(task),
        title: Text(
          task.displayTitle,
          style: TextStyle(
            decoration: task.isCompleted
                ? TextDecoration.lineThrough
                : TextDecoration.none,
            color: task.isCompleted ? Colors.grey : null,
            fontWeight: task.isCompleted ? FontWeight.normal : FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  _getTaskTypeIcon(task.type),
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                // Time with alarm icon - prominently displayed
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.alarm,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      task.time,
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getTaskTypeColor(task.type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    task.type.displayName,
                    style: TextStyle(
                      color: _getTaskTypeColor(task.type),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (task.description != null) ...[
              const SizedBox(height: 4),
              Text(
                task.description!,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getTaskTypeColor(task.type).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getTaskTypeIcon(task.type),
            color: _getTaskTypeColor(task.type),
            size: 24,
          ),
        ),
        activeColor: _getTaskTypeColor(task.type),
      ),
    );
  }

  IconData _getTaskTypeIcon(TaskType type) {
    switch (type) {
      case TaskType.medication:
        return Icons.medication;
      case TaskType.measurement:
        return Icons.monitor_heart;
      case TaskType.exercise:
        return Icons.fitness_center;
      case TaskType.appointment:
        return Icons.event;
      case TaskType.other:
        return Icons.check_circle;
    }
  }

  Color _getTaskTypeColor(TaskType type) {
    switch (type) {
      case TaskType.medication:
        return Colors.blue;
      case TaskType.measurement:
        return Colors.red;
      case TaskType.exercise:
        return Colors.green;
      case TaskType.appointment:
        return Colors.orange;
      case TaskType.other:
        return Colors.grey;
    }
  }
}
