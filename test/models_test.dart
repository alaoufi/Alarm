import 'package:flutter_test/flutter_test.dart';
import 'package:mudhakkarati/data/models/category.dart';
import 'package:mudhakkarati/data/models/checklist_item.dart';
import 'package:mudhakkarati/data/models/enums.dart';
import 'package:mudhakkarati/data/models/med_dose.dart';
import 'package:mudhakkarati/data/models/note.dart';

void main() {
  group('Note serialization', () {
    test('full roundtrip preserves every persisted field', () {
      final created = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final updated = DateTime.fromMillisecondsSinceEpoch(1700000500000);
      final deleted = DateTime.fromMillisecondsSinceEpoch(1700000900000);
      final n = Note(
        id: 5,
        uuid: 'abc-123',
        title: 'عنوان',
        content: 'محتوى',
        type: NoteType.checklist,
        color: 0xFF112233,
        isPinned: true,
        isFavorite: true,
        isArchived: true,
        isLocked: true,
        isDeleted: true,
        deletedAt: deleted,
        categoryId: 9,
        imagePath: '/img.png',
        audioPath: '/a.m4a',
        pdfPath: '/d.pdf',
        drawingPath: '/draw.png',
        bgStyle: 2,
        gradient: 'sunset',
        ruleOnLine: true,
        ruleThickness: 1.5,
        ruleOpacity: 0.4,
        ruleLineHeight: 1.8,
        createdAt: created,
        updatedAt: updated,
      );
      final back = Note.fromMap(n.toMap());
      expect(back.id, 5);
      expect(back.uuid, 'abc-123');
      expect(back.title, 'عنوان');
      expect(back.content, 'محتوى');
      expect(back.type, NoteType.checklist);
      expect(back.color, 0xFF112233);
      expect(back.isPinned, true);
      expect(back.isFavorite, true);
      expect(back.isArchived, true);
      expect(back.isLocked, true);
      expect(back.isDeleted, true);
      expect(back.deletedAt, deleted);
      expect(back.categoryId, 9);
      expect(back.imagePath, '/img.png');
      expect(back.audioPath, '/a.m4a');
      expect(back.pdfPath, '/d.pdf');
      expect(back.drawingPath, '/draw.png');
      expect(back.bgStyle, 2);
      expect(back.gradient, 'sunset');
      expect(back.ruleOnLine, true);
      expect(back.ruleThickness, 1.5);
      expect(back.ruleOpacity, 0.4);
      expect(back.ruleLineHeight, 1.8);
      expect(back.createdAt, created);
      expect(back.updatedAt, updated);
    });

    test('ruleOnLine tri-state (true/false/null) survives roundtrip', () {
      Note base() => Note(
            uuid: 'u',
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          );
      expect(Note.fromMap(base().copyWith(ruleOnLine: true).toMap()).ruleOnLine,
          true);
      expect(Note.fromMap(base().copyWith(ruleOnLine: false).toMap()).ruleOnLine,
          false);
      expect(Note.fromMap(base().toMap()).ruleOnLine, isNull);
    });

    test('unknown type falls back to text; missing flags default false', () {
      final n = Note.fromMap({
        'id': 1,
        'uuid': 'x',
        'title': 't',
        'content': '',
        'type': 'bogus_type',
        'created_at': 0,
        'updated_at': 0,
      });
      expect(n.type, NoteType.text);
      expect(n.isPinned, false);
      expect(n.isDeleted, false);
      expect(n.deletedAt, isNull);
      expect(n.color, isNull);
      expect(n.bgStyle, 0);
    });

    test('copyWith clear flags null out fields', () {
      final n = Note(
        uuid: 'u',
        color: 0xFFFFFFFF,
        gradient: 'g',
        categoryId: 3,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(1),
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final c = n.copyWith(
          clearColor: true,
          clearGradient: true,
          clearCategory: true,
          clearDeletedAt: true);
      expect(c.color, isNull);
      expect(c.gradient, isNull);
      expect(c.categoryId, isNull);
      expect(c.deletedAt, isNull);
    });
  });

  group('Category serialization', () {
    test('roundtrip preserves fields', () {
      const c = Category(
          id: 2, name: 'عمل', color: 0xFF00FF00, iconCode: 0xe5, position: 3);
      final back = Category.fromMap(c.toMap());
      expect(back.id, 2);
      expect(back.name, 'عمل');
      expect(back.color, 0xFF00FF00);
      expect(back.iconCode, 0xe5);
      expect(back.position, 3);
    });

    test('defaults applied for missing color/icon/position/name', () {
      final c = Category.fromMap({'id': 1});
      expect(c.name, '');
      expect(c.color, 0xFF9E9E9E);
      expect(c.iconCode, 7);
      expect(c.position, 0);
    });
  });

  group('MedDose serialization', () {
    test('taken/missed status maps both ways', () {
      final taken = MedDose(
          name: 'دواء',
          dose: '500mg',
          taken: true,
          at: DateTime.fromMillisecondsSinceEpoch(1000));
      expect(taken.toMap()['status'], 'taken');
      expect(MedDose.fromMap(taken.toMap()).taken, true);

      final missed = taken.toMap()..['status'] = 'missed';
      expect(MedDose.fromMap(missed).taken, false);
    });

    test('missing status/name/at do not crash (corrupt/partial rows)', () {
      final d = MedDose.fromMap({'name': null}); // no 'at' column at all
      expect(d.taken, true);
      expect(d.name, '');
      expect(d.dose, isNull);
      expect(d.at.millisecondsSinceEpoch, 0);
    });
  });

  group('ChecklistItem serialization', () {
    test('roundtrip incl. is_task and is_done', () {
      const item = ChecklistItem(
          id: 4,
          noteId: 7,
          text: 'مهمة',
          isDone: true,
          position: 2,
          isTask: false);
      final back = ChecklistItem.fromMap(item.toMap());
      expect(back.noteId, 7);
      expect(back.text, 'مهمة');
      expect(back.isDone, true);
      expect(back.position, 2);
      expect(back.isTask, false);
    });

    test('is_task defaults to true (legacy rows had no column)', () {
      final item = ChecklistItem.fromMap({
        'note_id': 1,
        'text': 'x',
        'is_done': 0,
        'position': 0,
      });
      expect(item.isTask, true);
    });
  });

  group('enum fromDb fallbacks', () {
    test('NoteType', () {
      expect(NoteTypeX.fromDb('audio'), NoteType.audio);
      expect(NoteTypeX.fromDb(null), NoteType.text);
      expect(NoteTypeX.fromDb('nope'), NoteType.text);
    });
    test('ReminderRepeat', () {
      expect(ReminderRepeatX.fromDb('weekly'), ReminderRepeat.weekly);
      expect(ReminderRepeatX.fromDb(null), ReminderRepeat.once);
      expect(ReminderRepeatX.fromDb('nope'), ReminderRepeat.once);
    });
    test('ReminderImportance', () {
      expect(ReminderImportanceX.fromDb('critical'),
          ReminderImportance.critical);
      expect(ReminderImportanceX.fromDb(null), ReminderImportance.high);
      expect(ReminderImportanceX.fromDb('nope'), ReminderImportance.high);
    });
  });
}
