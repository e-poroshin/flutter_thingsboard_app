import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thingsboard_app/config/routes/router.dart';
import 'package:thingsboard_app/config/themes/tb_theme.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/security/lifecycle_manager.dart';
import 'package:thingsboard_app/generated/l10n.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/di/patient_health_di.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_event.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_state.dart';
import 'package:thingsboard_app/utils/services/layouts/i_layout_service.dart';
import 'package:toastification/toastification.dart';

class ThingsboardApp extends StatefulWidget {
  const ThingsboardApp({super.key});

  @override
  State<StatefulWidget> createState() => _ThingsBoardAppState();
}

class _ThingsBoardAppState extends State<ThingsboardApp> {
  static const _diScopeKey = 'patient_health_app_scope';

  /// The single PatientBloc instance shared by the entire app.
  /// Initialized eagerly in [initState] and never recreated.
  late final PatientBloc _patientBloc;

  @override
  void initState() {
    super.initState();

    // PATIENT APP: Initialize Patient Health module DI eagerly.
    // tbClient is NOT needed for DI init (mock mode uses MockPatientRepository,
    // production mode uses NestApiClient from global scope).
    // This guarantees getIt<PatientBloc>() always resolves to a single instance.
    if (!getIt.hasScope(_diScopeKey)) {
      PatientHealthDi.init(
        _diScopeKey,
        logger: getIt<TbLogger>(),
      );
    }

    // Get the singleton bloc — DI is guaranteed to be initialized above
    _patientBloc = getIt<PatientBloc>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Set device screen size
      getIt<ILayoutService>().setDeviceScreenSize(
        MediaQuery.of(context).size,
        orientation: MediaQuery.of(context).orientation,
      );

      // Dispatch initial health summary load
      _dispatchInitialLoad();
    });
  }

  /// Dispatch the initial PatientLoadHealthSummaryEvent.
  /// Uses the real user ID if available, falls back to mock ID.
  void _dispatchInitialLoad() {
    if (_patientBloc.state is! PatientInitialState) return;

    try {
      final router = getIt<ThingsboardAppRouter>();
      final userId = router.tbContext.tbClient.getAuthUser()?.userId;
      _patientBloc.add(
        PatientLoadHealthSummaryEvent(
          patientId: userId ?? 'mock-patient-001',
        ),
      );
    } catch (_) {
      // tbClient not ready yet — use mock patient ID
      _patientBloc.add(
        const PatientLoadHealthSummaryEvent(patientId: 'mock-patient-001'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // PATIENT APP: Provide the SINGLE PatientBloc instance at global level.
        // Using .value ensures BlocProvider never closes the bloc on dispose.
        // This is the SAME instance that getIt<PatientBloc>() returns,
        // eliminating any split-brain issues between UI and BLE data.
        BlocProvider<PatientBloc>.value(
          value: _patientBloc,
        ),
      ],
      child: LifecycleManager(
        child: ToastificationWrapper(
          child: MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            onGenerateTitle: (BuildContext context) => S.of(context).appTitle,
            themeMode: ThemeMode.light,
            theme: tbTheme,
            darkTheme: tbDarkTheme,
            navigatorKey: getIt<ThingsboardAppRouter>().navigatorKey,
            onGenerateRoute: getIt<ThingsboardAppRouter>().router.generator,
            navigatorObservers: [
              getIt<ThingsboardAppRouter>().tbContext.routeObserver,
            ],
          ),
        ),
      ),
    );
  }
}
