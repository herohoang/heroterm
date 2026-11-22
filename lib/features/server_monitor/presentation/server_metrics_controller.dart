import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connection/presentation/terminal_sessions.dart';
import '../data/server_metrics_service.dart';
import '../domain/server_metrics.dart';

final serverMetricsProvider =
    NotifierProvider<ServerMetricsNotifier, ServerMetrics>(
      ServerMetricsNotifier.new,
    );

/// Polls the connected remote server for CPU/memory/disk metrics
/// (Milestone 6).
///
/// * Polls every [pollInterval] (inside the spec's 3–5 s window),
///   never overlapping: a tick while a fetch is in flight is skipped.
/// * Starts when a connection becomes live and stops on disconnect,
///   resetting to `unavailable` — the footer never shows numbers for
///   a server that is no longer connected.
/// * A failed fetch keeps the last good values marked `stale`; with
///   no good values yet, the state stays `unavailable`. Failures here
///   never touch the terminal or explorer.
final class ServerMetricsNotifier extends Notifier<ServerMetrics> {
  static const pollInterval = Duration(seconds: 4);

  final _service = const ServerMetricsService();
  Timer? _timer;
  MetricsCommandRunner? _runner;
  CpuSample? _previousCpu;
  bool _inFlight = false;
  bool _hasValues = false;
  int _completedPolls = 0;

  @override
  ServerMetrics build() {
    ref.onDispose(() => _timer?.cancel());
    // Metrics always describe the ACTIVE tab's server: polling
    // (re)starts when the active tab becomes connected or when the
    // user switches to another connected tab, and stops when the
    // active tab leaves the connected state.
    ref.listen(sessionManagerProvider, (previous, next) {
      final wasLive = previous?.activeTab?.isConnected ?? false;
      final isLive = next.activeTab?.isConnected ?? false;
      final tabChanged = previous?.activeTabId != next.activeTabId;
      if (isLive && (!wasLive || tabChanged)) {
        final tabId = next.activeTabId!;
        startPolling(
          (command) => ref
              .read(sessionManagerProvider.notifier)
              .runCommandFor(tabId, command),
        );
      } else if (!isLive && wasLive) {
        stopPolling();
      }
    });
    return ServerMetrics.unavailable(DateTime.now());
  }

  /// Starts polling with [runner] (also used directly by tests).
  /// Polls immediately, then on the interval.
  void startPolling(MetricsCommandRunner runner) {
    _timer?.cancel();
    _runner = runner;
    _previousCpu = null;
    _hasValues = false;
    _completedPolls = 0;
    state = ServerMetrics(
      sampledAt: DateTime.now(),
      status: MetricsStatus.collecting,
    );
    unawaited(pollOnce());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(pollOnce()));
  }

  /// Stops polling and clears the displayed metrics.
  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    _runner = null;
    _previousCpu = null;
    _hasValues = false;
    _completedPolls = 0;
    state = ServerMetrics.unavailable(DateTime.now());
  }

  bool get isPolling => _timer != null;

  /// One fetch cycle. Public for tests; the timer calls it too.
  Future<void> pollOnce() async {
    final runner = _runner;
    if (runner == null || _inFlight) return;
    _inFlight = true;
    try {
      final fetch = await _service.fetch(
        runner,
        previousCpu: _previousCpu,
        now: DateTime.now(),
      );
      if (fetch.cpuSample != null) _previousCpu = fetch.cpuSample;
      if (fetch.metrics.status == MetricsStatus.available) {
        state = fetch.metrics;
        _hasValues = _hasValues || fetch.metrics.hasValues;
      } else {
        _markStaleOrUnavailable();
      }
    } catch (_) {
      // Transport/parse/timeout failure: metrics degrade, the
      // connection itself is unaffected.
      _markStaleOrUnavailable();
    } finally {
      _inFlight = false;
      _completedPolls++;
    }
  }

  void _markStaleOrUnavailable() {
    if (_hasValues) {
      state = state.copyWith(status: MetricsStatus.stale);
    } else if (_completedPolls >= 1) {
      // At least two attempts produced nothing (this one plus the
      // ones before it): the server cannot report metrics.
      state = ServerMetrics.unavailable(DateTime.now());
    }
    // Otherwise stay in `collecting`: the first attempts are still
    // in flight and the footer shows a loading state, not a verdict.
  }
}
