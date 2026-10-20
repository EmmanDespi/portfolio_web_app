import 'dart:math';
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF171713);
  static const paper = Color.fromARGB(255, 243, 238, 222);
  static const white = Color(0xFFFFFEFA);
  static const lime = Color(0xFFD7F34A);
  static const coral = Color(0xFFEF6249);
  static const muted = Color(0xFF77766F);
  static const line = Color(0xFFBCB9AE);
  static const oatcream = Color(0xFFC2A178);

  static const dsBlue = Color.fromARGB(255, 56, 81, 90);
  static const oatmilk = Color.fromARGB(255, 212, 201, 181);
  static const onyx = Color.fromARGB(255, 56, 52, 59);
}

abstract final class AppSpacing {
  static const xs = 6.0;
  static const sm = 12.0;
  static const md = 20.0;
  static const lg = 32.0;
  static const xl = 48.0;
}



///
/// Responsive Helpers
///
abstract final class AppResponsive {
  /// Breakpoints
  static const double mobile = 600;
  static const double tablet = 1024;
  static const double desktop = 1440;

  static double width(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double height(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static bool isMobile(BuildContext context) =>
      width(context) < mobile;

  static bool isTablet(BuildContext context) =>
      width(context) >= mobile &&
      width(context) < tablet;

  static bool isDesktop(BuildContext context) =>
      width(context) >= tablet;

  static bool isLargeDesktop(BuildContext context) =>
      width(context) >= desktop;

  static double dashboardWidth(BuildContext context) {
    final w = width(context);
 
    if (isMobile(context)) return w * 0.99;
    if (isTablet(context)) return w * 0.95;
    if (isLargeDesktop(context)) return w * 0.5;
    return w * 0.7;
  }
  /// Page padding
  static EdgeInsets pagePadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(12);
    }

    if (isTablet(context)) {
      return const EdgeInsets.all(20);
    }

    return const EdgeInsets.all(24);
  }

  /// Dialog width helper
  static double dialogWidth(
    BuildContext context,
    double maxWidth,
  ) {
    return min(
      width(context) * 0.95,
      maxWidth,
    );
  }

  /// Adaptive roster grid count
  static int gridColumns(BuildContext context) {
    if (isMobile(context)) return 1;
    if (isTablet(context)) return 2;
    return 3;
  }

  static BoxShadow hardShadow(double offset) =>
      BoxShadow(color: AppColors.ink, offset: Offset(offset, offset), blurRadius: 0);

  /// Match card width
  static double bracketCardWidth(
    BuildContext context,
  ) {
    return isMobile(context)
        ? 160
        : 200;
  }

  /// Swiss round card width
  static double swissRoundWidth(
    BuildContext context,
  ) {
    return isMobile(context)
        ? 180
        : 214;
  }

  /// Responsive title size
  static double titleSize(
    BuildContext context,
  ) {
    if (isMobile(context)) return 26;
    if (isTablet(context)) return 30;
    return 34;
  }

  /// Dialog max height
  static double dialogHeight(
    BuildContext context,
    double factor,
  ) {
    return height(context) * factor;
  }

  /// Optional content max width
  static double contentWidth(
    BuildContext context,
  ) {
    final w = width(context);

    return min(
      w,
      1600,
    );
  }
}

///
/// BuildContext Extensions
///
extension ResponsiveContext on BuildContext {
  double get screenWidth =>
      MediaQuery.of(this).size.width;

  double get screenHeight =>
      MediaQuery.of(this).size.height;

  bool get isMobile =>
      AppResponsive.isMobile(this);

  bool get isTablet =>
      AppResponsive.isTablet(this);

  bool get isDesktop =>
      AppResponsive.isDesktop(this);

  bool get isLargeDesktop =>
      AppResponsive.isLargeDesktop(this);

  EdgeInsets get pagePadding =>
      AppResponsive.pagePadding(this);
}

///
/// Palette (light / dark)
///
/// Semantic colour roles used by the portfolio page. Stored on the theme as a
/// [ThemeExtension] so widgets can read them with `context.palette`.
///
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.shell,
    required this.card,
    required this.chip,
    required this.ink,
    required this.shadow,
  });

  final Color background; // page background
  final Color shell; // outer dashboard container
  final Color card; // inner cards / panels
  final Color chip; // chips
  final Color ink; // text, borders, dividers
  final Color shadow; // hard offset shadows

  static const light = AppPalette(
    background: AppColors.oatcream,
    shell: AppColors.paper,
    card: AppColors.oatmilk,
    chip: AppColors.white,
    ink: AppColors.ink,
    shadow: AppColors.ink,
  );

  static const dark = AppPalette(
    background: AppColors.ink,
    shell: AppColors.onyx,
    card: AppColors.dsBlue,
    chip: AppColors.onyx,
    ink: AppColors.paper,
    shadow: Colors.black,
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? shell,
    Color? card,
    Color? chip,
    Color? ink,
    Color? shadow,
  }) =>
      AppPalette(
        background: background ?? this.background,
        shell: shell ?? this.shell,
        card: card ?? this.card,
        chip: chip ?? this.chip,
        ink: ink ?? this.ink,
        shadow: shadow ?? this.shadow,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      shell: Color.lerp(shell, other.shell, t)!,
      card: Color.lerp(card, other.card, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

abstract final class AppTheme {
  static TextTheme _textTheme(Color ink) => TextTheme(
        headlineLarge: TextStyle(
          color: ink,
          fontSize: 42,
          height: 0.98,
          fontWeight: FontWeight.w900,
        ),
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 28,
          height: 1.0,
          fontWeight: FontWeight.w900,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: TextStyle(
          color: ink,
          fontSize: 16,
          height: 1.35,
        ),
        bodyMedium: TextStyle(
          color: ink,
          fontSize: 14,
          height: 1.35,
        ),
        labelLarge: TextStyle(
          color: ink,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: AppColors.paper,
        colorScheme: const ColorScheme.light(
          primary: AppColors.ink,
          secondary: AppColors.lime,
          surface: AppColors.oatmilk,
          error: AppColors.coral,
          onPrimary: AppColors.oatmilk,
          onSecondary: AppColors.ink,
          onSurface: AppColors.ink,
        ),
        textTheme: _textTheme(AppColors.ink),
        extensions: const [AppPalette.light],
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: AppColors.ink,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.paper,
          secondary: AppColors.lime,
          surface: AppColors.dsBlue,
          error: AppColors.coral,
          onPrimary: AppColors.ink,
          onSecondary: AppColors.ink,
          onSurface: AppColors.paper,
        ),
        textTheme: _textTheme(AppColors.paper),
        extensions: const [AppPalette.dark],
      );

  /// Portfolio page variant. Same base as [light] / [dark] but with the
  /// portfolio's own page background and neo-brutalist component styling.
  /// Scoped here so other pages (tournament, heatmap) are unaffected.
  static ThemeData portfolio({required bool isDark}) {
    final base = isDark ? dark : light;
    final p = isDark ? AppPalette.dark : AppPalette.light;

    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      iconTheme: IconThemeData(color: p.ink),
      dividerTheme: DividerThemeData(color: p.ink, thickness: 1.5, space: 1),
      listTileTheme: ListTileThemeData(iconColor: p.ink, textColor: p.ink),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.chip,
        labelStyle: base.textTheme.bodyMedium!.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: p.ink, width: 1.5),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.lime,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.ink, width: 2),
        ),
      ),
    );
  }
}

class NeoAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initials;
  final double size;
  final bool isDark;

  const NeoAvatar({
    super.key,
    this.imageUrl,
    required this.initials,
    this.size = 52,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppColors.onyx : AppColors.oatmilk,
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
                  color: AppColors.coral,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.35,
                ),
              ),
            ),
    );
  }
}