import '../domain/server_metrics.dart';

/// Runs one command on the remote host and returns its stdout —
/// satisfied by `RemoteConnection.runCommand` in production and by
/// fakes in tests.
typedef MetricsCommandRunner = Future<String> Function(String command);

/// The outcome of one metrics fetch: the parsed metrics plus the raw
/// CPU sample the caller keeps for the next delta calculation.
final class MetricsFetch {
  const MetricsFetch({required this.metrics, required this.cpuSample});

  final ServerMetrics metrics;
  final CpuSample? cpuSample;
}

/// Fetches remote server metrics with a single read-only, time-bounded
/// exec command (Milestone 6, FEATURE_SPEC section 8, ADR-005):
///
/// * CPU — the aggregate line of `/proc/stat`; a percentage needs two
///   samples, so the first fetch reports memory/disk only.
/// * Memory — `/proc/meminfo`, used = MemTotal − MemAvailable.
/// * Disk — `df -P /`, the portable one-line-per-filesystem form.
///
/// A section that comes back missing or unparsable yields null values
/// for that metric only; when nothing at all parses, the result has
/// status `unavailable` — values are never fabricated.
final class ServerMetricsService {
  const ServerMetricsService();

  /// One round trip with section markers. Read-only commands only.
  static const command =
      "printf '__HT_STAT__\\n'; head -n 1 /proc/stat; "
      "printf '__HT_MEM__\\n'; cat /proc/meminfo; "
      "printf '__HT_DF__\\n'; df -P /";

  static const _timeout = Duration(seconds: 10);

  Future<MetricsFetch> fetch(
    MetricsCommandRunner run, {
    required CpuSample? previousCpu,
    required DateTime now,
  }) async {
    final output = await run(command).timeout(_timeout);
    final sections = _splitSections(output);

    final cpuSample = sections['stat'] == null
        ? null
        : parseCpuSample(sections['stat']!.trim().split('\n').first);
    final cpuPercent = cpuSample == null || previousCpu == null
        ? null
        : CpuSample.usagePercent(previousCpu, cpuSample);

    int? memoryTotal;
    int? memoryUsed;
    final meminfo = sections['mem'];
    if (meminfo != null) {
      memoryTotal = parseMemInfoBytes(meminfo, 'MemTotal');
      final available = parseMemInfoBytes(meminfo, 'MemAvailable');
      memoryUsed = memoryUsedBytes(
        totalBytes: memoryTotal,
        availableBytes: available,
      );
      if (memoryUsed == null) memoryTotal = null;
    }

    final diskUsedPercent = sections['df'] == null
        ? null
        : parseDfUsedPercent(sections['df']!);

    final metrics = ServerMetrics(
      cpuPercent: cpuPercent,
      memoryUsedBytes: memoryUsed,
      memoryTotalBytes: memoryTotal,
      diskUsedPercent: diskUsedPercent,
      sampledAt: now,
      status:
          (cpuSample != null || memoryTotal != null || diskUsedPercent != null)
          ? MetricsStatus.available
          : MetricsStatus.unavailable,
    );
    return MetricsFetch(metrics: metrics, cpuSample: cpuSample);
  }

  Map<String, String> _splitSections(String output) {
    final sections = <String, StringBuffer>{};
    String? current;
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed == '__HT_STAT__' ||
          trimmed == '__HT_MEM__' ||
          trimmed == '__HT_DF__') {
        current = trimmed.substring(5, trimmed.length - 2).toLowerCase();
        sections[current] = StringBuffer();
        continue;
      }
      if (current != null) sections[current]!.writeln(line);
    }
    return sections.map((key, value) => MapEntry(key, value.toString()));
  }
}
