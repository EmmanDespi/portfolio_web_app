import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  bool _showOptions = false;
  // ── Theme (app_theme.dart) ─────────────────────────────
  static final ThemeData _lightTheme = app.AppTheme.portfolio(isDark: false);
  static final ThemeData _darkTheme = app.AppTheme.portfolio(isDark: true);

  ThemeData get _theme => _isDark ? _darkTheme : _lightTheme;
  app.AppPalette get _p => _theme.extension<app.AppPalette>()!;

  Border get _border => Border.all(color: _p.ink, width: 2);

  BoxShadow _hardShadow(double offset) =>
      BoxShadow(color: _p.shadow, offset: Offset(offset, offset), blurRadius: 0);

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

  Widget _menuItem({
    required IconData icon,
    required String label,
    required String route,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.5,
        ),
      ),
      onTap: () => context.go(route),
    );
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
        body: Stack(
        children: [
          SizedBox(
            height: context.screenHeight,
            child: SingleChildScrollView(
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
                    boxShadow: _hardShadow(4),
                    child: TournamentPanel(),
                  ),
                  const SizedBox(height: 280),
                ],
              ),
            ),
          ),
          if (_showOptions)
              Positioned(
                bottom: 80,
                right: 20,
                child: WireFrame(
                  width: 220,
                  color: _p.card,
                  padding: const EdgeInsets.all(12),
                  border: _border,
                  boxShadow: _hardShadow(4),
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _menuItem(
                          icon: Icons.emoji_events,
                          label: 'Home',
                          route: '/',
                        ),
                        _menuItem(
                          icon: Icons.fire_extinguisher,
                          label: 'HeatMaps',
                          route: '/heatmap',
                        ),
                        _menuItem(
                          icon: Icons.api_outlined,
                          label: 'Playground',
                          route: '/apiplayground',
                        ),
                        _menuItem(
                          icon: Icons.map_outlined,
                          label: 'Itinerary builder',
                          route: '/itinerary',
                        ),
                        // _menuItem(
                        //   icon: Icons.map_outlined,
                        //   label: 'Grocery list builder',
                        //   route: '/grocery',
                        // ),
                      ],
                    ),
                  ),
                ),
              ),
            ]
          ),
          floatingActionButton: FloatingActionButton(
          // colours, border and elevation come from AppTheme.portfolio
          child: Icon(_showOptions ? Icons.close : Icons.menu),
          onPressed: () {
            setState(() {
              _showOptions = !_showOptions;
            });
          },
        ),
      ),
    );
  }
}