/// A saved host-key entry (OpenSSH-style known_hosts, ADR-004).
///
/// The fingerprint is the OpenSSH SHA256 form (`SHA256:<base64>`),
/// exactly as presented by the SSH stack during verification.
final class KnownHostEntry {
  const KnownHostEntry({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
  });

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;

  String get key => '$host:$port';

  Map<String, Object?> toJson() => <String, Object?>{
    'host': host,
    'port': port,
    'keyType': keyType,
    'fingerprint': fingerprint,
  };

  factory KnownHostEntry.fromJson(Map<String, Object?> json) {
    return KnownHostEntry(
      host: json['host']! as String,
      port: (json['port'] as num?)?.toInt() ?? 22,
      keyType: json['keyType']! as String,
      fingerprint: json['fingerprint']! as String,
    );
  }
}

enum HostKeyDecision {
  /// Presented key matches the saved entry: connect silently.
  match,

  /// No saved entry: the user must explicitly trust this key.
  unknown,

  /// A different key was presented for a known host: block the
  /// connection (possible man-in-the-middle, SECURITY.md).
  changed,
}

HostKeyDecision decideHostKey(
  KnownHostEntry? stored, {
  required String keyType,
  required String fingerprint,
}) {
  if (stored == null) return HostKeyDecision.unknown;
  if (stored.keyType == keyType && stored.fingerprint == fingerprint) {
    return HostKeyDecision.match;
  }
  return HostKeyDecision.changed;
}
