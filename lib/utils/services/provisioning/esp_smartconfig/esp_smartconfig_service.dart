import 'package:thingsboard_app/utils/services/provisioning/esp_provisioning_channel.dart';
import 'package:thingsboard_app/utils/services/provisioning/esp_smartconfig/i_esp_smartconfig_service.dart';

class EspSmartConfigService implements IEspSmartConfigService {
  EspSmartConfigService();

  SmartConfig _config = SmartConfig.espTouch;

  @override
  void configure(SmartConfig config) {
    _config = config;
  }

  @override
  Future<void> start(ProvisioningRequest request) {
    return EspProvisioningChannel.startSmartConfig(
      ssid: request.ssid,
      bssid: request.bssid,
      password: request.password,
      isEspTouchV2: _config == SmartConfig.espTouchV2,
    );
  }

  @override
  Future<void> stop() {
    return EspProvisioningChannel.stopSmartConfig();
  }
}
