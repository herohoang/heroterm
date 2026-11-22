import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/server_monitor/domain/server_metrics.dart';

void main() {
  group('CpuSample.usagePercent', () {
    test('computes usage from the delta of two samples', () {
      const before = CpuSample(total: 1000, idle: 800);
      const after = CpuSample(total: 1200, idle: 900);
      // total +200, idle +100 => 50% busy.
      expect(CpuSample.usagePercent(before, after), 50.0);
    });

    test('returns null for non-advancing samples instead of faking 0', () {
      const sample = CpuSample(total: 1000, idle: 800);
      expect(CpuSample.usagePercent(sample, sample), isNull);
    });

    test('fully idle delta is a real 0', () {
      const before = CpuSample(total: 1000, idle: 800);
      const after = CpuSample(total: 1100, idle: 900);
      expect(CpuSample.usagePercent(before, after), 0.0);
    });
  });

  group('memoryUsedBytes (MemAvailable basis)', () {
    test('used = total - available', () {
      expect(memoryUsedBytes(totalBytes: 1000, availableBytes: 250), 750);
    });

    test('invalid inputs give null (unavailable), never a fake number', () {
      expect(memoryUsedBytes(totalBytes: null, availableBytes: 1), isNull);
      expect(memoryUsedBytes(totalBytes: 100, availableBytes: 200), isNull);
    });
  });

  group('ServerMetrics', () {
    test('unavailable factory carries no values', () {
      final metrics = ServerMetrics.unavailable(DateTime.utc(2026));
      expect(metrics.status, MetricsStatus.unavailable);
      expect(metrics.cpuPercent, isNull);
      expect(metrics.memoryUsedPercent, isNull);
    });
  });

  group('parseCpuSample', () {
    test('sums all jiffy fields; idle includes iowait', () {
      final sample = parseCpuSample('cpu  100 0 100 700 100 0 0 0 0 0');
      expect(sample, isNotNull);
      expect(sample!.total, 1000);
      expect(sample.idle, 800);
    });

    test('rejects non-cpu lines and malformed fields', () {
      expect(parseCpuSample('cpu0 1 2 3 4'), isNull);
      expect(parseCpuSample('cpu 1 2 x 4'), isNull);
      expect(parseCpuSample(''), isNull);
    });
  });

  group('parseMemInfoBytes', () {
    const meminfo = '''
MemTotal:        4000000 kB
MemFree:          500000 kB
MemAvailable:    1000000 kB
''';

    test('reads kB entries as bytes', () {
      expect(parseMemInfoBytes(meminfo, 'MemTotal'), 4000000 * 1024);
      expect(parseMemInfoBytes(meminfo, 'MemAvailable'), 1000000 * 1024);
    });

    test('missing entry is null, not a fabricated number', () {
      expect(parseMemInfoBytes(meminfo, 'SwapTotal'), isNull);
      expect(parseMemInfoBytes('garbage', 'MemTotal'), isNull);
    });
  });

  group('parseDfUsedPercent', () {
    test('reads the Capacity column of df -P output', () {
      const df = '''
Filesystem     1024-blocks     Used Available Capacity Mounted on
/dev/sda1        1000000   450000    550000      45% /
''';
      expect(parseDfUsedPercent(df), 45.0);
    });

    test('header-only or garbage output is null', () {
      expect(parseDfUsedPercent('Filesystem 1024-blocks Used'), isNull);
      expect(parseDfUsedPercent(''), isNull);
    });
  });
}
