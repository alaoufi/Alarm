import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/core/theme/note_gradient.dart';

/// يثبّت أنّ تدرّج الخلفية الافتراضيّ للتثبيت الجديد قابل للفكّ بألوانه الصحيحة
/// (FCE49E → EFE6C0 → E8E49E) واتجاه «أعلى لأسفل».
void main() {
  test('التدرّج الافتراضي للتثبيت الجديد', () {
    final g = NoteGradient.parse('0:${0xFFFCE49E},${0xFFEFE6C0},${0xFFE8E49E}');
    expect(g, isNotNull);
    expect(g!.direction, 0); // أعلى لأسفل
    expect(g.colors, [0xFFFCE49E, 0xFFEFE6C0, 0xFFE8E49E]);
  });
}
