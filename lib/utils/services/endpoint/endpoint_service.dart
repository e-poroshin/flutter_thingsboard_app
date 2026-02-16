import 'package:flutter/foundation.dart';
import 'package:thingsboard_app/constants/app_constants.dart';
import 'package:thingsboard_app/core/auth/login/select_region/model/region.dart';
import 'package:thingsboard_app/utils/services/endpoint/i_endpoint_service.dart';
import 'package:thingsboard_app/utils/services/local_database/i_local_database_service.dart';

class EndpointService implements IEndpointService {
  EndpointService({required this.databaseService});

  static const northAmericaHost = 'https://thingsboard.cloud';
  static const europeHost = 'https://eu.thingsboard.cloud';

  /// Fallback endpoint used when no endpoint is configured (fresh install
  /// without --dart-define=thingsboardApiEndpoint). Prevents "No host
  /// specified in URI" errors on the very first cold start.
  static const _fallbackEndpoint = 'https://demo.thingsboard.io';

  final ILocalDatabaseService databaseService;
  String? _cachedEndpoint;
  final _notifierValue = ValueNotifier<String?>(UniqueKey().toString());
  final _defaultEndpoints = <String>{
    ThingsboardAppConstants.thingsBoardApiEndpoint,
  };

  @override
  ValueListenable<String?> get listenEndpointChanges => _notifierValue;

  @override
  Future<void> setEndpoint(String endpoint) async {
    _cachedEndpoint = endpoint;
    _notifierValue.value = UniqueKey().toString();

    if (endpoint == northAmericaHost) {
      databaseService.saveSelectedRegion(Region.northAmerica);
    } else if (endpoint == europeHost) {
      databaseService.saveSelectedRegion(Region.europe);
    } else {
      databaseService.saveSelectedRegion(Region.custom);
    }

    await databaseService.setSelectedEndpoint(endpoint);
  }

  @override
  Future<String> getEndpoint() async {
    _cachedEndpoint ??= await databaseService.getSelectedEndpoint();

    final endpoint =
        _cachedEndpoint ?? ThingsboardAppConstants.thingsBoardApiEndpoint;

    // On a fresh install the compile-time constant may be an empty string
    // (no --dart-define). Return the fallback so ThingsboardClient always
    // gets a valid host on the very first launch.
    if (endpoint.isEmpty) {
      _cachedEndpoint = _fallbackEndpoint;
      return _fallbackEndpoint;
    }

    return endpoint;
  }

  @override
  Future<bool> isCustomEndpoint() async {
    _cachedEndpoint ??= await getEndpoint();
    final host = Uri.parse(_cachedEndpoint!).host;
    final defaultHosts = _defaultEndpoints.map((e) => Uri.parse(e).host).toSet();
    final isCustom = !defaultHosts.contains(host);
    return isCustom;
  }

  @override
  String getCachedEndpoint() {
    final endpoint =
        _cachedEndpoint ?? ThingsboardAppConstants.thingsBoardApiEndpoint;
    if (endpoint.isEmpty) {
      return _fallbackEndpoint;
    }
    return endpoint;
  }

  @override
  Future<Region?> getSelectedRegion() {
    return databaseService.getSelectedRegion();
  }

  @override
  Future<void> setRegion(Region region) async {
    if (region == Region.northAmerica) {
      await setEndpoint(northAmericaHost);
    } else if (region == Region.europe) {
      await setEndpoint(europeHost);
    }

    return databaseService.saveSelectedRegion(region);
  }
}
