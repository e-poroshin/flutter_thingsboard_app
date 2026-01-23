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
    final yMin = (minValue * 0.9).clamp(0, double.infinity);
    final yMax = (maxValue * 1.1);

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
            horizontalInterval: (yMax - yMin) / 5,
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
                reservedSize: 50,
                interval: (yMax - yMin) / 5,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
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
          minY: yMin.toDouble(),
          maxY: yMax.toDouble(),
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
