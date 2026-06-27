/// تصنيف للملاحظات (شخصي، عمل، مهم، ...).
class Category {
  final int? id;
  final String name;
  final int color; // قيمة ARGB int
  final int iconCode; // codePoint لأيقونة من Material Icons
  final int position;

  const Category({
    this.id,
    required this.name,
    required this.color,
    required this.iconCode,
    this.position = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'color': color,
      'icon_code': iconCode,
      'position': position,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: (map['name'] as String?) ?? '',
      color: map['color'] as int? ?? 0xFF9E9E9E,
      iconCode: map['icon_code'] as int? ?? 7,
      position: map['position'] as int? ?? 0,
    );
  }

  Category copyWith({
    int? id,
    String? name,
    int? color,
    int? iconCode,
    int? position,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      iconCode: iconCode ?? this.iconCode,
      position: position ?? this.position,
    );
  }
}
