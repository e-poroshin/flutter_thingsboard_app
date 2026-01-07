
import 'package:flutter/services.dart';

/// Platform channel for ESP Wi-Fi provisioning functionality.
/// This replaces the deprecated esp_smartconfig, esp_provisioning_softap,
/// and flutter_esp_ble_prov packages.
class EspProvisioningChannel {
  static const MethodChannel _channel = MethodChannel('esp_provisioning');

  // ============== ESP SmartConfig Methods ==============

  /// Start ESP SmartConfig provisioning (ESPTouch/ESPTouchV2)
  static Future<void> startSmartConfig({
    required String ssid,
    required String bssid,
    required String password,
    bool isEspTouchV2 = false,
  }) async {
    await _channel.invokeMethod('startSmartConfig', {
      'ssid': ssid,
      'bssid': bssid,
      'password': password,
      'isEspTouchV2': isEspTouchV2,
    });
  }

  /// Stop ESP SmartConfig provisioning
  static Future<void> stopSmartConfig() async {
    await _channel.invokeMethod('stopSmartConfig');
  }

  // ============== BLE Provisioning Methods ==============

  /// Scan for BLE devices with the given prefix
  static Future<List<String>> scanBleDevices(String prefix) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'scanBleDevices',
      {'prefix': prefix},
    );
    return result?.cast<String>() ?? [];
  }

  /// Scan Wi-Fi networks through a BLE-connected ESP device
  static Future<List<String>> scanWifiNetworksBle({
    required String deviceName,
    required String proofOfPossession,
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'scanWifiNetworksBle',
      {
        'deviceName': deviceName,
        'proofOfPossession': proofOfPossession,
      },
    );
    return result?.cast<String>() ?? [];
  }

  /// Provision Wi-Fi credentials to an ESP device via BLE
  static Future<bool> provisionWifiBle({
    required String deviceName,
    required String proofOfPossession,
    required String ssid,
    required String passphrase,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'provisionWifiBle',
      {
        'deviceName': deviceName,
        'proofOfPossession': proofOfPossession,
        'ssid': ssid,
        'passphrase': passphrase,
      },
    );
    return result ?? false;
  }

  // ============== SoftAP Provisioning Methods ==============

  /// Start SoftAP provisioning session
  static Future<bool> startSoftApSession({
    required String hostname,
    required String pop,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'startSoftApSession',
      {
        'hostname': hostname,
        'pop': pop,
      },
    );
    return result ?? false;
  }

  /// Scan Wi-Fi networks through SoftAP-connected ESP device
  static Future<List<Map<String, dynamic>>> scanWifiNetworksSoftAp() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'scanWifiNetworksSoftAp',
    );
    return result?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Send Wi-Fi configuration to ESP device via SoftAP
  static Future<bool> sendWifiConfigSoftAp({
    required String ssid,
    required String password,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'sendWifiConfigSoftAp',
      {
        'ssid': ssid,
        'password': password,
      },
    );
    return result ?? false;
  }

  /// Apply Wi-Fi configuration on ESP device
  static Future<bool> applyWifiConfigSoftAp() async {
    final result = await _channel.invokeMethod<bool>('applyWifiConfigSoftAp');
    return result ?? false;
  }

  /// Get connection status from ESP device
  static Future<Map<String, dynamic>> getStatusSoftAp() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getStatusSoftAp',
    );
    return result?.cast<String, dynamic>() ?? {};
  }

  /// Send and receive custom data via SoftAP
  static Future<Uint8List> sendReceiveCustomDataSoftAp({
    required Uint8List data,
    int packageSize = 256,
    String endpoint = 'custom-data',
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'sendReceiveCustomDataSoftAp',
      {
        'data': data,
        'packageSize': packageSize,
        'endpoint': endpoint,
      },
    );
    return result ?? Uint8List(0);
  }

  /// Dispose SoftAP provisioning session
  static Future<void> disposeSoftApSession() async {
    await _channel.invokeMethod('disposeSoftApSession');
  }

  // ============== Wi-Fi Connect Methods ==============

  /// Connect to a Wi-Fi network
  static Future<bool> connectToWifi(String ssid) async {
    final result = await _channel.invokeMethod<bool>(
      'connectToWifi',
      {'ssid': ssid},
    );
    return result ?? false;
  }

  /// Connect to a secure Wi-Fi network
  static Future<bool> connectToSecureWifi({
    required String ssid,
    required String password,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'connectToSecureWifi',
      {
        'ssid': ssid,
        'password': password,
      },
    );
    return result ?? false;
  }

  /// Disconnect from current Wi-Fi network
  static Future<bool> disconnectFromWifi() async {
    final result = await _channel.invokeMethod<bool>('disconnectFromWifi');
    return result ?? false;
  }
}

