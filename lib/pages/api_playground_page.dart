import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:portfolio/utils/widgets.dart';
import 'package:portfolio/utils/widgets/globe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfolio/utils/app_theme.dart' as app;
// import 'dart:convert';
// import 'package:http/http.dart' as http;
// (re-enable these two when you start making API calls)

class ApiPlaygroundPage extends StatefulWidget {
  const ApiPlaygroundPage({super.key});

  @override
  State<ApiPlaygroundPage> createState() => _ApiPlaygroundPageState();
}

class _ApiPlaygroundPageState extends State<ApiPlaygroundPage> {
  bool _isDark = false;

  static final ThemeData _lightTheme = app.AppTheme.portfolio(isDark: false);
  static final ThemeData _darkTheme = app.AppTheme.portfolio(isDark: true);

  ThemeData get _theme => _isDark ? _darkTheme : _lightTheme;
  app.AppPalette get _p => _theme.extension<app.AppPalette>()!;
  TextTheme get _text => _theme.textTheme;

  Color get _bg => _p.background;
  Color get _card => _p.card;
  Color get _ink => _p.ink;
  Color get _shadow => _p.shadow;

  Border get _border => Border.all(color: _ink, width: 2);

  BoxShadow _hardShadow(double offset) =>
      BoxShadow(color: _shadow, offset: Offset(offset, offset), blurRadius: 0);

  TextStyle get _heading => _text.titleLarge!.copyWith(
    letterSpacing: 2.5,
    fontSize: app.AppResponsive.isMobile(context) ? 16 : 24,
    fontWeight: FontWeight.bold,
  );

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isDark = prefs.getBool('isDark') ?? false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.screenWidth;
    const int itemCount = 4;
    const double spacing = 14;

    return Theme(
      data: _theme,
      child: Scaffold(
        backgroundColor: _bg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Playground', style: _heading),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final perRow = w < 700 ? 1 : w < 1600 ? 2 : 4;
                  return GridView.builder(
                    shrinkWrap: true,
                    clipBehavior: Clip.none,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: perRow,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      mainAxisExtent: context.screenHeight * 0.30,
                    ),
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      return WireFrame(
                        color: _card,
                        padding: const EdgeInsets.all(12),
                        border: _border,
                        boxShadow: _hardShadow(4),
                        borderRadius: BorderRadius.circular(12),
                        child: const PlanetGlobe(
                          initialPlanet: Planet.earth,
                          autoSpin: true,
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}