import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import 'package:thingsboard_app/modules/patient_health/domain/entities/health_record_entity.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_event.dart';

/// PATIENT APP: Add Symptom Bottom Sheet
///
/// A modal bottom sheet that allows the patient to log subjective data:
/// - Mood (1-5 scale with sentiment icons)
/// - Symptoms (common symptom filter chips)
/// - Optional free-text note
///
/// Dispatches [PatientAddRecordEvent] to the BLoC on save.

class AddSymptomSheet extends StatefulWidget {
  const AddSymptomSheet({super.key});

  @override
  State<AddSymptomSheet> createState() => _AddSymptomSheetState();
}

class _AddSymptomSheetState extends State<AddSymptomSheet> {
  int _selectedMood = 3; // Default to "Okay"
  final Set<String> _selectedSymptoms = {};
  final TextEditingController _noteController = TextEditingController();

  static const _moodIcons = [
    Icons.sentiment_very_dissatisfied,
    Icons.sentiment_dissatisfied,
    Icons.sentiment_neutral,
    Icons.sentiment_satisfied,
    Icons.sentiment_very_satisfied,
  ];

  static const _moodLabels = [
    'Very Bad',
    'Bad',
    'Okay',
    'Good',
    'Great',
  ];

  static const _moodColors = [
    Colors.red,
    Colors.orange,
    Colors.amber,
    Colors.lightGreen,
    Colors.green,
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _onSave() {
    final record = HealthRecordEntity(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      mood: _selectedMood,
      symptoms: _selectedSymptoms.toList(),
      note: _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : null,
    );

    context.read<PatientBloc>().add(
          PatientAddRecordEvent(record: record),
        );

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${record.moodEmoji} Symptom log saved!'),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              'Log Symptoms',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How are you feeling right now?',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),

            // Mood Selector
            Text(
              'Mood',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildMoodSelector(),
            const SizedBox(height: 20),

            // Symptom Chips
            Text(
              'Symptoms',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildSymptomChips(),
            const SizedBox(height: 20),

            // Note Input
            Text(
              'Note (optional)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add any additional notes...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _onSave,
                icon: const Icon(Icons.save),
                label: const Text(
                  'Save Log',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  /// Build the mood selector row with 5 sentiment icons
  Widget _buildMoodSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(5, (index) {
        final moodValue = index + 1; // 1-5 scale
        final isSelected = _selectedMood == moodValue;

        return GestureDetector(
          onTap: () => setState(() => _selectedMood = moodValue),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? _moodColors[index].withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: _moodColors[index], width: 2)
                  : Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _moodIcons[index],
                  size: isSelected ? 36 : 30,
                  color: isSelected ? _moodColors[index] : Colors.grey[400],
                ),
                const SizedBox(height: 4),
                Text(
                  _moodLabels[index],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? _moodColors[index] : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// Build symptom filter chips
  Widget _buildSymptomChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: CommonSymptoms.all.map((symptom) {
        final isSelected = _selectedSymptoms.contains(symptom);
        return FilterChip(
          label: Text(symptom),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedSymptoms.add(symptom);
              } else {
                _selectedSymptoms.remove(symptom);
              }
            });
          },
          selectedColor: Colors.teal.shade100,
          checkmarkColor: Colors.teal,
          backgroundColor: Colors.grey[100],
          labelStyle: TextStyle(
            color: isSelected ? Colors.teal[800] : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isSelected ? Colors.teal : Colors.grey[300]!,
            ),
          ),
        );
      }).toList(),
    );
  }
}
