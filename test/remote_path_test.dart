import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/remote_explorer/domain/remote_path.dart';

void main() {
  group('RemotePath.normalize', () {
    test('collapses slashes, dots, and dotdots', () {
      expect(RemotePath.normalize('/a//b/./c'), '/a/b/c');
      expect(RemotePath.normalize('/a/b/../c'), '/a/c');
      expect(RemotePath.normalize('/../..'), '/');
      expect(RemotePath.normalize('/'), '/');
    });

    test('keeps spaces and unicode segments intact', () {
      expect(
        RemotePath.normalize('/home/user/tài liệu'),
        '/home/user/tài liệu',
      );
    });
  });

  group('RemotePath breadcrumbs', () {
    test('ancestors are root-first and include the path itself', () {
      expect(RemotePath.ancestorsOf('/a/b/c'), ['/', '/a', '/a/b', '/a/b/c']);
      expect(RemotePath.ancestorsOf('/'), ['/']);
    });

    test('parent navigation stops at root', () {
      expect(RemotePath.parentOf('/a/b'), '/a');
      expect(RemotePath.parentOf('/a'), '/');
      expect(RemotePath.parentOf('/'), '/');
    });
  });

  group('RemotePath.validateNewName', () {
    test('rejects empty, dot names, and separators', () {
      expect(RemotePath.validateNewName(''), isNotNull);
      expect(RemotePath.validateNewName('.'), isNotNull);
      expect(RemotePath.validateNewName('..'), isNotNull);
      expect(RemotePath.validateNewName('a/b'), isNotNull);
      expect(RemotePath.validateNewName(r'a\b'), isNotNull);
    });

    test('accepts ordinary names with spaces and unicode', () {
      expect(RemotePath.validateNewName('file name 1.txt'), isNull);
      expect(RemotePath.validateNewName('tài-liệu.md'), isNull);
    });
  });
}
