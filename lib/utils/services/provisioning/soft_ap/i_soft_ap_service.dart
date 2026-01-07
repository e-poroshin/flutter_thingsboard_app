import 'dart:typed_data' show Uint8List;

/// Connection status from ESP device
enum WifiConnectionState {
  Disconnected,
  Connecting,
  Connected,
  ConnectionFailed,
}

/// Status result from ESP device
class ConnectionStatus {
  const ConnectionStatus({
    required this.state,
    this.failedReason,
    this.ip,
  });

  final WifiConnectionState state;
  final String? failedReason;
  final String? ip;

  factory ConnectionStatus.fromMap(Map<String, dynamic> map) {
    final stateStr = map['state'] as String? ?? 'disconnected';
    WifiConnectionState state;
    switch (stateStr.toLowerCase()) {
      case 'connected':
        state = WifiConnectionState.Connected;
      case 'connecting':
        state = WifiConnectionState.Connecting;
      case 'connectionfailed':
      case 'failed':
        state = WifiConnectionState.ConnectionFailed;
      default:
        state = WifiConnectionState.Disconnected;
    }
    return ConnectionStatus(
      state: state,
      failedReason: map['failedReason'] as String?,
      ip: map['ip'] as String?,
    );
  }
}

/// Provisioning session handle
class Provisioning {
  const Provisioning._();

  static const instance = Provisioning._();

  Future<void> dispose() async {
    // Handled by platform channel
  }
}

abstract interface class ISoftApService {
  Future<Provisioning> startProvisioning({
    required String hostname,
    required String pop,
  });

  Future<List<Map<String, dynamic>>?> startScanWiFi(Provisioning prov);

  Future<Uint8List> sendReceiveCustomData(
    Provisioning prov, {
    required Uint8List data,
    int packageSize = 256,
    String endpoint = 'custom-data',
  });

  Future<bool> sendWifiConfig(
    Provisioning prov, {
    required String ssid,
    required String password,
  });

  Future<bool> applyWifiConfig(Provisioning prov);

  Future<ConnectionStatus> getStatus(Provisioning prov);
}
