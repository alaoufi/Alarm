import 'package:flutter/material.dart';

/// قائمة ثابتة بأيقونات التصنيفات.
///
/// نخزّن في قاعدة البيانات *فهرس* الأيقونة (وليس codePoint) ليبقى كل استخدام
/// لـ IconData ثابتًا (const)، فيعمل بناء الـ release الافتراضي مع تقليم الأيقونات
/// (tree-shaking) دون الحاجة إلى أي رايات إضافية.
const List<IconData> kCategoryIcons = [
  Icons.person, // 0
  Icons.work, // 1
  Icons.star, // 2
  Icons.event, // 3
  Icons.lightbulb, // 4
  Icons.favorite, // 5
  Icons.school, // 6
  Icons.label, // 7
  Icons.home, // 8
  Icons.shopping_cart, // 9
  Icons.flight, // 10
  Icons.fitness_center, // 11
  Icons.inbox, // 12 (الوارد)
];

/// تُعيد أيقونة ثابتة بأمان من الفهرس المخزَّن.
IconData categoryIconByIndex(int index) {
  if (index < 0 || index >= kCategoryIcons.length) {
    return Icons.label;
  }
  return kCategoryIcons[index];
}
