import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// منتقي وقت بعجلة دوّارة (اختيار بالسحب لا كتابة) — أنيق ويعرض ص/م بوضوح.
Future<TimeOfDay?> pickTimeWheel(BuildContext context, TimeOfDay initial) {
  DateTime temp = DateTime(2020, 1, 1, initial.hour, initial.minute);
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.access_time, color: scheme.primary),
                const SizedBox(width: 10),
                Text('اختر الوقت',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('تم'),
                  onPressed: () =>
                      Navigator.pop(ctx, TimeOfDay.fromDateTime(temp)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              initialDateTime: temp,
              use24hFormat: false,
              onDateTimeChanged: (d) => temp = d,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
