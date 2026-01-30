import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/services/notification/notification_service.dart';
import 'package:thingsboard_app/core/services/notification/task_notification_helper.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/task_entity.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
import 'package:thingsboard_app/modules/patient_health/di/patient_health_di.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_event.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_state.dart';
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

      // Sync loaded tasks to bloc if available (in next frame when bloc is ready)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final bloc = context.read<PatientBloc>();
          bloc.add(PatientLoadTasksEvent(tasks: tasks));
        } catch (e) {
          // Bloc might not be available yet, that's okay
        }
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

    return BlocProvider<PatientBloc>(
      create: (_) => PatientBloc(
        repository: getIt<IPatientRepository>(),
        logger: getIt<TbLogger>(),
      ),
      child: BlocListener<PatientBloc, PatientState>(
        listener: (context, state) {
          if (state is PatientTasksLoadedState) {
            setState(() {
              _tasks = state.tasks;
            });
          }
        },
        child: Scaffold(
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
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddTaskBottomSheet(context),
            backgroundColor: Theme.of(context).primaryColor,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _showAddTaskBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => AddTaskBottomSheet(
        onTaskAdded: (task) {
          // Dispatch event to bloc
          context.read<PatientBloc>().add(PatientAddTaskEvent(task: task));
          // Also add to local state immediately for instant UI update
          setState(() {
            _tasks = [..._tasks, task];
          });
          Navigator.pop(context);
        },
      ),
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

/// Bottom sheet widget for adding a new task/reminder
class AddTaskBottomSheet extends StatefulWidget {
  const AddTaskBottomSheet({
    super.key,
    required this.onTaskAdded,
  });

  final Function(TaskEntity) onTaskAdded;

  @override
  State<AddTaskBottomSheet> createState() => _AddTaskBottomSheetState();
}

class _AddTaskBottomSheetState extends State<AddTaskBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _taskNameController = TextEditingController();
  TaskType _selectedType = TaskType.medication;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);

  @override
  void dispose() {
    _taskNameController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _saveTask() {
    if (_formKey.currentState!.validate()) {
      // Generate a random ID for the new task
      final random = Random();
      final taskId = 'user_task_${random.nextInt(1000000)}';

      // Create the task entity
      final task = TaskEntity(
        id: taskId,
        title: _taskNameController.text.trim(),
        time: _formatTime(_selectedTime),
        type: _selectedType,
        isCompleted: false,
      );

      // Call the callback
      widget.onTaskAdded(task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: mediaQuery.viewInsets.bottom + 
                mediaQuery.padding.bottom + 
                16, // Extra space for system navigation buttons
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              const Text(
                'New Reminder',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // Task Name TextField
              TextFormField(
                controller: _taskNameController,
                decoration: const InputDecoration(
                  labelText: 'Task Name',
                  hintText: 'e.g., Take Vitamin D',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Type Selection (Chips)
              const Text(
                'Type',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: TaskType.values.map((type) {
                  final isSelected = _selectedType == type;
                  return FilterChip(
                    label: Text(type.displayName),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedType = type;
                        });
                      }
                    },
                    selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
                    checkmarkColor: Theme.of(context).primaryColor,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey[700],
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Time Picker Row
              InkWell(
                onTap: _selectTime,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.orange),
                      const SizedBox(width: 12),
                      const Text(
                        'Time:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatTime(_selectedTime),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Save Button
              ElevatedButton(
                onPressed: _saveTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
