import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/core/network/nest_api_client.dart';
import 'package:thingsboard_app/core/network/nest_api_config.dart';
import 'package:thingsboard_app/core/network/nest_api_exceptions.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/di/patient_health_di.dart';
import 'package:thingsboard_app/modules/patient_health/domain/entities/vital_sign_entity.dart' as domain_entities;
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_event.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_state.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/view/vital_detail_page.dart';
import 'package:thingsboard_app/widgets/tb_app_bar.dart';

/// PATIENT APP: Patient Health Page
/// 
/// Main page for displaying patient health information.
/// This is the Home tab in the patient app's 3-tab navigation.

class PatientHealthPage extends TbContextWidget {
  PatientHealthPage(super.tbContext, {super.key});

  @override
  State<StatefulWidget> createState() => _PatientHealthPageState();
}

class _PatientHealthPageState extends TbContextState<PatientHealthPage>
    with AutomaticKeepAliveClientMixin<PatientHealthPage> {
  final _diScopeKey = UniqueKey();
  bool _isTestingConnection = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    
    // Initialize Patient Health module DI
    PatientHealthDi.init(
      _diScopeKey.toString(),
      tbClient: widget.tbContext.tbClient,
      logger: getIt(),
    );

    // Load patient health data when page initializes
    // Use the current user's ID as the patient ID
    // Dispatch the event after the frame is built to ensure BlocProvider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = widget.tbContext.tbClient.getAuthUser()?.userId;
      if (userId != null) {
        getIt<PatientBloc>().add(
          PatientLoadHealthSummaryEvent(patientId: userId),
        );
      } else {
        // Fallback: use a default patient ID for mock mode
        // In mock mode, the repository will return mock data regardless of ID
        getIt<PatientBloc>().add(
          const PatientLoadHealthSummaryEvent(patientId: 'mock-patient-001'),
        );
      }
    });
  }

  /// PATIENT APP: Test connection to NestJS BFF server
  Future<void> _testNestConnection() async {
    if (_isTestingConnection) return;

    setState(() => _isTestingConnection = true);

    final logger = getIt<TbLogger>();
    final apiClient = getIt<NestApiClient>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    logger.debug('Testing NestJS BFF connection...');
    logger.debug('Base URL: ${NestApiConfig.baseUrl}');

    try {
      // Try to fetch patient profile from NestJS
      final response = await apiClient.get<Map<String, dynamic>>(
        NestApiConfig.patientProfile,
      );

      logger.debug('Connection test SUCCESS: $response');

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ Connection successful!\n'
            'Profile: ${response['firstName'] ?? response['name'] ?? 'N/A'}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } on NestApiException catch (e) {
      logger.error('Connection test FAILED: ${e.message}');

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            '❌ Connection failed: ${e.message}\n'
            'Status: ${e.statusCode}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e, s) {
      logger.error('Connection test ERROR', e, s);

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      setState(() => _isTestingConnection = false);
    }
  }

  /// PATIENT APP: Test fetching vitals from NestJS BFF
  Future<void> _testFetchVitals() async {
    if (_isTestingConnection) return;

    setState(() => _isTestingConnection = true);

    final logger = getIt<TbLogger>();
    final apiClient = getIt<NestApiClient>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    logger.debug('Testing NestJS vitals endpoint...');

    try {
      final response = await apiClient.get<Map<String, dynamic>>(
        NestApiConfig.patientVitalsLatest,
      );

      logger.debug('Vitals test SUCCESS: $response');

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ Vitals fetched!\n'
            'Data: ${response.keys.join(", ")}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } on NestApiException catch (e) {
      logger.error('Vitals test FAILED: ${e.message}');

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            '❌ Vitals failed: ${e.message}\n'
            'Status: ${e.statusCode}',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e, s) {
      logger.error('Vitals test ERROR', e, s);

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      setState(() => _isTestingConnection = false);
    }
  }

  @override
  void dispose() {
    PatientHealthDi.dispose(_diScopeKey.toString());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return BlocProvider<PatientBloc>.value(
      value: getIt(),
      child: Scaffold(
        appBar: TbAppBar(
          tbContext,
          title: const Text(
            'Patient Health',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                getIt<PatientBloc>().add(const PatientRefreshEvent());
              },
            ),
          ],
        ),
        body: BlocBuilder<PatientBloc, PatientState>(
          builder: (context, state) {
            return switch (state) {
              PatientInitialState() => _buildInitialView(),
              PatientLoadingState() => _buildLoadingView(),
              PatientHealthLoadedState() => _buildHealthSummaryView(state),
              PatientVitalSignsLoadedState() => _buildVitalSignsView(state),
              PatientHistoryLoadedState() => _buildHistoryView(state),
              PatientVitalHistoryLoadedState() => _buildInitialView(), // Not used in this page
              PatientErrorState() => _buildErrorView(state),
            };
          },
        ),
      ),
    );
  }

  Widget _buildInitialView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.health_and_safety,
            size: 64,
            color: Colors.teal,
          ),
          const SizedBox(height: 16),
          const Text(
            'Patient Health',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your health dashboard is loading...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 32),
          // PATIENT APP: Test Connection Buttons
          _buildTestConnectionSection(),
        ],
      ),
    );
  }

  /// PATIENT APP: Build test connection buttons for development
  Widget _buildTestConnectionSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'NestJS BFF Connection Test',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Base URL: ${NestApiConfig.baseUrl}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isTestingConnection ? null : _testNestConnection,
                  icon: _isTestingConnection
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi, size: 18),
                  label: const Text('Test Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isTestingConnection ? null : _testFetchVitals,
                  icon: _isTestingConnection
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.favorite, size: 18),
                  label: const Text('Test Vitals'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading your health data...'),
        ],
      ),
    );
  }

  Widget _buildHealthSummaryView(PatientHealthLoadedState state) {
    final summary = state.healthSummary;

    return RefreshIndicator(
      onRefresh: () async {
        getIt<PatientBloc>().add(const PatientRefreshEvent());
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient info card
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: Text(summary.patientName ?? 'Patient'),
                subtitle: Text(
                  'Last updated: ${summary.lastUpdated?.toString() ?? 'N/A'}',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Vital signs section
            const Text(
              'Vital Signs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (summary.vitalSigns.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'No vital signs data available.\n'
                      'Connect your health devices to see data here.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              ...summary.vitalSigns.map((vital) => Card(
                    child: InkWell(
                      onTap: () {
                        // Navigate to vital detail page
                        // Convert old VitalSignType to new VitalSignType enum
                        final newVitalType = _convertVitalSignType(vital.type);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => VitalDetailPage(
                              widget.tbContext,
                              vitalType: newVitalType,
                            ),
                          ),
                        );
                      },
                      child: ListTile(
                        leading: _getVitalSignIcon(vital.type),
                        title: Text(_getVitalSignName(vital.type)),
                        subtitle: Text(_formatVitalValue(vital.value, vital.unit)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            vital.isNormal
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : const Icon(Icons.warning, color: Colors.orange),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  )),

            const SizedBox(height: 16),

            // Recent observations section
            const Text(
              'Recent Observations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (summary.recentObservations.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'No recent clinical observations.\n'
                      'Your healthcare provider will add observations here.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              ...summary.recentObservations.map((obs) => Card(
                    child: ListTile(
                      title: Text(obs.displayName),
                      subtitle: Text(obs.value),
                      trailing: Text(
                        obs.effectiveDateTime.toString().split(' ')[0],
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalSignsView(PatientVitalSignsLoadedState state) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.vitalSigns.length,
      itemBuilder: (context, index) {
        final vital = state.vitalSigns[index];
        return Card(
          child: ListTile(
            leading: _getVitalSignIcon(vital.type),
            title: Text(_getVitalSignName(vital.type)),
            subtitle: Text(_formatVitalValue(vital.value, vital.unit)),
          ),
        );
      },
    );
  }

  /// Convert old VitalSignType (from repository) to new VitalSignType (from domain entities)
  domain_entities.VitalSignType _convertVitalSignType(VitalSignType oldType) {
    switch (oldType) {
      case VitalSignType.heartRate:
        return domain_entities.VitalSignType.heartRate;
      case VitalSignType.bloodPressureSystolic:
      case VitalSignType.bloodPressureDiastolic:
        return domain_entities.VitalSignType.bloodPressure;
      case VitalSignType.temperature:
        return domain_entities.VitalSignType.temperature;
      case VitalSignType.oxygenSaturation:
        return domain_entities.VitalSignType.oxygenSaturation;
      case VitalSignType.respiratoryRate:
        return domain_entities.VitalSignType.respiratoryRate;
      case VitalSignType.bloodGlucose:
        return domain_entities.VitalSignType.bloodGlucose;
      case VitalSignType.weight:
        return domain_entities.VitalSignType.weight;
    }
  }

  /// Format vital sign value to 1 decimal place for numeric values
  String _formatVitalValue(double value, String unit) {
    // Format to 1 decimal place for numeric values
    return '${value.toStringAsFixed(1)} $unit';
  }

  Widget _buildHistoryView(PatientHistoryLoadedState state) {
    return Center(
      child: Text(
        'Health History\n${state.history.dataPoints.length} data points',
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildErrorView(PatientErrorState state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            state.message,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              getIt<PatientBloc>().add(const PatientRefreshEvent());
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _getVitalSignIcon(VitalSignType type) {
    final iconData = switch (type) {
      VitalSignType.heartRate => Icons.favorite,
      VitalSignType.bloodPressureSystolic => Icons.speed,
      VitalSignType.bloodPressureDiastolic => Icons.speed,
      VitalSignType.temperature => Icons.thermostat,
      VitalSignType.oxygenSaturation => Icons.air,
      VitalSignType.respiratoryRate => Icons.airline_seat_flat,
      VitalSignType.bloodGlucose => Icons.bloodtype,
      VitalSignType.weight => Icons.monitor_weight,
    };

    return CircleAvatar(
      backgroundColor: Colors.teal.shade100,
      child: Icon(iconData, color: Colors.teal),
    );
  }

  String _getVitalSignName(VitalSignType type) {
    return switch (type) {
      VitalSignType.heartRate => 'Heart Rate',
      VitalSignType.bloodPressureSystolic => 'Blood Pressure (Systolic)',
      VitalSignType.bloodPressureDiastolic => 'Blood Pressure (Diastolic)',
      VitalSignType.temperature => 'Temperature',
      VitalSignType.oxygenSaturation => 'Oxygen Saturation',
      VitalSignType.respiratoryRate => 'Respiratory Rate',
      VitalSignType.bloodGlucose => 'Blood Glucose',
      VitalSignType.weight => 'Weight',
    };
  }
}

