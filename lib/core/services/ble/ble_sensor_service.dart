import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';

/// PATIENT APP: BLE Sensor Service Interface
///
/// Abstract interface for BLE sensor scanning services.
/// Handles passive scanning for Xiaomi Mi Temperature Monitor 2 (LYWSD03MMC)
/// and other BLE environmental sensors.
abstract interface class IBleSensorService {
  /// Initialize the BLE service and request necessary permissions
  /// Must be called before scanning
  Future<void> init();

  /// Start scanning for BLE sensors.
  /// Returns a broadcast stream of scan results that keeps emitting
  /// until [stopScan] is called. No timeout — runs indefinitely.
  Stream<List<ScanResult>> scanForSensors();

  /// Stop scanning for BLE sensors
  void stopScan();

  /// Check if BLE is available on the device
  Future<bool> isBluetoothAvailable();

  /// Check if location services are enabled (required for BLE scanning)
  Future<bool> isLocationEnabled();
}

/// PATIENT APP: BLE Sensor Service Implementation
///
/// Handles BLE scanning for passive sensor reading.
/// Uses flutter_blue_plus for cross-platform BLE support.
///
/// [scanForSensors] starts a scan with **no timeout** and returns the
/// FBP scanResults broadcast stream directly. The scan runs continuously
/// until [stopScan] is called.  Multiple callers can listen to the same
/// stream (it is a broadcast stream from FBP).
class BleSensorService implements IBleSensorService {
  BleSensorService({
    required this.logger,
  });

  final TbLogger logger;
  bool _isInitialized = false;
  bool _isScanning = false;

  @override
  Future<void> init() async {
    if (_isInitialized) {
      logger.debug('BleSensorService: Already initialized');
      return;
    }

    try {
      // Request necessary permissions
      final permissionsGranted = await requestPermissions();
      if (!permissionsGranted) {
        throw Exception(
          'BleSensorService: Required permissions not granted',
        );
      }

      // Check if Bluetooth is available
      final isAvailable = await isBluetoothAvailable();
      if (!isAvailable) {
        throw Exception('BleSensorService: Bluetooth is not available');
      }

      _isInitialized = true;
      logger.info('BleSensorService: Initialized successfully');
    } catch (e) {
      logger.error('BleSensorService: Initialization failed: $e');
      rethrow;
    }
  }

  /// Request all necessary permissions for BLE scanning
  Future<bool> requestPermissions() async {
    try {
      // Request Bluetooth permissions (Android 12+)
      final bluetoothScanStatus = await Permission.bluetoothScan.request();
      final bluetoothConnectStatus =
          await Permission.bluetoothConnect.request();

      // Request location permission (required for BLE scanning on Android)
      final locationStatus = await Permission.locationWhenInUse.request();

      final allGranted = bluetoothScanStatus.isGranted &&
          bluetoothConnectStatus.isGranted &&
          locationStatus.isGranted;

      if (!allGranted) {
        logger.warn(
          'BleSensorService: Some permissions not granted - '
          'BluetoothScan: ${bluetoothScanStatus.isGranted}, '
          'BluetoothConnect: ${bluetoothConnectStatus.isGranted}, '
          'Location: ${locationStatus.isGranted}',
        );
      }

      return allGranted;
    } catch (e) {
      logger.error('BleSensorService: Error requesting permissions: $e');
      return false;
    }
  }

  @override
  Stream<List<ScanResult>> scanForSensors() {
    if (!_isInitialized) {
      throw Exception(
        'BleSensorService: Must call init() before scanning',
      );
    }

    // If already scanning, just return the existing FBP stream
    if (_isScanning) {
      logger.debug('BleSensorService: Already scanning, returning existing stream');
      return FlutterBluePlus.scanResults;
    }

    logger.info('BleSensorService: Starting continuous BLE scan (no timeout)');

    try {
      // Start scan WITHOUT timeout — runs until stopScan() is called.
      // This is the key fix: no timeout means no periodic restart,
      // no result-list reset, and continuous data flow.
      FlutterBluePlus.startScan(
        androidUsesFineLocation: true,
      );
      _isScanning = true;
      logger.debug('BleSensorService: Scan started successfully');
    } catch (e) {
      logger.error('BleSensorService: Error starting scan: $e');
      rethrow;
    }

    // FBP's scanResults is a broadcast stream that accumulates all
    // discovered devices and keeps emitting as new advertisements arrive.
    return FlutterBluePlus.scanResults;
  }

  @override
  void stopScan() {
    logger.info('BleSensorService: Stopping BLE scan');
    _isScanning = false;

    try {
      FlutterBluePlus.stopScan();
    } catch (_) {
      // Ignore errors when stopping scan
    }
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    try {
      // Check if Bluetooth adapter is available
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      logger.error('BleSensorService: Error checking Bluetooth availability: $e');
      return false;
    }
  }

  @override
  Future<bool> isLocationEnabled() async {
    try {
      final locationStatus = await Permission.locationWhenInUse.status;
      return locationStatus.isGranted;
    } catch (e) {
      logger.error('BleSensorService: Error checking location status: $e');
      return false;
    }
  }
}
