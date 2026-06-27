-- مخطّط قاعدة بيانات «مذكراتي» (إصدار المخطّط 18)
-- ملاحظة: قاعدة التطبيق الفعليّة مشفّرة بالكامل (SQLCipher). هذا الملف هو
-- المخطّط المرجعيّ (بنية فقط، بلا تشفير وبلا بيانات) لتوثيق البنية.
PRAGMA foreign_keys = ON;

CREATE TABLE categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  color INTEGER NOT NULL,
  icon_code INTEGER NOT NULL,
  position INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',           -- Delta JSON (flutter_quill)
  type TEXT NOT NULL DEFAULT 'text',          -- text/checklist/image/audio/pdf/drawing/password
  color INTEGER,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  is_favorite INTEGER NOT NULL DEFAULT 0,
  is_archived INTEGER NOT NULL DEFAULT 0,
  is_locked INTEGER NOT NULL DEFAULT 0,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  deleted_at INTEGER,
  category_id INTEGER,
  image_path TEXT,
  audio_path TEXT,
  pdf_path TEXT,
  drawing_path TEXT,
  bg_style INTEGER NOT NULL DEFAULT 0,
  gradient TEXT,                              -- "dir:c1,c2[,c3]"
  rule_on_line INTEGER,
  rule_thickness REAL,
  rule_opacity REAL,
  rule_line_height REAL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
);

CREATE TABLE checklist_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  note_id INTEGER NOT NULL,
  text TEXT NOT NULL DEFAULT '',
  is_done INTEGER NOT NULL DEFAULT 0,
  position INTEGER NOT NULL DEFAULT 0,
  is_task INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
);

CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  color INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE note_tags (
  note_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (note_id, tag_id),
  FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
);

CREATE TABLE reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  note_id INTEGER,
  title TEXT,
  time INTEGER NOT NULL,
  repeat TEXT NOT NULL DEFAULT 'once',         -- once/daily/weekly/monthly/yearly/hijriYearly
  is_active INTEGER NOT NULL DEFAULT 1,
  notification_id INTEGER NOT NULL,
  importance TEXT NOT NULL DEFAULT 'high',      -- low/medium/high/critical
  pre_alerts TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  attachment TEXT NOT NULL DEFAULT '',
  interval_days INTEGER NOT NULL DEFAULT 0,     -- كورس دواء: الفاصل = أيام الراحة + 1
  dose_count INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
);

CREATE TABLE info_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  main_specialty TEXT NOT NULL DEFAULT '',
  sub_specialty TEXT NOT NULL DEFAULT '',
  topic TEXT NOT NULL DEFAULT '',
  brief TEXT NOT NULL DEFAULT '',
  detail TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);

CREATE TABLE med_doses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  dose TEXT,
  status TEXT NOT NULL DEFAULT 'taken',         -- taken/missed
  at INTEGER NOT NULL
);

CREATE TABLE reminder_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  reminder_id INTEGER,
  title TEXT NOT NULL,
  at INTEGER NOT NULL
);

-- الفهارس
CREATE INDEX idx_notes_uuid ON notes (uuid);
CREATE INDEX idx_notes_category ON notes (category_id);
CREATE INDEX idx_notes_flags ON notes (is_deleted, is_archived);
CREATE INDEX idx_checklist_note ON checklist_items (note_id);
CREATE INDEX idx_reminders_note ON reminders (note_id);
CREATE INDEX idx_info_specialty ON info_entries (main_specialty, sub_specialty);
