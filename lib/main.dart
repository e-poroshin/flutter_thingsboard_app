import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:thingsboard_app/app_bloc_observer.dart';
import 'package:thingsboard_app/constants/enviroment_variables.dart';
import 'package:thingsboard_app/core/auth/login/select_region/model/region.dart';
import 'package:thingsboard_app/firebase_options.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/task_hive_model_adapter.dart';
import 'package:thingsboard_app/thingsboard_app.dart';
import 'package:thingsboard_app/utils/services/firebase/i_firebase_service.dart';
import 'package:thingsboard_app/utils/services/local_database/i_local_database_service.dart';
import 'package:thingsboard_app/core/services/notification/notification_service.dart';
import 'package:universal_platform/universal_platform.dart';

void main() async {
 final WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Hive.initFlutter();
  Hive.registerAdapter(RegionAdapter());
  // PATIENT APP: Register TaskHiveModel adapter (manual implementation)
  Hive.registerAdapter(TaskHiveModelAdapter());
  await setUpRootDependencies();
  if (UniversalPlatform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(
      kDebugMode || EnvironmentVariables.verbose,
    );
  }

  // Firebase initialization (optional - may not be configured)
  try {
    getIt<IFirebaseService>().initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase not configured yet - skipping (this is expected if google-services.json is missing)
    if (kDebugMode) {
      log('main::Firebase not configured yet - skipping initialization');
    }
  }

  try {
    final uri = await AppLinks().getInitialLink();
    if (uri != null) {
      await getIt<ILocalDatabaseService>().setInitialAppLink(uri.toString());
    }
  } catch (e) {
    log('main::getInitialUri() exception $e', error: e);
  }

  // PATIENT APP: Initialize Notification Service
  try {
    final notificationService = getIt<INotificationService>();
    await notificationService.init();
    await notificationService.requestPermissions();
    log('main::NotificationService initialized successfully');
  } catch (e) {
    log('main::NotificationService initialization exception $e', error: e);
    // Don't fail app startup if notification service fails to initialize
  }

  if (kDebugMode || EnvironmentVariables.verbose) {
    Bloc.observer = AppBlocObserver(getIt());
  }

  runApp(const ThingsboardApp());
}
