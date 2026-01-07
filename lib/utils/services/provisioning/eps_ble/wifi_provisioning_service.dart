import 'package:flutter/services.dart';
import 'package:thingsboard_app/utils/services/provisioning/eps_ble/i_wifi_provisioning_service.dart';
import 'package:thingsboard_app/utils/services/provisioning/esp_provisioning_channel.dart';

class BleProvisioningService implements IBleProvisioningService {
  BleProvisioningService();

  @override
  Future<bool?> provisionWifi({
    required String deviceName,
    required String proofOfPossession,
    required String ssid,
    required String passphrase,
  }) {
    return EspProvisioningChannel.provisionWifiBle(
      deviceName: deviceName,
      proofOfPossession: proofOfPossession,
      ssid: ssid,
      passphrase: passphrase,
    );
  }

  @override
  Future<List<String>> scanBleDevices(String prefix) {
    return EspProvisioningChannel.scanBleDevices(prefix);
  }

  @override
  Future<List<String>> scanWifiNetworks({
    required String deviceName,
    required String proofOfPossession,
  }) {
    return EspProvisioningChannel.scanWifiNetworksBle(
      deviceName: deviceName,
      proofOfPossession: proofOfPossession,
    );
  }

  @override
  Future<String?> getPlatformVersion() async {
    // Platform version check via method channel
    try {
      const channel = MethodChannel('esp_provisioning');
      return await channel.invokeMethod<String>('getPlatformVersion');
    } catch (_) {
      return null;
    }
  }
}
