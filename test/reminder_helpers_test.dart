import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/data/models/enums.dart';
import 'package:mudhakkarati/features/reminders/reminder_helpers.dart';
import 'package:mudhakkarati/features/reminders/standalone_reminder_dialog.dart';

void main() {
  group('importance helpers', () {
    test('impIcon is distinct per importance level', () {
      final icons = ReminderImportance.values.map(impIcon).toSet();
      expect(icons.length, ReminderImportance.values.length);
    });

    test('impColor is distinct per importance level', () {
      final colors =
          ReminderImportance.values.map((i) => impColor(i).value).toSet();
      expect(colors.length, ReminderImportance.values.length);
    });
  });

  group('toneName', () {
    test('known catalog id resolves to a friendly display name', () {
      // الافتراضي ocean = Ocean Whisper — يجب أن يختلف عن المعرّف الخام.
      expect(toneName('ocean'), isNot('ocean'));
      expect(toneName('ocean').trim(), isNotEmpty);
    });

    test('unknown id falls back to the id itself', () {
      expect(toneName('___not_a_real_tone___'), '___not_a_real_tone___');
    });
  });

  group('ReminderKind extension', () {
    test('label and titleLabel are non-empty for every kind', () {
      for (final k in ReminderKind.values) {
        expect(k.label.trim(), isNotEmpty, reason: '$k.label');
        expect(k.titleLabel.trim(), isNotEmpty, reason: '$k.titleLabel');
      }
    });

    test('labels are distinct across kinds', () {
      expect(ReminderKind.values.map((k) => k.label).toSet().length,
          ReminderKind.values.length);
    });

    test('icons are distinct across kinds', () {
      expect(ReminderKind.values.map((k) => k.icon).toSet().length,
          ReminderKind.values.length);
    });

    test('emoji is empty only for the general kind', () {
      expect(ReminderKind.general.emoji, isEmpty);
      for (final k
          in ReminderKind.values.where((k) => k != ReminderKind.general)) {
        expect(k.emoji.trim(), isNotEmpty, reason: '$k.emoji');
      }
    });
  });
}
