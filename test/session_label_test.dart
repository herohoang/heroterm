import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/sessions/domain/session_label.dart';

void main() {
  group('SessionLabel helpers (ADR-013)', () {
    test('canonical environment names keep their colours', () {
      expect(labelColorForName('Production'), labelPalette[0]);
      expect(labelColorForName(' production '), labelPalette[0]);
      expect(labelColorForName('Staging'), labelPalette[1]);
      expect(labelColorForName('Development'), labelPalette[5]);
    });

    test('other names get a stable palette colour', () {
      expect(labelColorForName('billing'), labelColorForName('Billing'));
      expect(labelPalette, contains(labelColorForName('anything')));
    });

    test('name normalization trims and single-spaces', () {
      expect(normalizeLabelName('  big   sale '), 'big sale');
      expect(normalizeLabelName('   '), '');
    });

    test('JSON round-trips', () {
      final label = SessionLabel(
        id: 'l1',
        name: 'Production',
        colorValue: labelPalette[0],
        createdAt: DateTime.utc(2026, 10, 25),
        updatedAt: DateTime.utc(2026, 10, 25),
      );
      final back = SessionLabel.fromJson(label.toJson());
      expect(back.id, 'l1');
      expect(back.name, 'Production');
      expect(back.colorValue, labelPalette[0]);
    });
  });
}
