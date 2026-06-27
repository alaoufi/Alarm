import 'package:flutter/material.dart';

/// تصنيف صوتيّ (مفتاح + أيقونة + لون).
class SoundCategory {
  final String key; // مفتاح الترجمة (cat_sea …)
  final IconData icon;
  final Color color;
  const SoundCategory(this.key, this.icon, this.color);
}

/// نغمة في مكتبة الأصوات.
class SoundTone {
  final String id; // اسم ملف raw/asset
  final String name; // اسم العرض (إنجليزي، اسم علم)
  final String categoryKey;
  final int calm; // مستوى الهدوء 1..5
  const SoundTone(this.id, this.name, this.categoryKey, this.calm);
}

const soundCategories = <SoundCategory>[
  SoundCategory('cat_sea', Icons.waves, Color(0xFF0288D1)),
  SoundCategory('cat_forest', Icons.forest, Color(0xFF2E7D32)),
  SoundCategory('cat_rain', Icons.water_drop, Color(0xFF5C6BC0)),
  SoundCategory('cat_wind', Icons.air, Color(0xFF00897B)),
  SoundCategory('cat_calm', Icons.auto_awesome, Color(0xFF8E24AA)),
  SoundCategory('cat_alarms', Icons.alarm, Color(0xFFE53935)),
];

/// مكتبة النغمات الأصلية (خالية من حقوق النشر) المضمّنة في التطبيق.
const soundCatalog = <SoundTone>[
  // 🌊 بحر
  SoundTone('ocean', 'Calm Tide', 'cat_sea', 5),
  SoundTone('gentle_waves', 'Gentle Waves', 'cat_sea', 5),
  SoundTone('sea_shore', 'Sound Of The Sea', 'cat_sea', 4),
  SoundTone('blue_harbour', 'Blue Harbour', 'cat_sea', 4),
  SoundTone('water', 'Aegean Sea', 'cat_sea', 4),
  // 🌲 غابة
  SoundTone('forest', 'Forest Morning', 'cat_forest', 5),
  SoundTone('rainforest', 'Rain Forest', 'cat_forest', 4),
  SoundTone('creek', 'Mountain Creek', 'cat_forest', 4),
  SoundTone('birds', 'Birds Singing', 'cat_forest', 3),
  // 🌧 مطر
  SoundTone('rain', 'Light Rain', 'cat_rain', 5),
  SoundTone('rain_window', 'Rain Window', 'cat_rain', 5),
  SoundTone('soft_storm', 'Soft Storm', 'cat_rain', 3),
  // 🌬 رياح
  SoundTone('desert_wind', 'Desert Wind', 'cat_wind', 4),
  SoundTone('evening_breeze', 'Evening Breeze', 'cat_wind', 5),
  // ✨ هادئة
  SoundTone('aurora', 'Aurora', 'cat_calm', 5),
  SoundTone('morning_light', 'Morning Light', 'cat_calm', 4),
  SoundTone('soft_bell', 'Soft Bell', 'cat_calm', 4),
  SoundTone('chime', 'Sakura Drop', 'cat_calm', 4),
  SoundTone('bell', 'Soft Chime', 'cat_calm', 3),
  // ⏰ منبّهات قوية
  SoundTone('alarm', 'Classic Alarm', 'cat_alarms', 1),
  SoundTone('digital_alarm', 'Digital Alarm', 'cat_alarms', 1),
  SoundTone('urgent', 'Urgent Reminder', 'cat_alarms', 1),
  SoundTone('wake_bell', 'Wake Up Bell', 'cat_alarms', 2),
];
