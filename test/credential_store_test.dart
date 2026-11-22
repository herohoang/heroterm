import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/core/security/credential_store.dart';

void main() {
  group('InMemoryCredentialStore', () {
    test('write, read, delete round-trip by opaque id', () async {
      final store = InMemoryCredentialStore();
      await store.write('cred-1', 's3cret');
      expect(await store.read('cred-1'), 's3cret');
      await store.delete('cred-1');
      expect(await store.read('cred-1'), isNull);
    });

    test('unknown id reads as null', () async {
      final store = InMemoryCredentialStore();
      expect(await store.read('nope'), isNull);
    });
  });
}
