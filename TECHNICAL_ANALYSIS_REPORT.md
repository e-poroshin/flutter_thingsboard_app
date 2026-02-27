# ThingsBoard Flutter App - Technical Analysis Report

**Date:** January 2, 2026  
**Purpose:** Evaluate adaptability for a Patient-facing Health Care mobile application integrating ThingsBoard (telemetry) and Medplum (FHIR data).

---

## Table of Contents

1. [Project Architecture & State Management](#1-project-architecture--state-management)
2. [Core ThingsBoard Integration](#2-core-thingsboard-integration)
3. [Authentication & Security](#3-authentication--security)
4. [Refactoring Complexity Assessment](#4-refactoring-complexity-assessment)
5. [Key Dependencies](#5-key-dependencies)
6. [HIPAA Compliance Considerations](#6-hipaa-compliance-considerations)
7. [Recommendations for Healthcare Fork](#7-recommendations-for-healthcare-fork)

---

## 1. Project Architecture & State Management

### 1.1 Folder Structure Analysis

The project follows a **hybrid approach** combining both **feature-first** and **layer-first** patterns:

```
lib/
├── config/               # App-wide configuration (routes, themes)
│   ├── routes/
│   └── themes/
├── constants/            # Global constants
├── core/                 # Core functionality (auth, context, logging)
│   ├── auth/
│   │   ├── login/        # Feature: Login (with BLoC, DI, views)
│   │   ├── noauth/       # Feature: NoAuth flow (Clean Architecture)
│   │   ├── oauth2/
│   │   └── web/
│   ├── context/          # Global app context (TbContext)
│   ├── init/             # App initialization
│   └── logger/
├── modules/              # Feature modules (feature-first)
│   ├── alarm/            # Full Clean Architecture
│   │   ├── data/
│   │   ├── di/
│   │   ├── domain/
│   │   └── presentation/
│   ├── dashboard/
│   ├── device/
│   ├── notification/
│   └── ...
├── utils/
│   └── services/         # Shared services layer
└── widgets/              # Reusable UI components
```

**Key Observation:** The codebase is evolving toward Clean Architecture. Newer modules like `alarm` and `noauth` follow Clean Architecture principles with clear separation:
- **Data Layer:** Datasources, repositories implementations
- **Domain Layer:** Entities, use cases, repository interfaces  
- **Presentation Layer:** BLoC, views, widgets

Older modules like `device` and `asset` are simpler, widget-centric structures.

### 1.2 State Management Solution

**Primary:** `flutter_bloc` (^8.1.5)

The app uses BLoC extensively for state management:

```dart
// Example: AlarmBloc (lib/modules/alarm/presentation/bloc/alarms_bloc.dart)
class AlarmBloc extends Bloc<AlarmEvent, AlarmsState> {
  AlarmBloc({
    required this.paginationRepository,
    required this.fetchAlarmsUseCase,
    required this.queryController,
  }) : super(const AlarmsFiltersNotActivatedState()) {
    on(_onEvent);
  }

  Future<void> _onEvent(AlarmEvent event, Emitter<AlarmsState> emit) async {
    switch (event) {
      case AlarmFiltersResetEvent():
        // Handle filter reset
      case AlarmFiltersUpdateEvent():
        queryController.onFiltersUpdated(event.filtersEntity);
        emit(const AlarmsFilterActivatedState());
      // ...
    }
  }
}
```

**Secondary State Mechanisms:**
- `ValueNotifier<T>` for simpler UI state (loading indicators, toggles)
- `StreamController<T>.broadcast()` for cross-component communication
- `EventBus` for decoupled event broadcasting

### 1.3 Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          UI Layer                                │
│  (TbContextWidget, BlocBuilder, ValueListenableBuilder)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Presentation Layer                          │
│  (BLoC: AlarmBloc, AuthBloc, LayoutPagesBloc)                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Domain Layer                               │
│  (UseCases: FetchAlarmsUseCase, FetchDashboardsUseCase)         │
│  (Entities: AlarmFiltersEntity, DashboardArgumentsEntity)       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Data Layer                                │
│  (Repositories: AlarmsRepository, NoAuthRepository)            │
│  (Datasources: AlarmsDatasource, NoAuthRemoteDatasource)        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ThingsboardClient                             │
│  (External package: thingsboard_client ^4.0.0)                  │
│  Handles: HTTP, WebSocket, JWT, Token Refresh                   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.4 Dependency Injection

**Library:** `get_it` (^7.6.7) - Service Locator pattern

**Root-level DI** (`lib/locator.dart`):
```dart
final getIt = GetIt.instance;

Future<void> setUpRootDependencies() async {
  final secureStorage = createAppStorage() as TbSecureStorage;
  await secureStorage.init();
  
  getIt
    ..registerLazySingleton(() => TbLogger())
    ..registerLazySingleton<IOverlayService>(() => OverlayService())
    ..registerSingleton(ThingsboardAppRouter(overlayService: getIt(), tbContext: getIt()))
    ..registerLazySingleton<TbStorage>(() => secureStorage)
    ..registerLazySingleton<ILocalDatabaseService>(() => LocalDatabaseService(...))
    ..registerLazySingleton<IEndpointService>(() => EndpointService(...))
    ..registerLazySingleton<IFirebaseService>(() => FirebaseService(...))
    // ...
}
```

**Feature-scoped DI** (using `getIt.pushNewScope`):
```dart
// lib/modules/alarm/di/alarms_di.dart
class AlarmsDi {
  static void init(String scopeName, {required ThingsboardClient tbClient, ...}) {
    getIt.pushNewScope(
      scopeName: scopeName,
      init: (locator) {
        locator.registerFactory<IAlarmsDatasource>(() => AlarmsDatasource(...));
        locator.registerFactory<IAlarmsRepository>(() => AlarmsRepository(...));
        locator.registerLazySingleton(() => AlarmBloc(...));
      },
    );
  }

  static void dispose(String scopeName, ...) {
    getIt<AlarmBloc>().close();
    getIt.dropScope(scopeName);
  }
}
```

**Implications for Healthcare Fork:**
- ✅ Well-structured DI enables easy injection of new services (FHIR client)
- ✅ Scoped DI prevents memory leaks and enables proper cleanup
- ⚠️ No interface-based registration for ThingsboardClient itself (hardcoded in TbContext)

---

## 2. Core ThingsBoard Integration

### 2.1 API Communication

**Client Library:** `thingsboard_client` (^4.0.0) - External Dart package

The ThingsBoard client is instantiated in `TbContext`:

```dart
// lib/core/context/tb_context.dart
tbClient = ThingsboardClient(
  endpoint,                    // Server URL
  storage: getIt(),            // TbSecureStorage for tokens
  onUserLoaded: onUserLoaded,  // Callback after auth
  onError: onError,            // Error handler
  onLoadStarted: onLoadStarted,
  onLoadFinished: onLoadFinished,
  computeFunc: <Q, R>(callback, message) => compute(callback, message),
);
```

**HTTP Client:** The `thingsboard_client` package internally uses Dart's `http` package (overridden to ^1.3.0 in pubspec.yaml).

### 2.2 Dashboard Rendering - CRUCIAL FINDING

**Dashboards are rendered via WebView, NOT native Flutter widgets.**

```dart
// lib/modules/dashboard/presentation/widgets/dashboard_widget.dart
class DashboardWidget extends TbContextWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: _initialUrl),
          // ...
        ),
      ],
    );
  }

  @override
  void initState() {
    _initialUrl = WebUri(
      '${getIt<IEndpointService>().getCachedEndpoint()}'
      '?accessToken=${widget.tbContext.tbClient.getJwtToken()!}'
      '&refreshToken=${widget.tbContext.tbClient.getRefreshToken()!}',
    );
  }
}
```

**How it works:**
1. The app loads the ThingsBoard web dashboard inside `InAppWebView`
2. JWT tokens are passed via URL query parameters
3. JavaScript handlers bridge WebView ↔ Flutter:
   - `tbMobileReadyHandler` - WebView loaded
   - `tbMobileDashboardLoadedHandler` - Dashboard ready
   - `tbMobileNavigationHandler` - Navigation requests
   - `tbMobileHandler` - Widget mobile actions

**Dashboard Controller** (`lib/modules/dashboard/presentation/controller/dashboard_controller.dart`):
```dart
Future<void> openDashboard(String dashboardId, {...}) async {
  final windowMessage = <String, dynamic>{
    'type': 'openDashboardMessage',
    'data': {'dashboardId': dashboardId, ...}
  };
  await controller?.postWebMessage(
    message: WebMessage(data: jsonEncode(windowMessage)),
    targetOrigin: WebUri('*'),
  );
}
```

**Widget Mobile Actions** are handled in `lib/utils/services/mobile_actions/widget_action_handler.dart`:
```dart
static final actions = [
  DeviceProvisioningAction(),
  ShowMapLocationAction(),
  TakePhotoAction(),
  ScanQrAction(),
  MakePhoneCallAction(),
  GetLocationAction(),
  // ...
];
```

**Implications:**
- ✅ Dashboards are fully dynamic - configured on ThingsBoard server
- ✅ No need to modify Flutter code for dashboard changes
- ⚠️ Requires network connectivity to render dashboards
- ⚠️ WebView-based approach may not be ideal for offline healthcare scenarios
- 🔴 Tokens passed in URL could be logged - security concern for HIPAA

### 2.3 WebSocket/Telemetry Connection

**Critical Finding:** The native Flutter app does NOT directly handle WebSocket connections for telemetry.

WebSocket connections for real-time telemetry data are managed **inside the WebView** by the ThingsBoard web dashboard JavaScript code. The Flutter app simply hosts this WebView.

The `thingsboard_client` package does provide WebSocket capabilities, but they're used for:
- Token refresh notifications
- Session management
- NOT for telemetry subscriptions in this app

For native telemetry access, you would need to use:
```dart
// Example (not currently implemented in the app)
tbClient.getWebsocketService().subscribe(...)
```

---

## 3. Authentication & Security

### 3.1 Authentication Flow

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Login Page    │──────│  ThingsBoard    │──────│   TbContext     │
│                 │      │    Client       │      │  onUserLoaded() │
└─────────────────┘      └─────────────────┘      └─────────────────┘
        │                        │                        │
        ▼                        ▼                        ▼
   Email/Password          tbClient.login()        Load User Info
   OAuth2 (Google,         JWT + Refresh          Route to /main
    Apple, etc.)            Token
```

**Login Methods:**
1. **Email/Password:**
   ```dart
   await tbClient.login(LoginRequest(username, password));
   ```

2. **OAuth2:**
   ```dart
   final result = await getIt<IOAuth2Client>().authenticate(client.url);
   await tbClient.setUserFromJwtToken(result.accessToken, result.refreshToken, true);
   ```

3. **QR Code Deep Link:**
   ```dart
   getIt<ThingsboardAppRouter>().navigateByAppLink(barcode.rawValue);
   ```

**Two-Factor Authentication:**
```dart
// lib/core/auth/login/two_factor_authentication_page.dart
twoFactorAuthProviders = await tbClient
    .getTwoFactorAuthService()
    .getAvailableLoginTwoFaProviders();
```

### 3.2 Token Storage

**Storage Implementation:** `flutter_secure_storage` + `Hive` encrypted box

```dart
// lib/utils/services/_tb_secure_storage.dart
class TbSecureStorage<T> implements TbStorage {
  late Box encryptedBox;

  Future<void> init() async {
    const secureStorage = FlutterSecureStorage();
    
    // Generate encryption key if not exists
    final encryptionKeyString = await secureStorage.read(key: 'key');
    if (encryptionKeyString == null) {
      final key = Hive.generateSecureKey();
      await secureStorage.write(key: 'key', value: base64UrlEncode(key));
    }

    final key = await secureStorage.read(key: 'key');
    final encryptionKeyUint8List = base64Url.decode(key!);

    // Open encrypted Hive box
    encryptedBox = await Hive.openBox(
      'securedStorage',
      encryptionCipher: HiveAesCipher(encryptionKeyUint8List),
    );
  }
}
```

**Security Assessment:**
- ✅ Uses `flutter_secure_storage` for the encryption key (Keychain on iOS, EncryptedSharedPreferences on Android)
- ✅ Hive box encrypted with AES
- ✅ Tokens not stored in plain SharedPreferences
- ⚠️ `thingsboard_client` handles actual token storage - review external package

### 3.3 User Role Checking

**Authority Types** (from `thingsboard_client` package):
- `Authority.SYS_ADMIN` - System Administrator
- `Authority.TENANT_ADMIN` - Tenant Administrator  
- `Authority.CUSTOMER_USER` - Customer User

**Role-Based Navigation** (`lib/utils/services/layouts/layout_service.dart`):
```dart
void cachePageLayouts(List<PageLayout>? pages, {required Authority authority}) {
  if (pages == null) {
    pagesLayout = [
      const PageLayout(id: Pages.home),
      const PageLayout(id: Pages.alarms),
      const PageLayout(id: Pages.devices),
    ];

    if (authority == Authority.SYS_ADMIN) {
      pagesLayout.add(const PageLayout(id: Pages.notifications));
    } else if (authority == Authority.TENANT_ADMIN) {
      pagesLayout.addAll([
        const PageLayout(id: Pages.customers),
        const PageLayout(id: Pages.assets),
        const PageLayout(id: Pages.audit_logs),
        const PageLayout(id: Pages.notifications),
      ]);
    } else if (authority == Authority.CUSTOMER_USER) {
      pagesLayout.addAll([
        const PageLayout(id: Pages.assets),
        const PageLayout(id: Pages.notifications),
      ]);
    }
  }
}
```

**Role Check in Device Provisioning:**
```dart
// lib/utils/services/mobile_actions/actions/device_provisioning_action.dart
if (tbContext.userDetails?.authority != Authority.CUSTOMER_USER) {
  return WidgetMobileActionResult.errorResult(
    "Provisioning is only available for customer roles.",
  );
}
```

**Key Files for Role-Based Access:**
- `lib/utils/services/layouts/layout_service.dart` - Page layout by role
- `lib/modules/layout_pages/bloc/layout_pages_bloc.dart` - Bottom bar items
- `lib/modules/home/home_page.dart` - Home page per role

**For Patient Role Lock-down:**
```dart
// You would add a new Authority type or filter for "Patient"
if (authority == Authority.CUSTOMER_USER) {
  // Only show patient-relevant pages
  pagesLayout = [
    const PageLayout(id: Pages.home),
    const PageLayout(id: Pages.notifications),
    // Custom patient dashboard
  ];
}
```

---

## 4. Refactoring Complexity Assessment

### 4.1 Removing Admin Navigation Drawer → Simple 3-Tab Layout

**Difficulty: LOW**

The navigation is already tab-based (BottomNavigationBar), not drawer-based!

**Current Implementation:**
```dart
// lib/modules/main/main_page.dart
Scaffold(
  body: TabBarView(
    controller: _tabController,
    children: state.items.map((e) => e.page).toList(),
  ),
  bottomNavigationBar: TbNavigationBarWidget(
    currentIndex: _currentIndexNotifier.value,
    onTap: (index) => _setIndex(index),
    customBottomBarItems: state.items,
  ),
)
```

**Steps to Modify:**
1. Edit `lib/utils/services/layouts/layout_service.dart`:
   ```dart
   void cachePageLayouts(...) {
     // For Patient role, only allow 3 tabs
     pagesLayout = [
       const PageLayout(id: Pages.home),        // Patient Dashboard
       const PageLayout(id: Pages.notifications),
       // Custom FHIR/Health Records page
     ];
   }
   ```

2. Modify `LayoutPagesBloc.getBottomBarItems()` to force 3 items max.

**Estimated Effort:** 2-4 hours

### 4.2 Stripping Device Management, Keeping Dashboards

**Difficulty: LOW-MEDIUM**

**Files to Remove/Disable:**
```
lib/modules/device/           # Remove or stub
lib/modules/asset/            # Remove or stub
lib/modules/customer/         # Remove
lib/modules/tenant/           # Remove
lib/modules/audit_log/        # Remove
```

**Steps:**
1. Remove routes from `lib/config/routes/router.dart`:
   ```dart
   // Comment out or remove:
   // DeviceRoutes(_tbContext).doRegisterRoutes(router);
   // AssetRoutes(_tbContext).doRegisterRoutes(router);
   ```

2. Remove from layout service page options:
   ```dart
   // Remove Pages.devices, Pages.assets, etc.
   ```

3. Keep dashboard functionality intact:
   - `lib/modules/dashboard/` - Keep entirely
   - `lib/modules/home/home_page.dart` - Keep (loads home dashboard)

**Estimated Effort:** 4-8 hours

### 4.3 Injecting Secondary FHIR Data Source (Medplum)

**Difficulty: MEDIUM-HIGH**

This requires architectural additions but the DI structure supports it well.

**Recommended Approach:**

1. **Create FHIR Module:**
   ```
   lib/modules/fhir/
   ├── data/
   │   ├── datasource/
   │   │   └── medplum_datasource.dart
   │   └── repository/
   │       └── fhir_repository.dart
   ├── di/
   │   └── fhir_di.dart
   ├── domain/
   │   ├── entities/
   │   │   └── patient_record.dart
   │   ├── repository/
   │   │   └── i_fhir_repository.dart
   │   └── usecases/
   │       ├── fetch_patient_usecase.dart
   │       └── fetch_vitals_usecase.dart
   └── presentation/
       ├── bloc/
       │   └── patient_bloc.dart
       └── view/
           └── patient_records_page.dart
   ```

2. **Register FHIR Client in DI:**
   ```dart
   // lib/locator.dart
   getIt.registerLazySingleton<IMedplumClient>(
     () => MedplumClient(
       endpoint: 'https://api.medplum.com/fhir/R4',
       // Configure auth
     ),
   );
   ```

3. **Create Combined Health Context:**
   ```dart
   class HealthContext {
     final TbContext tbContext;      // ThingsBoard telemetry
     final IMedplumClient fhirClient; // FHIR clinical data
     
     // Unified patient data access
   }
   ```

**Challenges:**
- Authentication synchronization between ThingsBoard and Medplum
- Data correlation (linking device telemetry to FHIR Patient resources)
- Offline support strategy for clinical data

**Estimated Effort:** 2-4 weeks depending on FHIR scope

---

## 5. Key Dependencies

### 5.1 Critical Libraries

| Package | Version | Purpose | Risk Assessment |
|---------|---------|---------|-----------------|
| `thingsboard_client` | ^4.0.0 | ThingsBoard API client | ⚠️ Core dependency, locked to TB version |
| `flutter_bloc` | ^8.1.5 | State management | ✅ Stable, widely used |
| `get_it` | ^7.6.7 | Dependency injection | ✅ Stable |
| `flutter_secure_storage` | ^9.0.0 | Secure token storage | ✅ HIPAA-relevant, stable |
| `hive` | ^2.2.3 | Local encrypted storage | ✅ Stable |
| `flutter_inappwebview` | ^6.1.5 | Dashboard WebView | ⚠️ Platform-specific issues possible |
| `firebase_messaging` | ^15.0.1 | Push notifications | ⚠️ Firebase dependency |
| `fluro` | ^2.0.5 | Routing | ✅ Stable but older pattern |
| `freezed_annotation` | ^3.1.0 | Immutable models | ✅ Modern, recommended |

### 5.2 Flutter SDK Compatibility

**Current:** `sdk: ^3.7.0`

This is a very recent Dart SDK requirement, indicating the project is actively maintained and uses modern Flutter features.

### 5.3 Potential Conflicts

1. **`http` Override:**
   ```yaml
   dependency_overrides:
     http: ^1.3.0
   ```
   This override exists likely due to `thingsboard_client` requiring a specific version.

2. **`flutter_html: 3.0.0-beta.2`** - Beta version, may have breaking changes.

3. **`auto_size_text: ^3.0.0-nullsafety.0`** - Null-safety migration version.

---

## 6. HIPAA Compliance Considerations

### 6.1 Current Security Posture

| Requirement | Status | Notes |
|-------------|--------|-------|
| Encryption at Rest | ✅ | Hive AES encryption + Secure Storage |
| Encryption in Transit | ✅ | HTTPS enforced |
| Access Control | ⚠️ | Role-based, but no Patient-specific role |
| Audit Logging | ⚠️ | Server-side only |
| Session Management | ✅ | JWT with refresh tokens |
| Secure Token Storage | ✅ | flutter_secure_storage |
| Biometric Auth | ❌ | Not implemented |
| App Timeout/Lock | ❌ | Not implemented |

### 6.2 Required Additions for HIPAA

1. **Biometric Authentication:**
   ```dart
   // Add: local_auth package
   final authenticated = await LocalAuthentication().authenticate(
     localizedReason: 'Authenticate to access health records',
   );
   ```

2. **Session Timeout:**
   ```dart
   // Add inactivity timer
   Timer? _inactivityTimer;
   void resetInactivityTimer() {
     _inactivityTimer?.cancel();
     _inactivityTimer = Timer(Duration(minutes: 5), () {
       tbContext.logout();
     });
   }
   ```

3. **Audit Logging (Client-Side):**
   ```dart
   class AuditService {
     void logAccess(String resourceType, String action);
     void logDataView(String patientId, String dataType);
   }
   ```

4. **Certificate Pinning:**
   ```dart
   // In flutter_inappwebview settings
   await controller.setOptions(
     options: InAppWebViewGroupOptions(
       crossPlatform: InAppWebViewOptions(
         // Add certificate verification
       ),
     ),
   );
   ```

5. **Data Minimization:**
   - Remove unnecessary admin features entirely
   - Limit data exposure to patient's own records only

---

## 7. Recommendations for Healthcare Fork

### 7.1 Immediate Actions

1. **Fork and Rename:**
   - Fork from ThingsBoard repo
   - Rename package to `patient_health_app` or similar
   - Update all branding assets

2. **Lock Down User Role:**
   - Filter to `CUSTOMER_USER` authority only
   - Add server-side validation for Patient role

3. **Simplify Navigation:**
   - Reduce to 3 tabs: Dashboard, Records, Settings
   - Remove all admin/device management routes

### 7.2 Architecture Modifications

```
lib/
├── core/
│   ├── auth/          # Keep, add biometric
│   ├── context/
│   │   ├── tb_context.dart
│   │   └── health_context.dart  # NEW: Combined context
│   └── security/      # NEW: HIPAA security services
├── modules/
│   ├── dashboard/     # Keep for health dashboards
│   ├── records/       # NEW: FHIR health records
│   ├── vitals/        # NEW: Telemetry vitals display
│   └── settings/      # NEW: Patient settings
└── integrations/
    ├── thingsboard/   # Wrap existing TB client
    └── medplum/       # NEW: FHIR client integration
```

### 7.3 Suggested Package Additions

```yaml
dependencies:
  # Security
  local_auth: ^2.1.0          # Biometric authentication
  app_security: ^1.0.0        # Screen capture prevention
  
  # FHIR Integration
  fhir: ^0.9.0                # FHIR R4 models
  # or custom Medplum client
  
  # Offline Support
  sembast: ^3.6.0             # Local database for offline
  connectivity_plus: ^5.0.0   # Network monitoring
  
  # Accessibility
  flutter_tts: ^3.8.0         # Text-to-speech for vitals
```

### 7.4 Estimated Timeline

| Phase | Duration | Scope |
|-------|----------|-------|
| Phase 1 | 1-2 weeks | Strip admin features, lock to patient role |
| Phase 2 | 2-3 weeks | Add HIPAA security features |
| Phase 3 | 3-4 weeks | Integrate Medplum FHIR client |
| Phase 4 | 2-3 weeks | Build patient-specific UI/UX |
| Phase 5 | 2 weeks | Testing, security audit |

**Total Estimated Effort:** 10-14 weeks for MVP

---

## Appendix: Key File Reference

### Authentication
- `lib/core/auth/login/login_page.dart` - Main login UI
- `lib/core/auth/login/bloc/auth_bloc.dart` - Auth state management
- `lib/core/auth/oauth2/tb_oauth2_client.dart` - OAuth2 implementation
- `lib/utils/services/_tb_secure_storage.dart` - Token storage

### Core Context
- `lib/core/context/tb_context.dart` - Main app context, ThingsboardClient instantiation
- `lib/core/context/has_tb_context.dart` - Mixin for context access

### Navigation & Layout
- `lib/config/routes/router.dart` - All route definitions
- `lib/modules/main/main_page.dart` - Main scaffold with bottom nav
- `lib/utils/services/layouts/layout_service.dart` - Role-based page layouts
- `lib/modules/layout_pages/bloc/layout_pages_bloc.dart` - Navigation items builder

### Dashboard
- `lib/modules/dashboard/presentation/widgets/dashboard_widget.dart` - WebView dashboard
- `lib/modules/dashboard/presentation/controller/dashboard_controller.dart` - Dashboard control
- `lib/modules/dashboard/presentation/view/home_dashboard_page.dart` - Home dashboard

### Dependency Injection
- `lib/locator.dart` - Root DI setup
- `lib/modules/alarm/di/alarms_di.dart` - Example feature DI

---

*Report generated for internal technical assessment. Not for external distribution.*

