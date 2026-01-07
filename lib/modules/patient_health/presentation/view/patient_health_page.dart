import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/patient_health/di/patient_health_di.dart';
import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_bloc.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_event.dart';
import 'package:thingsboard_app/modules/patient_health/presentation/bloc/patient_state.dart';
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    PatientHealthDi.init(
      _diScopeKey.toString(),
      tbClient: widget.tbContext.tbClient,
      logger: getIt(),
    );

    // Load patient health data when page initializes
    // Use the current user's ID as the patient ID
    final userId = widget.tbContext.tbClient.getAuthUser()?.userId;
    if (userId != null) {
      getIt<PatientBloc>().add(
        PatientLoadHealthSummaryEvent(patientId: userId),
      );
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
              PatientErrorState() => _buildErrorView(state),
            };
          },
        ),
      ),
    );
  }

  Widget _buildInitialView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.health_and_safety,
            size: 64,
            color: Colors.teal,
          ),
          SizedBox(height: 16),
          Text(
            'Patient Health',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Your health dashboard is loading...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
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
                    child: ListTile(
                      leading: _getVitalSignIcon(vital.type),
                      title: Text(_getVitalSignName(vital.type)),
                      subtitle: Text('${vital.value} ${vital.unit}'),
                      trailing: vital.isNormal
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.warning, color: Colors.orange),
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
            subtitle: Text('${vital.value} ${vital.unit}'),
          ),
        );
      },
    );
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

