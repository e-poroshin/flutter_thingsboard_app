import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/services/ble/ble_data_parser.dart';
import 'package:thingsboard_app/core/services/ble/ble_sensor_service.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_event.dart';
import 'package:thingsboard_app/widgets/tb_app_bar.dart';

/// PATIENT APP: Sensor Scan Page
///
/// Displays BLE scan results for temperature sensors.
/// Shows device information and parsed temperature/humidity from advertisement data.
class SensorScanPage extends TbContextWidget {
  SensorScanPage(super.tbContext, {super.key});

  @override
  State<StatefulWidget> createState() => _SensorScanPageState();
}

class _SensorScanPageState extends TbContextState<SensorScanPage> {
  final IBleSensorService _bleService = getIt<IBleSensorService>();
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isInitialized = false;
  String? _errorMessage;

  // Flag to track if we successfully paired a sensor
  // If true, we won't stop the BLE service on dispose, allowing the Bloc to keep scanning
  bool _isSensorPaired = false;

  @override
  void initState() {
    super.initState();
    // Rely on global DI scope initialized in ThingsboardApp
    _initializeAndStartScan();
  }

  @override
  void dispose() {
    // Stop local UI updates
    _scanSubscription?.cancel();
    _scanSubscription = null;

    // CRITICAL FIX: Only stop the physical BLE scan if we didn't pair a sensor.
    // If we paired, the PatientBloc takes over scanning, so we must keep the radio on.
    if (!_isSensorPaired) {
      try {
        _bleService.stopScan();
      } catch (e) {
        // Ignore errors during disposal
      }
    }

    super.dispose();
  }

  Future<void> _initializeAndStartScan() async {
    try {
      setState(() {
        _isInitialized = false;
        _errorMessage = null;
      });

      // Initialize BLE service
      await _bleService.init();

      // Check if Bluetooth is available
      final isAvailable = await _bleService.isBluetoothAvailable();
      if (!isAvailable) {
        setState(() {
          _errorMessage = 'Bluetooth is not available. Please enable Bluetooth.';
          _isInitialized = true;
        });
        return;
      }

      setState(() {
        _isInitialized = true;
        _isScanning = true;
      });

      // Start scanning
      _scanSubscription = _bleService.scanForSensors().listen(
            (results) {
          if (mounted) {
            setState(() {
              _scanResults = results;
              _isScanning = true;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Scan error: $error';
              _isScanning = false;
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isScanning = false;
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Initialization failed: $e';
        _isInitialized = true;
        _isScanning = false;
      });
    }
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _bleService.stopScan();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _restartScan() {
    _stopScan();
    _scanResults.clear();
    _initializeAndStartScan();
  }

  Future<void> _addToDashboard(ScanResult result) async {
    try {
      final remoteId = result.device.remoteId.toString();

      // Save sensor ID to repository
      final repository = getIt<IPatientRepository>();
      await repository.saveSensor(remoteId);

      // Mark as paired so dispose() doesn't kill the scan
      _isSensorPaired = true;

      // Dispatch event to global bloc to load data and start its own listener
      try {
        final bloc = getIt<PatientBloc>();
        final userId = widget.tbContext.tbClient.getAuthUser()?.userId
            ?? 'mock-patient-001';
        bloc.add(PatientLoadHealthSummaryEvent(patientId: userId));
      } catch (e) {
        // Ignore if bloc not ready
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sensor Paired'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Stop local UI updates only (don't stop the actual service!)
        _scanSubscription?.cancel();
        _scanSubscription = null;

        // Small delay for UX
        await Future.delayed(const Duration(milliseconds: 100));

        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _isSensorPaired = false; // Reset flag on error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving sensor: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TbAppBar(
        widget.tbContext,
        title: const Text('Connect Sensor'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initializeAndStartScan,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildScanControls(),
        Expanded(
          child: _scanResults.isEmpty
              ? _buildEmptyState()
              : _buildScanResultsList(),
        ),
      ],
    );
  }

  Widget _buildScanControls() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isScanning ? 'Scanning...' : 'Scan Stopped',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_scanResults.length} device(s) found',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Row(
            children: [
              if (_isScanning)
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: _stopScan,
                  tooltip: 'Stop Scan',
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _restartScan,
                  tooltip: 'Start Scan',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bluetooth_searching,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _isScanning
                ? 'Scanning for sensors...\nBring your sensor closer'
                : 'No devices found',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanResultsList() {
    return SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 80.0),
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          final result = _scanResults[index];
          return _buildScanResultItem(result);
        },
      ),
    );
  }

  Widget _buildScanResultItem(ScanResult result) {
    final deviceName = result.advertisementData.advName.isEmpty
        ? 'Unknown Device'
        : result.advertisementData.advName;
    final deviceId = result.device.remoteId.toString();
    final rssi = result.rssi;

    final temperature = BleDataParser.parseTemperature(result);
    final humidity = BleDataParser.parseHumidity(result);
    final isAtcSensor = BleDataParser.isXiaomiTemperatureMonitor(result);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isAtcSensor
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceVariant,
          child: Icon(
            Icons.thermostat,
            color: isAtcSensor
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          deviceName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'ID: ${deviceId.substring(0, deviceId.length > 17 ? 17 : deviceId.length)}...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'RSSI: $rssi dBm',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (temperature != null) ...[
              Row(
                children: [
                  Icon(Icons.thermostat, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${temperature.toStringAsFixed(1)}°C',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (humidity != null) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.water_drop, size: 18, color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(width: 4),
                    Text(
                      '${humidity.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.hourglass_empty, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Waiting for data...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: temperature != null
            ? ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () => _addToDashboard(result),
              )
            : null,
        isThreeLine: true,
      ),
    );
  }
}
