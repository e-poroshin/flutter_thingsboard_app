import 'dart:async';

import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/patient_local_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/datasources/tb_telemetry_datasource.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/models.dart';
import 'package:thingsboard_app/modules/patient_health/data/models/vital_history_hive_model.dart';
import 'package:thingsboard_app/modules/patient_health/data/repositories/patient_repository_impl.dart';

/// PATIENT APP: Telemetry Sync Worker
///
/// Background service that flushes the Write-Ahead Log (WAL) by
/// uploading locally-persisted BLE measurements to the SmartBean Proxy.
///
/// **Dynamic Credentials:**
/// Instead of requiring static `deviceId`/`tenantId` at construction,
/// the worker resolves these at flush-time from [PatientRepositoryImpl]'s
/// cached user profile. This means:
/// - The worker can be registered in DI before the user logs in.
/// - If the user logs out (profile is null), flushes are silently skipped.
/// - If the profile has no `thingsboardDeviceId`, flushes are skipped.
///
/// **Lifecycle:**
/// 1. [start] — begins a periodic timer (default: every 60 s).
/// 2. Each tick calls [flushDirtyMeasurements].
/// 3. [stop] — cancels the timer (call on logout / dispose).
///
/// **Flush strategy:**
/// - Resolves `deviceId` and `tenantId` from the user profile.
/// - Fetches all [SyncStatus.dirty] items from Hive (FIFO order).
/// - Loops through them one-by-one:
///     • Marks item as [SyncStatus.syncing] (prevents double-send).
///     • Sends to POST /api/proxy/telemetry.
///     • On success → marks [SyncStatus.synced] and saves to Hive.
///     • On failure → reverts to [SyncStatus.dirty] and **stops the loop**
///       to preserve chronological order and retry on the next tick.
///
/// **Concurrency guard:**
/// A [_isFlushing] flag prevents overlapping flushes if a tick fires
/// while a previous flush is still in progress.
///
/// **Optional enhancement (TODO):**
/// Listen to `connectivity_plus` events to trigger an immediate flush
/// when the device transitions from offline → online, instead of
/// waiting for the next timer tick.

class TelemetrySyncWorker {
  TelemetrySyncWorker({
    required this.localDatasource,
    required this.telemetryDatasource,
    required this.repository,
    this.logger,
    this.flushInterval = const Duration(seconds: 60),
  });

  // ── Dependencies ──────────────────────────────────────────────────
  final PatientLocalDatasource localDatasource;
  final ITbTelemetryDatasource telemetryDatasource;
  final TbLogger? logger;

  /// The real repository — used to resolve the current user profile
  /// (and thus `thingsboardDeviceId` / `tenantId`) at flush-time.
  ///
  /// Uses [PatientRepositoryImpl] (not [IPatientRepository]) because
  /// [fetchUserProfile] is an implementation detail not exposed on the
  /// domain interface. The sync worker is a production-only component,
  /// so this tight coupling is acceptable.
  final PatientRepositoryImpl repository;

  /// How often the worker checks for dirty measurements.
  final Duration flushInterval;

  // ── Internal state ────────────────────────────────────────────────
  Timer? _timer;
  bool _isFlushing = false;
  bool _isRunning = false;

  /// Whether the worker is currently running.
  bool get isRunning => _isRunning;

  /// Whether a flush is currently in progress.
  bool get isFlushing => _isFlushing;

  // ── Lifecycle ─────────────────────────────────────────────────────

  /// Start the periodic sync timer.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops if
  /// the worker is already running.
  void start() {
    if (_isRunning) {
      logger?.debug('TelemetrySyncWorker: Already running, ignoring start()');
      return;
    }

    logger?.info(
      'TelemetrySyncWorker: Starting (interval: ${flushInterval.inSeconds}s)',
    );

    _isRunning = true;

    // Fire immediately on start, then periodically.
    unawaited(flushDirtyMeasurements());

    _timer = Timer.periodic(flushInterval, (_) {
      unawaited(flushDirtyMeasurements());
    });
  }

  /// Stop the periodic sync timer.
  ///
  /// Does NOT cancel an in-progress flush — it will finish naturally.
  void stop() {
    if (!_isRunning) return;

    logger?.info('TelemetrySyncWorker: Stopping');
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// Clean up resources. Call on app dispose / logout.
  void dispose() {
    stop();
    logger?.debug('TelemetrySyncWorker: Disposed');
  }

  // ── Core Flush Logic ──────────────────────────────────────────────

  /// Fetch all dirty measurements from Hive and push them to the backend.
  ///
  /// **Credential resolution:**
  /// Calls [repository.fetchUserProfile] to get the current `deviceId`
  /// and `tenantId`. If the profile is unavailable or has no
  /// `thingsboardDeviceId`, the flush is skipped gracefully.
  ///
  /// **Order guarantee:** Items are processed oldest-first (FIFO).
  /// If any item fails, the loop stops immediately so that
  /// chronological ordering is preserved on the backend.
  ///
  /// Returns the number of successfully synced items.
  Future<int> flushDirtyMeasurements() async {
    // ── Concurrency guard ────────────────────────────────────────
    if (_isFlushing) {
      logger?.debug(
        'TelemetrySyncWorker: Flush already in progress, skipping tick',
      );
      return 0;
    }

    _isFlushing = true;
    int syncedCount = 0;

    try {
      // ── Resolve credentials dynamically ────────────────────────
      final UserProfileDTO profile;
      try {
        profile = await repository.fetchUserProfile();
      } catch (e) {
        logger?.debug(
          'TelemetrySyncWorker: Cannot resolve user profile, '
          'skipping flush. Error: $e',
        );
        return 0;
      }

      if (!profile.hasThingsboardDevice) {
        logger?.debug(
          'TelemetrySyncWorker: No thingsboardDeviceId in profile, '
          'skipping flush',
        );
        return 0;
      }

      final deviceId = profile.thingsboardDeviceId!;
      final tenantId = profile.id; // tenant derived from user profile

      // ── Fetch dirty items ──────────────────────────────────────
      final dirtyItems = await localDatasource.getDirtyMeasurements();

      if (dirtyItems.isEmpty) {
        logger?.debug('TelemetrySyncWorker: No dirty measurements to sync');
        return 0;
      }

      logger?.info(
        'TelemetrySyncWorker: Flushing ${dirtyItems.length} dirty '
        'measurements (device: $deviceId)',
      );

      for (final item in dirtyItems) {
        try {
          // Mark as syncing (prevents double-send on next tick)
          item.syncStatus = SyncStatus.syncing;
          await item.save();

          // Build DTO and push
          final dto = TelemetryRequestDto.fromHiveModel(
            model: item,
            deviceId: deviceId,
            tenantId: tenantId,
          );

          await telemetryDatasource.pushTelemetry(dto);

          // ✅ Success — mark as synced
          item.syncStatus = SyncStatus.synced;
          await item.save();
          syncedCount++;

          logger?.debug(
            'TelemetrySyncWorker: Synced ${item.vitalType}=${item.value} '
            '@ ${item.timestamp.toIso8601String()}',
          );
        } catch (e) {
          // ❌ Failed — revert to dirty so the next tick retries
          item.syncStatus = SyncStatus.dirty;
          await item.save();

          logger?.warn(
            'TelemetrySyncWorker: Failed to sync ${item.vitalType}='
            '${item.value}. Stopping flush to preserve order. Error: $e',
          );

          // Stop the loop — don't skip ahead, preserve FIFO order
          break;
        }
      }

      if (syncedCount > 0) {
        logger?.info(
          'TelemetrySyncWorker: Flush complete — '
          '$syncedCount/${dirtyItems.length} synced',
        );
      }
    } catch (e, s) {
      logger?.error(
        'TelemetrySyncWorker: Unexpected error during flush',
        e,
        s,
      );
    } finally {
      _isFlushing = false;
    }

    return syncedCount;
  }

  /// Trigger an immediate flush (e.g., when connectivity is restored).
  ///
  /// This is a convenience method that simply delegates to
  /// [flushDirtyMeasurements]. It respects the concurrency guard.
  Future<int> syncNow() => flushDirtyMeasurements();
}
