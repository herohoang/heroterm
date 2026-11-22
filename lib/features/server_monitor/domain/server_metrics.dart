enum MetricsStatus { available, stale, unavailable, collecting }

/// Metrics describing the *remote* host, never the local Mac (ADR-005).
final class ServerMetrics {
  const ServerMetrics({
    this.cpuPercent,
    this.memoryUsedBytes,
    this.memoryTotalBytes,
    this.diskUsedPercent,
    required this.sampledAt,
    this.status = MetricsStatus.unavailable,
  });

  factory ServerMetrics.unavailable(DateTime now) =>
      ServerMetrics(sampledAt: now, status: MetricsStatus.unavailable);

  final double? cpuPercent;
  final int? memoryUsedBytes;
  final int? memoryTotalBytes;
  final double? diskUsedPercent;
  final DateTime sampledAt;
  final MetricsStatus status;

  double? get memoryUsedPercent {
    final used = memoryUsedBytes;
    final total = memoryTotalBytes;
    if (used == null || total == null || total <= 0) return null;
    return used / total * 100;
  }

  ServerMetrics copyWith({MetricsStatus? status}) {
    return ServerMetrics(
      cpuPercent: cpuPercent,
      memoryUsedBytes: memoryUsedBytes,
      memoryTotalBytes: memoryTotalBytes,
      diskUsedPercent: diskUsedPercent,
      sampledAt: sampledAt,
      status: status ?? this.status,
    );
  }

  /// True when at least one real value was measured.
  bool get hasValues =>
      cpuPercent != null || memoryTotalBytes != null || diskUsedPercent != null;
}

/// One reading of the aggregate `cpu` line of Linux `/proc/stat`:
/// cumulative jiffies, split into total and idle (+iowait).
final class CpuSample {
  const CpuSample({required this.total, required this.idle});

  final int total;
  final int idle;

  /// CPU usage percentage between two samples (delta method required by
  /// FEATURE_SPEC section 8 / TEST_PLAN). Returns null when the samples
  /// do not advance, which callers must surface as unavailable/stale —
  /// never as a fabricated 0.
  static double? usagePercent(CpuSample previous, CpuSample current) {
    final totalDelta = current.total - previous.total;
    final idleDelta = current.idle - previous.idle;
    if (totalDelta <= 0 || idleDelta < 0 || idleDelta > totalDelta) {
      return null;
    }
    return (1 - idleDelta / totalDelta) * 100;
  }
}

/// Memory usage from `/proc/meminfo`, using `MemAvailable` as the basis
/// for estimated used memory (FEATURE_SPEC section 8).
int? memoryUsedBytes({required int? totalBytes, required int? availableBytes}) {
  if (totalBytes == null || availableBytes == null) return null;
  if (totalBytes < 0 || availableBytes < 0 || availableBytes > totalBytes) {
    return null;
  }
  return totalBytes - availableBytes;
}

/// Parses the aggregate `cpu` line of `/proc/stat` into a [CpuSample].
/// Total is the sum of every jiffy field; idle is idle + iowait.
/// Returns null for anything that is not a well-formed cpu line —
/// callers surface that as unavailable, never as a fabricated sample.
CpuSample? parseCpuSample(String line) {
  final parts = line.trim().split(RegExp(r'\s+'));
  if (parts.length < 5 || parts.first != 'cpu') return null;
  final fields = <int>[];
  for (final part in parts.skip(1)) {
    final value = int.tryParse(part);
    if (value == null || value < 0) return null;
    fields.add(value);
  }
  final total = fields.fold<int>(0, (sum, value) => sum + value);
  final idle = fields[3] + (fields.length > 4 ? fields[4] : 0);
  return CpuSample(total: total, idle: idle);
}

/// Reads one `Name: <value> kB` entry from `/proc/meminfo` content and
/// returns it in bytes. Null when the entry is absent or malformed.
int? parseMemInfoBytes(String meminfo, String name) {
  final match = RegExp(
    '^${RegExp.escape(name)}:\\s+(\\d+)\\s*kB',
    multiLine: true,
  ).firstMatch(meminfo);
  if (match == null) return null;
  final kb = int.tryParse(match.group(1)!);
  return kb == null ? null : kb * 1024;
}

/// Parses the used-percentage for the filesystem in `df -P` output
/// (header line plus one line per filesystem; the last non-empty line
/// is the reading). Null when no percentage column is present.
double? parseDfUsedPercent(String dfOutput) {
  final lines = dfOutput
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 2) return null;
  for (final token in lines.last.split(RegExp(r'\s+'))) {
    if (token.endsWith('%')) {
      return double.tryParse(token.substring(0, token.length - 1));
    }
  }
  return null;
}
