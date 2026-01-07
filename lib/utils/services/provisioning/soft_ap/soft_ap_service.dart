import 'dart:typed_data';

import 'package:thingsboard_app/utils/services/provisioning/esp_provisioning_channel.dart';
import 'package:thingsboard_app/utils/services/provisioning/soft_ap/i_soft_ap_service.dart';

class SoftApService implements ISoftApService {
  @override
  Future<Provisioning> startProvisioning({
    required String hostname,
    required String pop,
  }) async {
    final success = await EspProvisioningChannel.startSoftApSession(
      hostname: hostname,
      pop: pop,
    );

    if (!success) {
      throw Exception('Error establishSession');
    }

    return Provisioning.instance;
  }

  @override
  Future<bool> applyWifiConfig(Provisioning prov) {
    return EspProvisioningChannel.applyWifiConfigSoftAp();
  }

  @override
  Future<ConnectionStatus> getStatus(Provisioning prov) async {
    final result = await EspProvisioningChannel.getStatusSoftAp();
    return ConnectionStatus.fromMap(result);
  }

  @override
  Future<Uint8List> sendReceiveCustomData(
    Provisioning prov, {
    required Uint8List data,
    int packageSize = 256,
    String endpoint = 'custom-data',
  }) {
    return EspProvisioningChannel.sendReceiveCustomDataSoftAp(
      data: data,
      packageSize: packageSize,
      endpoint: endpoint,
    );
  }

  @override
  Future<bool> sendWifiConfig(
    Provisioning prov, {
    required String ssid,
    required String password,
  }) {
    return EspProvisioningChannel.sendWifiConfigSoftAp(
      ssid: ssid,
      password: password,
    );
  }

  @override
  Future<List<Map<String, dynamic>>?> startScanWiFi(Provisioning prov) async {
    final result = await EspProvisioningChannel.scanWifiNetworksSoftAp();
    return result.isEmpty ? null : result;
  }
}
