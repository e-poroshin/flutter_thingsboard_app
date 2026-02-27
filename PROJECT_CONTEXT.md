Project Context: ThingsBoard Patient Health App (Flutter)
1. Project Overview
This is a Flutter-based mobile application integrating with the ThingsBoard IoT platform. The current focus is on the Patient Health Module, which allows users to monitor vital signs. The core feature being developed is the integration of BLE (Bluetooth Low Energy) sensors, specifically the Xiaomi LYWSD03MMC temperature and humidity sensor flashed with custom PVVX/ATC firmware.

2. Tech Stack

- Framework: Flutter (Dart).

- State Management: flutter_bloc (BLoC pattern).

- DI (Dependency Injection): get_it.

- BLE: flutter_blue_plus.

- Local Storage: hive (for caching paired device IDs and tasks).

- Backend: ThingsBoard (via REST API) + NestJS BFF (Best-for-Frontend).

3. Architecture & Key Decisions

- Global Singleton BLoC: The PatientBloc is registered as a Lazy Singleton in GetIt and provided globally at the MaterialApp level (in thingsboard_app.dart using BlocProvider.value). This ensures the BLoC remains alive throughout the app's lifecycle to maintain the BLE connection and data stream, preventing "poisoned singleton" issues during navigation.

- Clean Architecture: Separation of concerns into Presentation (Pages, BLoCs), Domain (Entities, Repositories), and Data (Datasources, Models).

- Navigation: Uses a main dashboard (PatientHealthPage) and a settings/profile area. The BLE scanning UI (SensorScanPage) is a separate route.

4. BLE Implementation Details

- Sensor Target: Xiaomi LYWSD03MMC with custom ATC firmware.

- Scanning: Filters for Service UUID 0x181A (Environmental Sensing) or specific manufacturer data.

- Data Parsing: The app parses custom advertisement data (Big Endian format) to extract Temperature and Humidity in real-time.

- Pairing Logic:

1) User scans and selects a device in SensorScanPage.

2) Device ID (MAC address) is persisted to Hive via PatientLocalDatasource.

3) PatientBloc detects the new ID, stops previous scans, and starts a dedicated listener for this specific device.

4) Scanning is not stopped immediately upon pairing to ensure the Bloc can pick up the stream seamlessly.

5. Current Status (Working Features)

✅ Real-time Monitoring: The app successfully connects to the sensor, parses data, and updates the PatientHealthPage UI with live temperature/humidity.

✅ Persistence: The paired sensor ID is saved. On app restart, the PatientBloc automatically reconnects.

✅ State Handling: Fixed issues where the Dashboard would get stuck in Loading state. Now, adding a sensor forces a PatientLoadHealthSummaryEvent, ensuring the UI and BLoC state (PatientHealthLoadedState) are synchronized.

✅ Navigation Stability: The BLE stream survives tab switching and navigation between Home and Profile screens.

6. Next Objective (Current Task)
We are moving from "Real-time only" to "Historical Data Sync".

- Goal: Connect to the sensor via GATT, access its internal Flash memory (using the PVVX custom service 0x1F10), download historical data points (timestamp + value), and persist them locally in Hive to display charts.

- Protocol: We need to implement the specific Read/Notify sequence for the PVVX history characteristic (0x1F11).