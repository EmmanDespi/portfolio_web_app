import 'package:flutter/material.dart';
import 'package:portfolio/utils/app_theme.dart';

/// Flat box with a thick ink border and a hard offset shadow.
class BrutalBox extends StatelessWidget {
  const BrutalBox({
    super.key,
    required this.child,
    this.color = AppColors.white,
    this.padding = const EdgeInsets.all(AppSpacing.sm),
    this.shadow = 4,
    this.radius = 8,
    this.borderWidth = 2,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double shadow;
  final double radius;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.ink, width: borderWidth),
        boxShadow: shadow == 0
            ? null
            : [
                BoxShadow(
                  color: AppColors.ink,
                  offset: Offset(shadow, shadow),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// Tappable [BrutalBox] with an icon and/or label.
class BrutalButton extends StatelessWidget {
  const BrutalButton({
    super.key,
    required this.onTap,
    this.icon,
    this.label,
    this.selected = false,
    this.color = AppColors.white,
    this.tooltip,
  });

  final VoidCallback onTap;
  final IconData? icon;
  final String? label;
  final bool selected;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: BrutalBox(
          color: selected ? AppColors.lime : color,
          shadow: selected ? 0 : 3,
          radius: 6,
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 8 : 12,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, size: 18, color: AppColors.ink),
              if (icon != null && label != null) const SizedBox(width: 6),
              if (label != null)
                Text(
                  label!,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
