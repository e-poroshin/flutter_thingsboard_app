import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:fluro/fluro.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:thingsboard_app/config/routes/router.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/version/route/version_route.dart';
import 'package:thingsboard_app/modules/version/route/version_route_arguments.dart';
import 'package:thingsboard_app/thingsboard_client.dart';
import 'package:thingsboard_app/utils/services/device_info/i_device_info_service.dart';
import 'package:thingsboard_app/utils/services/endpoint/i_endpoint_service.dart';
import 'package:thingsboard_app/utils/services/firebase/i_firebase_service.dart';
import 'package:thingsboard_app/utils/services/layouts/i_layout_service.dart';
import 'package:thingsboard_app/utils/services/notification_service.dart';
import 'package:thingsboard_app/utils/services/overlay_service/i_overlay_service.dart';
import 'package:thingsboard_app/utils/utils.dart';

import 'package:universal_platform/universal_platform.dart';

part 'has_tb_context.dart';

class TbContext implements PopEntry {
  bool isUserLoaded = false;
  final _isAuthenticated = ValueNotifier<bool>(false);

  /// PATIENT APP: Flag indicating the user authenticated via NestJS BFF
  /// (POST /api/patient/login) rather than the ThingsBoard SDK.
  /// When true, TB-specific auth checks and service calls are bypassed.
  bool _nestApiAuthenticated = false;
  bool get isNestApiAuthenticated => _nestApiAuthenticated;

  List<TwoFaProviderInfo>? twoFactorAuthProviders;
  User? userDetails;
  HomeDashboardInfo? homeDashboard;
  VersionInfo? versionInfo;
  StoreInfo? storeInfo;
  final IOverlayService _overlayService = getIt<IOverlayService>();
  final _deviceInfoService = getIt<IDeviceInfoService>();
  final _isLoadingNotifier = ValueNotifier<bool>(false);
  final _log = TbLogger();
  StreamSubscription? _appLinkStreamSubscription;

  late bool _handleRootState;
  final appLinks = AppLinks();

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(false);

  @override
  void onPopInvoked(bool didPop) {
    onPopInvokedImpl(didPop);
  }

  @override
  void onPopInvokedWithResult(bool didPop, dynamic result) {
    onPopInvokedImpl(didPop, result);
  }

  late ThingsboardClient tbClient;

  final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

  Listenable get isAuthenticatedListenable => _isAuthenticated;

  bool get isAuthenticated => _isAuthenticated.value;

  TbContextState? currentState;
  late final ThingsboardAppRouter thingsboardAppRouter = getIt();
  TbLogger get log => _log;
  final bottomNavigationTabChangedStream = StreamController<int>.broadcast();

  Future<void> init() async {
    _handleRootState = true;

    final endpointService = getIt<IEndpointService>();
    var endpoint = await endpointService.getEndpoint();

    // Safety net: if the endpoint is still empty after EndpointService
    // resolution (should not happen after the fallback fix), use demo server
    // and persist it so subsequent calls are consistent.
    if (endpoint.isEmpty) {
      const fallback = 'https://demo.thingsboard.io';
      log.warn('TbContext::init() endpoint was empty, using fallback: $fallback');
      await endpointService.setEndpoint(fallback);
      endpoint = fallback;
    }

    log.debug('TbContext::init() endpoint: $endpoint');

    // PATIENT APP: Check for existing NestJS session (app restart scenario).
    // If NestJS tokens are stored, we'll skip TB-specific auth in onUserLoaded.
    try {
      _nestApiAuthenticated = await getIt<NestApiClient>().isAuthenticated();
      if (_nestApiAuthenticated) {
        log.debug('TbContext::init() Active NestJS session detected — '
            'will bypass TB auth checks');
      }
    } catch (e) {
      log.debug('TbContext::init() NestApiClient check skipped: $e');
    }

    tbClient = ThingsboardClient(
      endpoint,
      storage: getIt(),
      onUserLoaded: onUserLoaded,
      onError: onError,
      onLoadStarted: onLoadStarted,
      onLoadFinished: onLoadFinished,
      computeFunc: <Q, R>(callback, message) => compute(callback, message),
    );

    try {
      await tbClient.init();
    } catch (e, s) {
      // PATIENT APP: If NestJS auth is active, a TB init failure is expected
      // (no TB credentials). Navigate to /main instead of showing fatal error.
      if (_nestApiAuthenticated) {
        log.debug('TbContext::init() TB init failed with NestJS auth active — '
            'proceeding to main');
        _isAuthenticated.value = true;
        isUserLoaded = true;

        // Cache patient layouts (same as completeNestApiLogin)
        try {
          getIt<ILayoutService>().cachePageLayouts(
            null,
            authority: Authority.CUSTOMER_USER,
          );
        } catch (_) {}

        FlutterNativeSplash.remove();
        await updateRouteState();
        return;
      }
      log.error('Failed to init tbContext: $e', e, s);
      await onFatalError(e);
    }
  }

  Future<void> reInit({
    required String endpoint,
    required VoidCallback onDone,
    required ErrorCallback onAuthError,
  }) async {
    log.debug('TbContext:reinit()');

    _handleRootState = true;

    tbClient = ThingsboardClient(
      endpoint,
      storage: getIt(),
      onUserLoaded: () => onUserLoaded(onDone: onDone),
      onError: (error) {
        onAuthError(error);
        onError(error);
      },
      onLoadStarted: onLoadStarted,
      onLoadFinished: onLoadFinished,
      computeFunc: <Q, R>(callback, message) => compute(callback, message),
    );

    await tbClient.init();
  }

  Future<void> onFatalError(dynamic e) async {
    String getMessage(dynamic e, BuildContext context) {
      final message =
          e is ThingsboardError
              ? (e.message ?? S.of(context).unknownError)
              : S.of(context).unknownError;

      return '${S.of(context).fatalApplicationErrorOccurred}\n$message';
    }

    await _overlayService.showAlertDialog(
      content:
          (context) => DialogContent(
            title: S.of(context).fatalError,
            message: getMessage(e, context),
            ok: S.of(context).cancel,
          ),
    );
    logout();
  }

  void onError(ThingsboardError tbError) {
    log.error('onError', tbError, tbError.getStackTrace());
    _overlayService.showErrorNotification((_) => tbError.message!);
  }

  void onLoadStarted() {
    log.debug('TbContext: On load started.');
    _isLoadingNotifier.value = true;
  }

  Future<void> onLoadFinished() async {
    log.debug('TbContext: On load finished.');
    _isLoadingNotifier.value = false;
  }
Future<bool> checkDasboardAccess(String id) async {
    try {
      final dashboard = await tbClient.getDashboardService().getDashboard(id);
      if (dashboard == null) {
        return false;
      }
    } catch (e) {
      return false;
    }
    return true;
  }
  Future<void> onUserLoaded({VoidCallback? onDone}) async {
    try {
      log.debug(
        'TbContext.onUserLoaded: isAuthenticated=${tbClient.isAuthenticated()}, '
        'nestApiAuth=$_nestApiAuthenticated',
      );
      isUserLoaded = true;

      // ── PATIENT APP: NestJS BFF Auth Path ──────────────────────
      // If the user authenticated via NestJS (POST /api/patient/login),
      // skip ALL ThingsBoard SDK-specific logic (role guard, mobile info,
      // dashboard resolution). NestJS manages auth independently.
      if (_nestApiAuthenticated) {
        log.debug(
          'TbContext.onUserLoaded: NestJS auth active — '
          'bypassing TB checks, navigating to /main',
        );
        userDetails = null;
        homeDashboard = null;
        versionInfo = null;
        storeInfo = null;
        twoFactorAuthProviders = null;

        _isAuthenticated.value = true;

        // ── Cache patient page layouts ─────────────────────────────
        // On app restart the layout cache is empty. Without this call
        // LayoutPagesBloc receives an empty item list and MainPage
        // shows a loading indicator forever ("endless loading" bug).
        try {
          getIt<ILayoutService>().cachePageLayouts(
            null, // null → triggers default 3-tab patient layout
            authority: Authority.CUSTOMER_USER,
          );
        } catch (e) {
          log.warn('TbContext.onUserLoaded: layout cache failed: $e');
        }

        if (isAuthenticated) {
          onDone?.call();
        }

        FlutterNativeSplash.remove();
        if (_handleRootState) {
          await updateRouteState();
        }

        // Skip Firebase notifications (not used with NestJS auth)
        return;
      }

      // ── Standard ThingsBoard SDK Auth Path ─────────────────────
      if (tbClient.isAuthenticated() && !tbClient.isPreVerificationToken()) {
        log.debug('authUser: ${tbClient.getAuthUser()}');

        // PATIENT APP: Role Guard - Only allow CUSTOMER_USER (Patient) access
        final authority = tbClient.getAuthUser()!.authority;
        if (authority != Authority.CUSTOMER_USER) {
          log.warn(
            'TbContext.onUserLoaded: Access Denied - '
            'Patient App Only. User authority: $authority',
          );

          // CRITICAL: Remove splash screen first to prevent hanging
          FlutterNativeSplash.remove();

          // Show non-blocking error notification
          _overlayService.showErrorNotification(
            (_) => 'Access Denied: This app is for Patient users only. '
                'Your account type ($authority) is not supported.',
          );

          // Force logout - clears tokens from secure storage
          await logout(notifyUser: false);

          // Explicitly navigate to login page to prevent getting stuck
          thingsboardAppRouter.navigateTo(
            '/login',
            replace: true,
            clearStack: true,
            transition: TransitionType.fadeIn,
            transitionDuration: const Duration(milliseconds: 750),
          );

          return;
        }

        if (tbClient.getAuthUser()!.userId != null) {
          try {
            final mobileInfo = await tbClient
                .getMobileService()
                .getUserMobileInfo(
                  MobileInfoQuery(
                    platformType: _deviceInfoService.getPlatformType(),
                    packageName: _deviceInfoService.getApplicationId(),
                  ),
                );
            userDetails = mobileInfo?.user;
            homeDashboard = mobileInfo?.homeDashboardInfo;
            versionInfo = mobileInfo?.versionInfo;
            storeInfo = mobileInfo?.storeInfo;
            if (_defaultDashboardId() != null) {
              final hasAccess = await checkDasboardAccess(
                _defaultDashboardId()!,
              );
              if (!hasAccess) {
                userDetails?.additionalInfo?['defaultDashboardId'] = null;
              }
            }
            getIt<ILayoutService>().cachePageLayouts(
              mobileInfo?.pages,
              authority: tbClient.getAuthUser()!.authority,
            );
          } catch (e) {
            log.error('TbContext::onUserLoaded error $e');
            if (!Utils.isConnectionError(e)) {
              logout();
            } else {
              rethrow;
            }
          }
        }
      } else {
        if (tbClient.isPreVerificationToken()) {
          log.debug('authUser: ${tbClient.getAuthUser()}');
          twoFactorAuthProviders =
              await tbClient
                  .getTwoFactorAuthService()
                  .getAvailableLoginTwoFaProviders();
        } else {
          twoFactorAuthProviders = null;
        }

        userDetails = null;
        homeDashboard = null;
        versionInfo = null;
        storeInfo = null;
      }

      _isAuthenticated.value =
          tbClient.isAuthenticated() && !tbClient.isPreVerificationToken();
      if (versionInfo != null && versionInfo?.minVersion != null) {
        if (_deviceInfoService.getAppVersion().versionInt() <
            (versionInfo!.minVersion?.versionInt() ?? 0)) {
          thingsboardAppRouter.navigateTo(
            VersionRoutes.updateRequiredRoutePath,
            clearStack: true,
            replace: true,
            routeSettings: RouteSettings(
              arguments: VersionRouteArguments(
                versionInfo: versionInfo!,
                storeInfo: storeInfo,
              ),
            ),
          );
          return;
        }
      }

      if (isAuthenticated) {
        onDone?.call();
      }
  FlutterNativeSplash.remove();
      if (_handleRootState) {
        await updateRouteState();
      }

      if (isAuthenticated) {
        if (getIt<IFirebaseService>().apps.isNotEmpty) {
          await NotificationService(tbClient, log, this).init();
        }
      }
    } catch (e, s) {
      log.error('TbContext.onUserLoaded: $e', e, s);

      if (Utils.isConnectionError(e)) {
        final res = await _overlayService.showAlertDialog(
          content:
              (context) => DialogContent(
                title: S.of(context).connectionError,
                message: S.of(context).failedToConnectToServer,
                ok: S.of(context).retry,
              ),
        );
        if (res == true) {
          _overlayService.hideNotification();
          onUserLoaded();
        } else {
          thingsboardAppRouter.navigateTo(
            '/login',
            replace: true,
            clearStack: true,
            transition: TransitionType.fadeIn,
            transitionDuration: const Duration(milliseconds: 750),
          );
        }
      } else {
        thingsboardAppRouter.navigateTo(
          '/login',
          replace: true,
          clearStack: true,
          transition: TransitionType.fadeIn,
          transitionDuration: const Duration(milliseconds: 750),
        );
      }
    } finally {
      _appLinkStreamSubscription ??= appLinks.uriLinkStream.listen(
        (link) {
        
          thingsboardAppRouter.navigateByAppLink(link.toString());
        },
        onError: (err) {
          log.error('linkStream.listen $err');
        },
      );
        FlutterNativeSplash.remove();
    }
  }

  Future<void> logout({
    RequestConfig? requestConfig,
    bool notifyUser = true,
  }) async {
    log.debug('TbContext::logout($requestConfig, $notifyUser)');
    _handleRootState = true;

    // PATIENT APP: Clear NestJS auth state
    _nestApiAuthenticated = false;
    try {
      await getIt<NestApiClient>().clearTokens();
    } catch (e) {
      log.debug('TbContext::logout() NestApiClient token clear skipped: $e');
    }

    if (getIt<IFirebaseService>().apps.isNotEmpty) {
      await NotificationService(tbClient, log, this).logout();
    }

    await tbClient.logout(requestConfig: requestConfig, notifyUser: notifyUser);

    _appLinkStreamSubscription?.cancel();
    _appLinkStreamSubscription = null;
  }

 Future<void> updateRouteState() async {
    log.debug(
      'TbContext:updateRouteState() mounted=${currentState != null && currentState!.mounted}, '
      'nestApiAuth=$_nestApiAuthenticated',
    );

    // PATIENT APP: Check both NestJS BFF auth and ThingsBoard SDK auth.
    // If NestJS auth is active, skip the TB isAuthenticated check entirely.
    final isTbAuthenticated =
        tbClient.isAuthenticated() && !tbClient.isPreVerificationToken();
    
    if (!_nestApiAuthenticated && !isTbAuthenticated) {
      thingsboardAppRouter.navigateTo(
        '/login',
        replace: true,
        clearStack: true,
        transition: TransitionType.fadeIn,
        transitionDuration: const Duration(milliseconds: 750),
      );
      return;
    }

    // PATIENT APP: NestJS auth has no TB dashboards or user details.
    // Navigate directly to /main.
    if (_nestApiAuthenticated && !isTbAuthenticated) {
      thingsboardAppRouter.navigateTo(
        '/main',
        replace: true,
        clearStack: true,
        transition: TransitionType.fadeIn,
        transitionDuration: const Duration(milliseconds: 750),
      );
      return;
    }

    final defaultDashboardId = _defaultDashboardId();
    if (defaultDashboardId == null) {
      thingsboardAppRouter.navigateTo(
        '/main',
        replace: true,
        clearStack: true,
        transition: TransitionType.fadeIn,
        transitionDuration: const Duration(milliseconds: 750),
      );
      return;
    }
    final bool fullscreen = _userForceFullscreen();
    if (fullscreen) {
      thingsboardAppRouter.navigateTo(
        '/fullscreenDashboard/$defaultDashboardId',
        replace: true,
        clearStack: true,
        transition: TransitionType.fadeIn,
      );
      return;
    }
    await thingsboardAppRouter.navigateToDashboard(
      defaultDashboardId,
      animate: false,
    );
    thingsboardAppRouter.navigateTo(
      '/main',
      replace: true,
      closeDashboard: false,
      clearStack: true,
      transition: TransitionType.none,
    );
  }

  /// PATIENT APP: Complete login flow after successful NestJS BFF authentication.
  ///
  /// Called from the login page after [INestAuthRepository.login()] succeeds
  /// and tokens are saved. Sets auth state, caches the patient-specific
  /// bottom-bar layout, and navigates directly to `/main`, bypassing the
  /// ThingsBoard SDK auth flow entirely.
  Future<void> completeNestApiLogin() async {
    log.debug('TbContext::completeNestApiLogin() — setting NestJS auth active');
    _nestApiAuthenticated = true;
    _isAuthenticated.value = true;
    isUserLoaded = true;
    _handleRootState = false; // Prevent onUserLoaded from re-navigating

    // ── Cache patient page layouts ─────────────────────────────────
    // The standard TB SDK path calls cachePageLayouts() inside
    // onUserLoaded(). Since we bypass that, we must populate the
    // layout cache here so LayoutPagesBloc has items to render.
    try {
      getIt<ILayoutService>().cachePageLayouts(
        null, // null → triggers default layout for the given authority
        authority: Authority.CUSTOMER_USER,
      );
    } catch (e) {
      log.warn('TbContext::completeNestApiLogin() '
          'layout cache failed: $e');
    }

    FlutterNativeSplash.remove();

    thingsboardAppRouter.navigateTo(
      '/main',
      replace: true,
      clearStack: true,
      transition: TransitionType.fadeIn,
      transitionDuration: const Duration(milliseconds: 750),
    );
  }

  String? _defaultDashboardId() {
    if (userDetails != null && userDetails!.additionalInfo != null) {
      return userDetails!.additionalInfo!['defaultDashboardId']?.toString();
    }
    return null;
  }

  bool _userForceFullscreen() {
    return tbClient.getAuthUser()!.isPublic! ||
        (userDetails != null &&
            userDetails!.additionalInfo != null &&
            userDetails!.additionalInfo!['defaultDashboardFullscreen'] == true);
  }

  String userAgent() {
    String userAgent = 'Mozilla/5.0';
    if (UniversalPlatform.isAndroid) {
      userAgent +=
          ' (Linux; Android ${_deviceInfoService.getSystemVersion()}; ${_deviceInfoService.getDeviceModel()})';
    } else if (UniversalPlatform.isIOS) {
      userAgent += ' (${_deviceInfoService.getDeviceModel()})';
    }
    return '$userAgent AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/83.0.4103.106 Mobile Safari/537.36';
  }

  Future<T?> showFullScreenDialog<T>(Widget dialog, {BuildContext? context}) {
    return Navigator.of(context ?? currentState!.context).push<T>(
      MaterialPageRoute<T>(
        builder: (BuildContext context) {
          return dialog;
        },
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> onPopInvokedImpl<T>(bool didPop, [T? result]) async {
    if (didPop) {
      return;
    }

    if (await currentState?.willPop() == true) {
      if (currentState?.context != null &&
          currentState?.context.mounted == true) {
        // ignore: use_build_context_synchronously
        final navigator = Navigator.of(currentState!.context);
        if (navigator.canPop()) {
          navigator.pop(result);
        } else {
          SystemNavigator.pop();
        }
      }
    }
  }
}
