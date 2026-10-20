import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/widgets.dart';
import '../utils/app_theme.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';
import '../tournament_system.dart';

class TournamentPage extends ConsumerStatefulWidget {
  const TournamentPage({super.key});

  @override
  ConsumerState<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends ConsumerState<TournamentPage> {
  bool _isDark = false;

  // ── Theme (app_theme.dart) ─────────────────────────────
  static final ThemeData _lightTheme = app.AppTheme.portfolio(isDark: false);
  static final ThemeData _darkTheme = app.AppTheme.portfolio(isDark: true);

  ThemeData get _theme => _isDark ? _darkTheme : _lightTheme;
  app.AppPalette get _p => _theme.extension<app.AppPalette>()!;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isDark = prefs.getBool('isDark') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = app.AppResponsive.isDesktop(context);
    final dashboardWidth = app.AppResponsive.dashboardWidth(context);
    final shadowOffset = isDesktop ? 8.0 : 4.0;

    return Theme(
      data: _theme,
      child: Scaffold(
        backgroundColor: _p.background,
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 42),
              WireFrame(
                color: _p.shell,
                width: dashboardWidth,
                margin: EdgeInsets.all(
                  isDesktop ? app.AppSpacing.md : app.AppSpacing.sm,
                ),
                padding: const EdgeInsets.all(app.AppSpacing.sm),
                border: Border.all(color: _p.ink, width: 2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: BoxShadow(
                  color: _p.shadow,
                  offset: Offset(shadowOffset, shadowOffset),
                  blurRadius: 0,
                ),
                child: TournamentPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}