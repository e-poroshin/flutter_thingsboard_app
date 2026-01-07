import 'package:thingsboard_app/utils/services/provisioning/esp_provisioning_channel.dart';

/// Service for Wi-Fi connection management.
/// Replaces the plugin_wifi_connect package.
class PluginWifiConnect {
  /// Connect to an open Wi-Fi network
  static Future<bool?> connect(String ssid) {
    return EspProvisioningChannel.connectToWifi(ssid)
        .then((value) => value ? true : null);
  }

  /// Connect to a secure Wi-Fi network with password
  static Future<bool?> connectToSecureNetwork(String ssid, String password) {
    return EspProvisioningChannel.connectToSecureWifi(
      ssid: ssid,
      password: password,
    ).then((value) => value ? true : null);
  }

  /// Disconnect from current Wi-Fi network
  static Future<bool?> disconnect() {
    return EspProvisioningChannel.disconnectFromWifi()
        .then((value) => value ? true : null);
  }
}

