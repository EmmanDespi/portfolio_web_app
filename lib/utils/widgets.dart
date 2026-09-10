import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math';

// ─────────────────────────────────────────────────────────────
// APP COLORS
// Brand palette used across light and dark themes.
// ─────────────────────────────────────────────────────────────
class AppColors {
  /// Vivid orange – primary CTA accent (peach / primary).
  static const Color peach = Color(0xFFFE8254);

  /// Muted teal-navy – text, borders, dividers (dsBlue).
  static const Color dsBlue = Color.fromARGB(255, 56, 81, 90);

  /// Warm tan – main page/scaffold background (oatcream).
  static const Color oatcream = Color(0xFFC2A178);

  /// Light greige – cards, panels, input fills (oatmilk).
  static const Color oat = Color.fromARGB(255, 236, 232, 225);

   static const Color oatmilk = Color.fromARGB(255, 212, 201, 181);

  /// Dark brown – deep accent / cookie colour.
  static const Color cookie = Color(0xFF4B2E21);

  /// Near-black – dark theme background/surface (onyx).
  static const Color onyx = Color.fromARGB(255, 56, 52, 59);

  /// Dark theme card surface – slightly lighter than onyx.
  static const Color onyxCard = Color(0xFF44404A);

  /// Success green.
  static const Color success = Color(0xFF4CAF82);

  /// Error / danger red.
  static const Color danger = Color(0xFFE05252);

  /// Warning amber.
  static const Color warning = Color(0xFFF5A623);

  /// Info blue.
  static const Color info = Color(0xFF5B9BD5);

   /// blak.
  static const Color black = Color.fromARGB(255, 5, 5, 5);

   /// white.
  static const Color white = Color.fromARGB(255, 255, 255, 255);
}

// ─────────────────────────────────────────────────────────────
// THEME HELPER
// Convenience accessors that flip between light and dark modes.
// ─────────────────────────────────────────────────────────────
class AppTheme {
  final bool isDark;
  const AppTheme({required this.isDark});

  /// Scaffold / page background.
  Color get background => isDark ? AppColors.onyx : AppColors.oatmilk;

  Color get background2 => !isDark ? AppColors.onyx : AppColors.oatmilk;

  /// Card / panel surface.
  Color get surface => isDark ? AppColors.onyx : AppColors.oatmilk;
  Color get surface2 => !isDark ? AppColors.onyx : AppColors.oatmilk;

  /// Primary text colour.
  Color get textPrimary => isDark ? AppColors.oatmilk : AppColors.onyx;
  
  /// terttiary / muted text.
  Color get textTertiary => !isDark ? AppColors.oatmilk : AppColors.onyx;

  /// Secondary / muted text.
  Color get textSecondary =>
      isDark ? AppColors.onyx : AppColors.oatmilk;

  /// Accent / CTA – always peach.
  Color get accent => AppColors.peach;

  /// Divider / border colour.
  Color get border =>
      isDark ? AppColors.oatmilk.withValues(alpha: 0.15) : AppColors.dsBlue.withValues(alpha: 0.25);

  /// Shadow dark side.
  Color get shadowDark =>
      isDark ? Colors.white.withValues(alpha: 0.85): Colors.black.withValues(alpha: 0.5);

  /// Shadow light side (neo-morphic highlight).
  Color get shadowLight =>
      isDark ? Colors.black.withValues(alpha: 0.5): Colors.white.withValues(alpha: 0.85);
}

// ─────────────────────────────────────────────────────────────
// WIRE PANEL
// Flat container – no shadows.  Used for layout scaffolding.
// ─────────────────────────────────────────────────────────────
class WirePanel extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;
  final BoxBorder? border;
  final AppTheme? theme;

  const WirePanel({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
    this.border,
    required this.theme
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: width,
        height: height,
        padding: padding ?? const EdgeInsets.all(0),
        margin: margin ?? const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius ?? BorderRadius.circular(0),
          border: border,
          boxShadow: [
              BoxShadow(
                color: AppColors.black,
                offset: const Offset(-10,10),
                blurRadius: 0,
              ),
          ]
        ),
        
        child: child,
      ),
    );
  }
}

class FlipCardPanel extends StatefulWidget {
  final double? width;
  final double? height;
  final Widget front;
  final Widget back;

  const FlipCardPanel({
    super.key,
    this.width,
    this.height,
    required this.front,
    required this.back,
  });

  @override
  State<FlipCardPanel> createState() => _FlipCardPanelState();
}

class _FlipCardPanelState extends State<FlipCardPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isFlipped = false;

  void _onEnter(bool hover) {
    setState(() {
      _hovering = hover;
      if (_hovering) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _onTap() {
    setState(() {
      _isFlipped = !_isFlipped;
      if (_isFlipped) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isTouch = !kIsWeb ||
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    final child = SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final angle = _controller.value * pi;
          final isFront = angle <= pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isFront
                ? widget.front
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: widget.back,
                  ),
          );
        },
      ),
    );

    // On touch devices use GestureDetector tap; on web/desktop use MouseRegion hover
    if (isTouch) {
      return GestureDetector(
        onTap: _onTap,
        child: child,
      );
    }

    return MouseRegion(
      onEnter: (_) => _onEnter(true),
      onExit: (_) => _onEnter(false),
      child: child,
    );
  }
}
class WireFrame extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;
  final BoxBorder? border;
  final BoxShadow? boxShadow;
  final AppTheme? theme;

  const WireFrame({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
    this.border,
    this.boxShadow,
    this.theme
  });

  @override
  Widget build(BuildContext context) {
    // If a theme is provided, derive colors from it; otherwise fall back to
    // the explicit `color` prop or the default oatmilk constant.
    final bgColor = color ?? theme?.surface ?? AppColors.oatmilk;

    return Center(
      child: Container(
        width: width,
        height: height,
        padding: padding ?? const EdgeInsets.all(0),
        margin: margin ?? const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius ?? BorderRadius.circular(2),
          border: border,
          boxShadow: [
              boxShadow ??
              BoxShadow(
                color: AppColors.black,
                offset: const Offset(-10,10),
                blurRadius: 0,
              ),
              // BoxShadow(
              //   color: AppColors.oat,
              //   offset: const Offset(-5, 5),
              //   blurRadius: 1,
              // ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class WireFrameFlat extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;
  final BoxBorder? border;

  const WireFrameFlat({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: width,
        height: height,
        padding: padding ?? const EdgeInsets.all(0),
        margin: margin ?? const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color ?? AppColors.oatmilk,
          borderRadius: borderRadius ?? BorderRadius.circular(12),
          border: border,
           boxShadow: [
              BoxShadow(
                color: AppColors.onyx,
                offset: const Offset(2, 2),
                blurRadius: 2,
              ),
           ]
        ),
        child: child,
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
// NEOMORPHISM PANEL  (ELEVATION: BASE / RAISED)
// Core tactile card.  Outer drop-shadow + inner gradient
// simulate physical depth on both light and dark surfaces.
// ─────────────────────────────────────────────────────────────
class NeomorphismPanel extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;
  final BoxBorder? border;
  final EdgeInsetsGeometry? margin;
  final AppTheme? theme;

  const NeomorphismPanel({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.borderRadius,
    this.border,
    this.margin,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? AppColors.oatmilk;
    final radius = borderRadius ?? BorderRadius.circular(22);
    final shadowDark = theme?.shadowDark ?? Colors.black.withValues(alpha: 0.28);
    final shadowLight = theme?.shadowLight ?? Colors.white.withValues(alpha: 0.8);

    return Center(
      child: Container(
        margin: margin ?? const EdgeInsets.all(12),
        child: Stack(
          children: [
            // ── Outer neomorphic shadow ──────────────────────
            Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: radius,
                border: border,
                boxShadow: [
                  BoxShadow(
                    color: shadowDark,
                    offset: const Offset(4, 4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: shadowLight,
                    offset: const Offset(-4, -4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              padding: padding ?? const EdgeInsets.all(20.0),
              child: child,
            ),
            // ── Inner gradient overlay (depth simulation) ───
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.06),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.08),
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INSET PANEL  (ELEVATION: INSET / PRESSED)
// Recessed surface – inner shadow gives a "pressed in" look.
// Used for input fields, slider tracks, skeleton backgrounds.
// ─────────────────────────────────────────────────────────────
class InsetPanel extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;
  final AppTheme? theme;

  const InsetPanel({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.borderRadius,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? AppColors.oatmilk;
    final radius = borderRadius ?? BorderRadius.circular(12);
    final shadowDark = theme?.shadowDark ?? Colors.black.withValues(alpha: 0.22);
    final shadowLight = theme?.shadowLight ?? Colors.white.withValues(alpha: 0.8);

    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: radius,
        boxShadow: [
          // ── inner-shadow simulation (inset top-left dark) ─
          BoxShadow(
            color: shadowDark,
            offset: const Offset(2, 2),
            blurRadius: 4,
            spreadRadius: 0,
          ),
          // ── inner-shadow highlight (inset bottom-right) ───
          BoxShadow(
            color: shadowLight,
            offset: const Offset(-2, -2),
            blurRadius: 4,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PRIMARY BUTTON  (CONTROLS: BUTTON SET – PRIMARY)
// Raised, filled with accent peach.  Supports pressed state.
// ─────────────────────────────────────────────────────────────
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final AppTheme? theme;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.theme,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isDisabled || widget.onPressed == null;
    final baseColor = disabled
        ? (widget.theme?.surface ?? AppColors.oatmilk)
        : AppColors.peach;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
      onTapCancel: disabled ? null : () => setState(() => _pressed = false),
      onTap: disabled ? null : widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(50),
          boxShadow: _pressed || disabled
              ? [
                  // ── pressed / inset shadow ─────────────────
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                ]
              : [
                  // ── raised shadow ──────────────────────────
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    offset: const Offset(3, 4),
                    blurRadius: 6,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.6),
                    offset: const Offset(-2, -2),
                    blurRadius: 4,
                  ),
                ],
        ),
        child: widget.isLoading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              )
            : Text(
                widget.label,
                style: TextStyle(
                  color: disabled
                      ? (widget.theme?.textSecondary ?? AppColors.dsBlue)
                      : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.4,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TEXT INPUT FIELD  (CONTROLS: TEXT FIELD)
// Inset neomorphic input.  Shows helper text and error state.
// ─────────────────────────────────────────────────────────────
class NeoTextField extends StatelessWidget {
  final String placeholder;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final bool obscureText;
  final AppTheme? theme;

  const NeoTextField({
    super.key,
    required this.placeholder,
    this.helperText,
    this.errorText,
    this.controller,
    this.obscureText = false,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    final surfaceColor = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;
    final hintColor = theme?.textSecondary ?? AppColors.dsBlue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Inset field container ────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasError ? AppColors.danger : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(2, 2),
                blurRadius: 5,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.7),
                offset: const Offset(-2, -2),
                blurRadius: 5,
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: TextStyle(color: hintColor, fontSize: 14),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        // ── Helper / error text ──────────────────────────────
        if (helperText != null || hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              hasError ? errorText! : helperText!,
              style: TextStyle(
                color: hasError ? AppColors.danger : hintColor,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CHECKBOX  (CONTROLS: CHECKBOX)
// Neomorphic checkbox with checked / unchecked states.
// ─────────────────────────────────────────────────────────────
class NeoCheckbox extends StatefulWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final AppTheme? theme;

  const NeoCheckbox({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.theme,
  });

  @override
  State<NeoCheckbox> createState() => _NeoCheckboxState();
}

class _NeoCheckboxState extends State<NeoCheckbox> {
  @override
  Widget build(BuildContext context) {
    final surface = widget.theme?.surface ?? AppColors.oatmilk;
    final textColor = widget.theme?.textPrimary ?? AppColors.onyx;

    return GestureDetector(
      onTap: () => widget.onChanged?.call(!widget.value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Box ─────────────────────────────────────────────
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: widget.value ? AppColors.peach : surface,
              borderRadius: BorderRadius.circular(5),
              boxShadow: widget.value
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        offset: const Offset(2, 2),
                        blurRadius: 4,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        offset: const Offset(2, 2),
                        blurRadius: 4,
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.75),
                        offset: const Offset(-2, -2),
                        blurRadius: 4,
                      ),
                    ],
            ),
            child: widget.value
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: textColor, fontSize: 13)),
        ],
      ),
    );
  }

  String get label => widget.label;
}

// ─────────────────────────────────────────────────────────────
// RADIO BUTTON  (CONTROLS: RADIO)
// Single-select option with neomorphic ring.
// ─────────────────────────────────────────────────────────────
class NeoRadio extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final AppTheme? theme;

  const NeoRadio({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Outer ring ───────────────────────────────────────
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  offset: const Offset(2, 2),
                  blurRadius: 4,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.75),
                  offset: const Offset(-2, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: selected ? 12 : 0,
                height: selected ? 12 : 0,
                decoration: const BoxDecoration(
                  color: AppColors.peach,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: textColor, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOGGLE SWITCH  (CONTROLS: SWITCH)
// ON/OFF sliding toggle with neomorphic track.
// ─────────────────────────────────────────────────────────────
class NeoSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final AppTheme? theme;

  const NeoSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.theme,
  });

  @override
  State<NeoSwitch> createState() => _NeoSwitchState();
}

class _NeoSwitchState extends State<NeoSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.value ? 1.0 : 0.0,
    );
    _anim = _ctrl;
  }

  @override
  void didUpdateWidget(NeoSwitch old) {
    super.didUpdateWidget(old);
    widget.value ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final surface = widget.theme?.surface ?? AppColors.oatmilk;

    return GestureDetector(
      onTap: () => widget.onChanged?.call(!widget.value),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          return Container(
            width: 52,
            height: 28,
            decoration: BoxDecoration(
              color: Color.lerp(surface, AppColors.peach, _anim.value),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  offset: const Offset(2, 2),
                  blurRadius: 5,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.6),
                  offset: const Offset(-2, -2),
                  blurRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.all(3),
            child: Align(
              alignment:
                  Alignment.lerp(Alignment.centerLeft, Alignment.centerRight, _anim.value)!,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 3,
                      offset: const Offset(1, 1),
                    ),
                  ],
                ),
                child: Icon(
                  widget.value ? Icons.dark_mode : Icons.light_mode,
                  color: widget.value ? AppColors.peach : AppColors.dsBlue,
                  size: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SLIDER  (CONTROLS: SLIDER)
// Neomorphic horizontal range slider.
// ─────────────────────────────────────────────────────────────
class NeoSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final String? label;
  final AppTheme? theme;

  const NeoSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = theme?.textPrimary ?? AppColors.onyx;
    final surface = theme?.surface ?? AppColors.oatmilk;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.onyx,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label!,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.peach,
            inactiveTrackColor: surface,
            thumbColor: AppColors.peach,
            overlayColor: AppColors.peach.withValues(alpha: 0.2),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TABS  (NAVIGATION: TABS)
// Horizontal tab bar with active pill indicator.
// ─────────────────────────────────────────────────────────────
class NeoTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int>? onTabChanged;
  final AppTheme? theme;

  const NeoTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    this.onTabChanged,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(2, 2),
            blurRadius: 5,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.7),
            offset: const Offset(-2, -2),
            blurRadius: 5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(tabs.length, (i) {
          final active = i == selectedIndex;
          return GestureDetector(
            onTap: () => onTabChanged?.call(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.peach : Colors.transparent,
                borderRadius: BorderRadius.circular(50),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          offset: const Offset(2, 2),
                          blurRadius: 4,
                        ),
                      ]
                    : [],
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  color: active ? Colors.white : textColor,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BREADCRUMBS  (NAVIGATION: BREADCRUMBS)
// Path-style navigation trail with chevron separators.
// ─────────────────────────────────────────────────────────────
class NeoBreadcrumbs extends StatelessWidget {
  final List<String> crumbs;
  final AppTheme? theme;

  const NeoBreadcrumbs({super.key, required this.crumbs, this.theme});

  @override
  Widget build(BuildContext context) {
    final textColor = theme?.textPrimary ?? AppColors.onyx;
    final mutedColor = theme?.textSecondary ?? AppColors.dsBlue;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: List.generate(crumbs.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Icon(Icons.chevron_right, size: 14, color: mutedColor);
        }
        final idx = i ~/ 2;
        final isLast = idx == crumbs.length - 1;
        return Text(
          crumbs[idx],
          style: TextStyle(
            color: isLast ? AppColors.peach : mutedColor,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PAGINATION  (NAVIGATION: PAGINATION)
// Numbered page selector with prev/next controls.
// ─────────────────────────────────────────────────────────────
class NeoPagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int>? onPageChanged;
  final AppTheme? theme;

  const NeoPagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    this.onPageChanged,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;

    Widget pageBtn(String label, int? page, {bool active = false}) {
      return GestureDetector(
        onTap: page != null ? () => onPageChanged?.call(page) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active ? AppColors.peach : surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: active ? 0.25 : 0.15),
                offset: const Offset(2, 2),
                blurRadius: 4,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: active ? 0.3 : 0.7),
                offset: const Offset(-2, -2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : textColor,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pageBtn('‹', currentPage > 1 ? currentPage - 1 : null),
        ...List.generate(totalPages, (i) {
          return pageBtn('${i + 1}', i + 1, active: i + 1 == currentPage);
        }),
        pageBtn('›', currentPage < totalPages ? currentPage + 1 : null),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STEP PROGRESS  (NAVIGATION: N-STEP PROCESS)
// Linear step indicator showing current progress.
// ─────────────────────────────────────────────────────────────
class NeoStepProgress extends StatelessWidget {
  final List<String> steps;
  final int currentStep;
  final AppTheme? theme;

  const NeoStepProgress({
    super.key,
    required this.steps,
    required this.currentStep,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textSecondary ?? AppColors.dsBlue;

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final passed = (i ~/ 2) < currentStep - 1;
          return Expanded(
            child: Container(
              height: 3,
              color: passed ? AppColors.peach : surface,
            ),
          );
        }
        final idx = i ~/ 2;
        final done = idx < currentStep - 1;
        final active = idx == currentStep - 1;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: done || active ? AppColors.peach : surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.6),
                    offset: const Offset(-2, -2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '${idx + 1}',
                        style: TextStyle(
                          color: active ? Colors.white : textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(steps[idx],
                style: TextStyle(fontSize: 10, color: textColor)),
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DATA CARD  (DATA DISPLAY: CARDS)
// Product / content card with title, description, and action.
// ─────────────────────────────────────────────────────────────
class NeoDataCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AppTheme? theme;

  const NeoDataCard({
    super.key,
    required this.title,
    required this.description,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;
    final mutedColor = theme?.textSecondary ?? AppColors.dsBlue;

    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            offset: const Offset(3, 3),
            blurRadius: 6,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.7),
            offset: const Offset(-3, -3),
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Icon area ────────────────────────────────────────
          if (icon != null)
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.7),
                    offset: const Offset(-2, -2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Icon(icon, size: 20, color: mutedColor),
            ),
          Text(title,
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 4),
          Text(description,
              style: TextStyle(color: mutedColor, fontSize: 11)),
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.peach,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      offset: const Offset(2, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(actionLabel!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LIST ITEM  (DATA DISPLAY: LIST ITEMS)
// Row with avatar, title, subtitle, and trailing chevron.
// ─────────────────────────────────────────────────────────────
class NeoListItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? leading;
  final VoidCallback? onTap;
  final AppTheme? theme;

  const NeoListItem({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.onTap,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;
    final mutedColor = theme?.textSecondary ?? AppColors.dsBlue;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              offset: const Offset(2, 2),
              blurRadius: 5,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.7),
              offset: const Offset(-2, -2),
              blurRadius: 5,
            ),
          ],
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Text(subtitle,
                      style: TextStyle(color: mutedColor, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: mutedColor),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BADGE  (DATA DISPLAY: BADGES)
// Compact status pill – New / Sale / Popular / Unconfirmed.
// ─────────────────────────────────────────────────────────────
class NeoBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const NeoBadge({super.key, required this.label, this.color});

  factory NeoBadge.success(String label) =>
      NeoBadge(label: label, color: AppColors.success);
  factory NeoBadge.danger(String label) =>
      NeoBadge(label: label, color: AppColors.danger);
  factory NeoBadge.warning(String label) =>
      NeoBadge(label: label, color: AppColors.warning);
  factory NeoBadge.info(String label) =>
      NeoBadge(label: label, color: AppColors.info);

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.peach;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AVATAR  (DATA DISPLAY: AVATARS)
// Circular avatar with neomorphic ring.
// ─────────────────────────────────────────────────────────────
class NeoAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initials;
  final double size;
  final AppTheme? theme;

  const NeoAvatar({
    super.key,
    this.imageUrl,
    required this.initials,
    this.size = 52,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(2, 2),
            blurRadius: 5,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.7),
            offset: const Offset(-2, -2),
            blurRadius: 5,
          ),
        ],
      ),
      child: imageUrl != null
          ? ClipOval(
              child: Image.network(imageUrl!,
                  width: size, height: size, fit: BoxFit.cover))
          : Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: AppColors.peach,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.35,
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOOLTIP  (DATA DISPLAY: TOOLTIP)
// Dark popup label pointing to a target.
// ─────────────────────────────────────────────────────────────
class NeoTooltipWrapper extends StatelessWidget {
  final String message;
  final Widget child;

  const NeoTooltipWrapper(
      {super.key, required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      decoration: BoxDecoration(
        color: AppColors.onyx,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// COMPACT TABLE HEADER  (DATA DISPLAY: COMPACT TABLE HEADER)
// Sortable column headers for inline data tables.
// ─────────────────────────────────────────────────────────────
class NeoTableHeader extends StatelessWidget {
  final List<String> columns;
  final AppTheme? theme;

  const NeoTableHeader({super.key, required this.columns, this.theme});

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textSecondary ?? AppColors.dsBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.7),
            offset: const Offset(-2, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: columns.map((col) {
          return Expanded(
            child: Row(
              children: [
                Text(col,
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
                const SizedBox(width: 2),
                Icon(Icons.unfold_more, size: 12, color: textColor),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MODAL CONFIRMATION  (FEEDBACK: MODAL CONFIRMATION)
// Destructive action confirmation dialog.
// ─────────────────────────────────────────────────────────────
class NeoModal extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final AppTheme? theme;

  const NeoModal({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Delete',
    this.cancelLabel = 'Cancel',
    this.onConfirm,
    this.onCancel,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;
    final mutedColor = theme?.textSecondary ?? AppColors.dsBlue;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(4, 4),
            blurRadius: 10,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.7),
            offset: const Offset(-4, -4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Warning icon ─────────────────────────────────────
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.warning_amber, color: AppColors.warning, size: 28),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedColor, fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          offset: const Offset(2, 2),
                          blurRadius: 4,
                        ),
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.7),
                          offset: const Offset(-2, -2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                        child: Text(cancelLabel,
                            style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onConfirm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          offset: const Offset(2, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                        child: Text(confirmLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13))),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TOAST  (FEEDBACK: TOAST STACK)
// Dismissible notification row with icon and label.
// ─────────────────────────────────────────────────────────────
class NeoToast extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onDismiss;
  final AppTheme? theme;

  const NeoToast({
    super.key,
    required this.message,
    this.icon = Icons.check_circle_outline,
    this.iconColor,
    this.onDismiss,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(2, 2),
            blurRadius: 5,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.7),
            offset: const Offset(-2, -2),
            blurRadius: 5,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor ?? AppColors.success),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(message, style: TextStyle(color: textColor, fontSize: 13))),
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 14, color: textColor),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ALERT BANNER  (FEEDBACK: ALERT BANNER)
// Full-width informational / warning banner.
// ─────────────────────────────────────────────────────────────
class NeoAlertBanner extends StatelessWidget {
  final String message;
  final AlertBannerType type;
  final AppTheme? theme;

  const NeoAlertBanner({
    super.key,
    required this.message,
    this.type = AlertBannerType.info,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final IconData icon;

    switch (type) {
      case AlertBannerType.warning:
        bg = AppColors.warning;
        icon = Icons.warning_amber;
        break;
      case AlertBannerType.error:
        bg = AppColors.danger;
        icon = Icons.error_outline;
        break;
      case AlertBannerType.success:
        bg = AppColors.success;
        icon = Icons.check_circle_outline;
        break;
      case AlertBannerType.info:
        bg = AppColors.info;
        icon = Icons.info_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }
}

enum AlertBannerType { info, warning, error, success }

// ─────────────────────────────────────────────────────────────
// LINEAR PROGRESS  (FEEDBACK: LINEAR PROGRESS)
// Labelled horizontal progress bar.
// ─────────────────────────────────────────────────────────────
class NeoLinearProgress extends StatelessWidget {
  final double value; // 0.0 – 1.0
  final String? label;
  final AppTheme? theme;

  const NeoLinearProgress({
    super.key,
    required this.value,
    this.label,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final surface = theme?.surface ?? AppColors.oatmilk;
    final textColor = theme?.textPrimary ?? AppColors.onyx;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label!,
                    style: TextStyle(color: textColor, fontSize: 12)),
                Text('${(value * 100).round()}%',
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ],
            ),
          ),
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(1, 1),
                blurRadius: 4,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.7),
                offset: const Offset(-1, -1),
                blurRadius: 4,
              ),
            ],
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.peach,
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SPINNER  (FEEDBACK: SPINNER)
// Animated loading indicator in brand colour.
// ─────────────────────────────────────────────────────────────
class NeoSpinner extends StatelessWidget {
  final double size;

  const NeoSpinner({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        valueColor:
            const AlwaysStoppedAnimation<Color>(AppColors.peach),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SKELETON ROW  (FEEDBACK: SKELETON ROWS)
// Animated shimmer placeholder for loading content.
// ─────────────────────────────────────────────────────────────
class NeoSkeletonRow extends StatefulWidget {
  final double? width;
  final double height;
  final AppTheme? theme;

  const NeoSkeletonRow({
    super.key,
    this.width,
    this.height = 14,
    this.theme,
  });

  @override
  State<NeoSkeletonRow> createState() => _NeoSkeletonRowState();
}

class _NeoSkeletonRowState extends State<NeoSkeletonRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.theme?.surface ?? AppColors.oatmilk;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          color: Color.lerp(
            surface,
            surface.withValues(alpha: 0.6),
            _anim.value,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EMPTY STATE  (FEEDBACK: EMPTY STATE)
// Centered illustration + message + CTA for zero-data views.
// ─────────────────────────────────────────────────────────────
class NeoEmptyState extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final IconData icon;
  final VoidCallback? onAction;
  final AppTheme? theme;

  const NeoEmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.icon = Icons.search_off,
    this.onAction,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = theme?.textPrimary ?? AppColors.onyx;
    final mutedColor = theme?.textSecondary ?? AppColors.dsBlue;
    final surface = theme?.surface ?? AppColors.oatmilk;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Broken-link / search icon container ─────────────
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(3, 3),
                blurRadius: 6,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.7),
                offset: const Offset(-3, -3),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(icon, size: 30, color: mutedColor),
        ),
        const SizedBox(height: 12),
        Text(message,
            style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
        if (actionLabel != null) ...[
          const SizedBox(height: 12),
          PrimaryButton(
              label: actionLabel!, onPressed: onAction, theme: theme),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SECTION LABEL  (UTILITY)
// Small caps section header for the design dashboard.
// ─────────────────────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String text;
  final AppTheme? theme;

  const SectionLabel({super.key, required this.text, this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: theme?.textSecondary ?? AppColors.dsBlue,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}