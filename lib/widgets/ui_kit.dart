import 'package:flutter/material.dart';

/// مكوّنات واجهة موحّدة لمظهر عصري ثلاثي الأبعاد عبر صفحات التطبيق:
/// شريط علوي متدرّج، بطاقات بارزة، أيقونات متدرّجة، وحالة فارغة أنيقة.

/// شريط علوي بتدرّج لوني خفيف.
AppBar gradientAppBar(BuildContext context, String title,
    {List<Widget>? actions, PreferredSizeWidget? bottom, Widget? leading}) {
  final scheme = Theme.of(context).colorScheme;
  return AppBar(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    actions: actions,
    bottom: bottom,
    leading: leading,
    flexibleSpace: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.primaryContainer.withOpacity(0.55),
            scheme.surface,
          ],
        ),
      ),
    ),
  );
}

/// بطاقة بارزة (ثلاثية الأبعاد) بحواف دائرية وظلّ ناعم.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin = const EdgeInsets.fromLTRB(14, 6, 14, 6),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = padding == null ? child : Padding(padding: padding!, child: child);
    return Card(
      margin: margin,
      elevation: 3,
      shadowColor: scheme.shadow.withOpacity(0.4),
      surfaceTintColor: scheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// أيقونة دائرية الحواف بتدرّج لوني — لمسة عصرية موحّدة.
class GradientIcon extends StatelessWidget {
  final IconData icon;
  final Color? color; // أساس اللون؛ null = لون السمة الأساسي.
  final double size;
  const GradientIcon(this.icon, {super.key, this.color, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = color ?? scheme.primaryContainer;
    final fg = color != null
        ? (ThemeData.estimateBrightnessForColor(base) == Brightness.dark
            ? Colors.white
            : Colors.black87)
        : scheme.onPrimaryContainer;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, base.withOpacity(0.55)],
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: (color ?? scheme.primary).withOpacity(0.22),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: fg, size: size * 0.52),
    );
  }
}

/// شارة أيقونة بارزة ثلاثية الأبعاد (تدرّج ثلاثي + توهّج + حدّ فاتح).
/// [radius] = null ⇒ دائرة، وإلا مستطيل بحواف دائرية بهذا القطر.
Widget gradientBadge(IconData icon, Color color,
    {double size = 48, double? radius, double? iconSize}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: radius == null ? null : BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(Colors.white.withOpacity(0.28), color),
          color,
          Color.alphaBlend(Colors.black.withOpacity(0.20), color),
        ],
      ),
      boxShadow: [
        BoxShadow(
            color: color.withOpacity(0.45),
            offset: const Offset(0, 6),
            blurRadius: 14,
            spreadRadius: -2),
      ],
      border: Border.all(color: Colors.white.withOpacity(0.30), width: 1.2),
    ),
    child: Icon(icon, color: Colors.white, size: iconSize ?? size * 0.5),
  );
}

/// حالة فارغة أنيقة (أيقونة دائرية + عنوان + وصف اختياري).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState(
      {super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 58, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor)),
            ],
          ],
        ),
      ),
    );
  }
}
