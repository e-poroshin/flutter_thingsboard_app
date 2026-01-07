enum SmartConfig { espTouch, espTouchV2 }

/// Request for ESP SmartConfig provisioning
class ProvisioningRequest {
  const ProvisioningRequest({
    required this.ssid,
    required this.bssid,
    required this.password,
  });

  final String ssid;
  final String bssid;
  final String password;
}

abstract interface class IEspSmartConfigService {
  void configure(SmartConfig config);

  Future<void> start(ProvisioningRequest request);

  Future<void> stop();
}
