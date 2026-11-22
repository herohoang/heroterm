import 'dart:convert';
import 'dart:io';

import '../domain/host_key.dart';

/// Persistence for trusted host keys. Stored separately from session
/// metadata so trust decisions are never mixed with profile data.
abstract interface class KnownHostsStore {
  Future<KnownHostEntry?> lookup(String host, int port);
  Future<void> save(KnownHostEntry entry);
  Future<void> remove(String host, int port);
}

final class InMemoryKnownHostsStore implements KnownHostsStore {
  InMemoryKnownHostsStore([Iterable<KnownHostEntry> initial = const []])
    : _entries = {for (final e in initial) e.key: e};

  final Map<String, KnownHostEntry> _entries;

  @override
  Future<KnownHostEntry?> lookup(String host, int port) async =>
      _entries['$host:$port'];

  @override
  Future<void> save(KnownHostEntry entry) async {
    _entries[entry.key] = entry;
  }

  @override
  Future<void> remove(String host, int port) async {
    _entries.remove('$host:$port');
  }
}

/// JSON-file known-hosts store (`heroterm-known-hosts.json` in the
/// application support directory), written atomically like the
/// session library (ADR-006 pattern).
final class JsonFileKnownHostsStore implements KnownHostsStore {
  JsonFileKnownHostsStore(this._resolveDirectory);

  final Future<Directory> Function() _resolveDirectory;
  Map<String, KnownHostEntry>? _cache;

  Future<Map<String, KnownHostEntry>> _load() async {
    if (_cache != null) return _cache!;
    final dir = await _resolveDirectory();
    final file = File('${dir.path}/heroterm-known-hosts.json');
    final entries = <String, KnownHostEntry>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final item in decoded.whereType<Map<String, Object?>>()) {
            final entry = KnownHostEntry.fromJson(item);
            entries[entry.key] = entry;
          }
        }
      } on FormatException {
        // A corrupt trust store must not silently trust anything:
        // start empty so every host is treated as unknown and the
        // user is prompted again.
      }
    }
    return _cache = entries;
  }

  Future<void> _persist() async {
    final dir = await _resolveDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/heroterm-known-hosts.json');
    final tmp = File('${file.path}.tmp');
    final payload = _cache!.values.map((e) => e.toJson()).toList();
    await tmp.writeAsString(jsonEncode(payload), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<KnownHostEntry?> lookup(String host, int port) async =>
      (await _load())['$host:$port'];

  @override
  Future<void> save(KnownHostEntry entry) async {
    (await _load())[entry.key] = entry;
    await _persist();
  }

  @override
  Future<void> remove(String host, int port) async {
    (await _load()).remove('$host:$port');
    await _persist();
  }
}
