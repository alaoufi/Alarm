/// سجلّ جرعة دواء: اسم الدواء، الجرعة، الحالة (أُخذت/فاتت)، ووقتها.
class MedDose {
  final int? id;
  final String name;
  final String? dose;
  final bool taken; // true = أُخذت، false = فاتت
  final DateTime at;

  const MedDose({
    this.id,
    required this.name,
    this.dose,
    required this.taken,
    required this.at,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'dose': dose,
        'status': taken ? 'taken' : 'missed',
        'at': at.millisecondsSinceEpoch,
      };

  factory MedDose.fromMap(Map<String, dynamic> map) => MedDose(
        id: map['id'] as int?,
        name: (map['name'] as String?) ?? '',
        dose: map['dose'] as String?,
        taken: ((map['status'] as String?) ?? 'taken') == 'taken',
        at: DateTime.fromMillisecondsSinceEpoch((map['at'] as int?) ?? 0),
      );
}
