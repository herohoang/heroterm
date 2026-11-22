import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/server_monitor/domain/server_metrics.dart';
import 'package:heroterm/features/server_monitor/presentation/server_metrics_controller.dart';

String metricsOutput({required int cpuBusy, required int cpuIdle}) {
  final total = cpuBusy + cpuIdle;
  return '''
__HT_STAT__
cpu  $cpuBusy 0 0 $cpuIdle 0 0 0 0 0 0
__HT_MEM__
MemTotal:        4000000 kB
MemAvailable:    1000000 kB
__HT_DF__
Filesystem     1024-blocks     Used Available Capacity Mounted on
/dev/sda1        ${total * 1000}   450000    550000      45% /
''';
}

void main() {
  late ProviderContainer container;
  late ServerMetricsNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(serverMetricsProvider.notifier);
  });

  tearDown(() {
    notifier.stopPolling();
    container.dispose();
  });

  ServerMetrics state() => container.read(serverMetricsProvider);

  test('first poll reports memory/disk; CPU needs a second sample', () async {
    var calls = 0;
    notifier.startPolling((command) async {
      calls++;
      return metricsOutput(cpuBusy: 200, cpuIdle: 800);
    });
    await notifier.pollOnce();
    // startPolling already fired one poll; wait for it to settle.
    await Future<void>.delayed(Duration.zero);

    expect(state().status, MetricsStatus.available);
    expect(state().cpuPercent, isNull);
    expect(state().memoryTotalBytes, 4000000 * 1024);
    expect(state().memoryUsedBytes, 3000000 * 1024);
    expect(state().memoryUsedPercent, 75.0);
    expect(state().diskUsedPercent, 45.0);
    expect(calls, greaterThanOrEqualTo(1));
  });

  test('second poll computes CPU from the delta of two samples', () async {
    final outputs = [
      metricsOutput(cpuBusy: 200, cpuIdle: 800), // total 1000, idle 800
      metricsOutput(cpuBusy: 300, cpuIdle: 900), // total 1200, idle 900
    ];
    var index = 0;
    notifier.startPolling((command) async => outputs[index++]);
    await Future<void>.delayed(Duration.zero);
    await notifier.pollOnce();

    // Delta: total +200, idle +100 => 50% busy.
    expect(state().cpuPercent, 50.0);
    expect(state().status, MetricsStatus.available);
  });

  test('a failed poll after good data marks values stale', () async {
    var fail = false;
    notifier.startPolling((command) async {
      if (fail) throw StateError('boom');
      return metricsOutput(cpuBusy: 200, cpuIdle: 800);
    });
    await Future<void>.delayed(Duration.zero);
    expect(state().status, MetricsStatus.available);

    fail = true;
    await notifier.pollOnce();
    expect(state().status, MetricsStatus.stale);
    expect(state().memoryTotalBytes, 4000000 * 1024);
  });

  test('failures before any data keep metrics unavailable', () async {
    notifier.startPolling((command) async => throw StateError('boom'));
    await Future<void>.delayed(Duration.zero);
    await notifier.pollOnce();
    expect(state().status, MetricsStatus.unavailable);
    expect(state().hasValues, isFalse);
  });

  test(
    'the first failed attempt still shows collecting, not a verdict',
    () async {
      notifier.startPolling((command) async => throw StateError('boom'));
      await Future<void>.delayed(Duration.zero);
      expect(state().status, MetricsStatus.collecting);
    },
  );

  test('unparsable output is unavailable, never fabricated', () async {
    notifier.startPolling((command) async => 'hello from an odd server');
    await Future<void>.delayed(Duration.zero);
    await notifier.pollOnce();
    expect(state().status, MetricsStatus.unavailable);
    expect(state().cpuPercent, isNull);
  });

  test('stopPolling clears values and stops the timer', () async {
    notifier.startPolling(
      (command) async => metricsOutput(cpuBusy: 200, cpuIdle: 800),
    );
    await Future<void>.delayed(Duration.zero);
    expect(state().status, MetricsStatus.available);
    expect(notifier.isPolling, isTrue);

    notifier.stopPolling();
    expect(notifier.isPolling, isFalse);
    expect(state().status, MetricsStatus.unavailable);
    expect(state().hasValues, isFalse);
  });
}
