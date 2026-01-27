import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_sign_entity.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_event.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_state.dart';
import 'package:thingsboard_app/widgets/tb_app_bar.dart';

/// PATIENT APP: Vital Detail Page
///
/// Displays historical chart data for a specific vital sign.
/// Shows trends over time with range selector (1D, 1W, 1M).

class VitalDetailPage extends TbContextWidget {
  VitalDetailPage(
    super.tbContext, {
    required this.vitalType,
    super.key,
  });

  final VitalSignType vitalType;

  @override
  State<StatefulWidget> createState() => _VitalDetailPageState();
}

class _VitalDetailPageState extends TbContextState<VitalDetailPage> {
  String _selectedRange = '1D';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVitalHistory();
    });
  }

  void _loadVitalHistory() {
    final vitalId = widget.vitalType.name;
    getIt<PatientBloc>().add(
      PatientLoadVitalHistoryEvent(
        vitalId: vitalId,
        range: _selectedRange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PatientBloc>.value(
      value: getIt<PatientBloc>(),
      child: Scaffold(
        appBar: TbAppBar(
          tbContext,
          title: Text(
            widget.vitalType.displayName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: BlocBuilder<PatientBloc, PatientState>(
          builder: (context, state) {
            return switch (state) {
              PatientInitialState() => _buildLoadingView(),
              PatientLoadingState() => _buildLoadingView(),
              PatientVitalHistoryLoadedState() => _buildChartView(state),
              PatientErrorState() => _buildErrorView(state),
              _ => _buildLoadingView(),
            };
          },
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading vital history...'),
        ],
      ),
    );
  }

  Widget _buildErrorView(PatientErrorState state) {
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
            state.message,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadVitalHistory,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildChartView(PatientVitalHistoryLoadedState state) {
    if (state.historyPoints.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No historical data available',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Historical data will appear here once measurements are recorded.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Value Display
          _buildCurrentValueSection(state),
          const SizedBox(height: 24),

          // Range Selector
          _buildRangeSelector(),
          const SizedBox(height: 24),

          // Chart
          _buildChart(state),
        ],
      ),
    );
  }

  Widget _buildCurrentValueSection(PatientVitalHistoryLoadedState state) {
    final currentValue = state.currentValue;
    final unit = widget.vitalType.defaultUnit;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Average',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currentValue != null
                ? '${currentValue.toStringAsFixed(1)} $unit'
                : 'N/A',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildRangeChip('1D', '1 Day'),
        _buildRangeChip('1W', '1 Week'),
        _buildRangeChip('1M', '1 Month'),
      ],
    );
  }

  Widget _buildRangeChip(String range, String label) {
    final isSelected = _selectedRange == range;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedRange = range;
          });
          _loadVitalHistory();
        }
      },
      selectedColor: Theme.of(context).primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildChart(PatientVitalHistoryLoadedState state) {
    final points = state.historyPoints;
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    // Prepare chart data
    final spots = points.asMap().entries.map((entry) {
      final index = entry.key;
      final point = entry.value;
      return FlSpot(index.toDouble(), point.value);
    }).toList();

    // Find min/max for Y-axis
    final values = points.map((p) => p.value).toList();
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    
    // Calculate Y-axis bounds with padding
    final yRange = maxValue - minValue;
    final padding = yRange > 0 ? (yRange * 0.1) : (maxValue * 0.1).clamp(1.0, double.infinity);
    final yMin = (minValue - padding).clamp(0, double.infinity);
    final yMax = maxValue + padding;
    
    // Calculate a "nice" interval that prevents label overlap
    // This ensures labels are at round numbers and spaced appropriately
    final rawRange = yMax - yMin;
    final rawInterval = rawRange > 0 ? (rawRange / 4) : 1.0; // Target 4-5 labels max
    
    // Round interval to a "nice" number (1, 2, 5, 10, 20, 50, 100, etc.)
    final ln10 = math.log(10);
    final magnitude = (rawInterval.abs() < 1) 
        ? 1.0 
        : math.pow(10, (math.log(rawInterval.abs()) / ln10).floor()).toDouble();
    final normalizedInterval = rawInterval / magnitude;
    
    double niceInterval;
    if (normalizedInterval <= 1) {
      niceInterval = magnitude;
    } else if (normalizedInterval <= 2) {
      niceInterval = 2 * magnitude;
    } else if (normalizedInterval <= 5) {
      niceInterval = 5 * magnitude;
    } else {
      niceInterval = 10 * magnitude;
    }
    
    // Ensure minimum interval to prevent too many labels
    final finalInterval = niceInterval.clamp(1.0, double.infinity);
    
    // Round min/max to nice intervals to ensure clean labels
    final niceMin = (yMin / finalInterval).floor() * finalInterval;
    final niceMax = ((yMax / finalInterval).ceil() * finalInterval).clamp(niceMin + finalInterval, double.infinity);

    // Format X-axis labels
    String getXLabel(int index) {
      if (index >= points.length) return '';
      final timestamp = points[index].timestamp;
      if (_selectedRange == '1D') {
        return DateFormat('HH:mm').format(timestamp);
      } else if (_selectedRange == '1W') {
        return DateFormat('MMM d').format(timestamp);
      } else {
        return DateFormat('MMM d').format(timestamp);
      }
    }

    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: finalInterval,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.withOpacity(0.2),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: (points.length / 5).ceil().toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < points.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        getXLabel(index),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 70, // Increased significantly to prevent text overlap
                interval: finalInterval, // Use calculated nice interval
                getTitlesWidget: (value, meta) {
                  // Only show labels at exact interval positions to prevent overlap
                  // Check if value is at an exact interval position (within small tolerance)
                  final normalizedValue = value - niceMin;
                  final intervalPosition = normalizedValue / finalInterval;
                  
                  // Only show label if value is very close to an exact interval position
                  // This prevents duplicate/overlapping labels
                  if ((intervalPosition - intervalPosition.round()).abs() > 0.01) {
                    return const SizedBox.shrink();
                  }
                  
                  // Use the exact interval-aligned value for display
                  final displayValue = (intervalPosition.round() * finalInterval) + niceMin;
                  
                  // Format numbers to prevent long labels
                  String formattedValue;
                  if (displayValue.abs() >= 1000) {
                    formattedValue = '${(displayValue / 1000).toStringAsFixed(1)}k';
                  } else if (displayValue % 1 == 0) {
                    formattedValue = displayValue.toInt().toString();
                  } else {
                    // Determine decimal places based on interval
                    final ln10 = math.log(10);
                    final decimalPlaces = finalInterval < 1 
                        ? (math.log(1 / finalInterval) / ln10).ceil().clamp(0, 2)
                        : 0;
                    formattedValue = displayValue.toStringAsFixed(decimalPlaces);
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.only(right: 10.0),
                    child: Text(
                      formattedValue,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: false,
          ),
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: niceMin,
          maxY: niceMax,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Theme.of(context).primaryColor,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Theme.of(context).primaryColor.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
