import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfolio/utils/heatmap/brutal.dart';
import 'package:portfolio/utils/heatmap/heat_data.dart';
import 'package:portfolio/utils/heatmap/heat_map_view.dart';
import 'package:portfolio/utils/heatmap/heat_models.dart';
import 'package:portfolio/utils/heatmap/heat_panels.dart';
import 'package:portfolio/utils/heatmap/ph_geo.dart';
import 'package:portfolio/utils/app_theme.dart';

class HeatmapPage extends ConsumerStatefulWidget {
  const HeatmapPage({super.key});

  @override
  ConsumerState<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends ConsumerState<HeatmapPage> {
  bool _isDark = false;
  bool _showOptions = false;
  // ── Theme (app_theme.dart) ─────────────────────────────
  static final ThemeData _lightTheme = AppTheme.portfolio(isDark: false);
  static final ThemeData _darkTheme = AppTheme.portfolio(isDark: true);

  ThemeData get _theme => _isDark ? _darkTheme : _lightTheme;
  AppPalette get _p => _theme.extension<AppPalette>()!;

  Border get _border => Border.all(color: _p.ink, width: 2);

  BoxShadow _hardShadow(double offset) =>
      BoxShadow(color: _p.shadow, offset: Offset(offset, offset), blurRadius: 0);

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

  void _refresh() => ref.invalidate(provinceWeatherProvider);

  String? _updatedLabel(Map<String, WeatherReading> readings) {
    for (final r in readings.values) {
      final label = r.timeLabel;
      if (label != null) return label;
    }
    return null;
  }

  TextStyle get _small => TextStyle(
        color: _p.ink,
        fontSize: 13,
        letterSpacing: 0.6,
        height: 1.35,
      );

  @override
  Widget build(BuildContext context) {
    final geoAsync = ref.watch(phGeoProvider);
    final weatherAsync = ref.watch(provinceWeatherProvider);
    final weather = weatherAsync.maybeWhen<ProvinceWeather?>(
      data: (w) => w,
      orElse: () => null,
    );

    final isDesktop = context.isDesktop;
    final dashboardWidth = AppResponsive.dashboardWidth(context);

    return Theme(
      data: _theme,
      child: Scaffold(
        backgroundColor: _p.background,
        body: Stack(
        children: [
          SizedBox(
            height: context.screenHeight,
            child: Center(
              child: SingleChildScrollView(
                child:Column(
                  children: [
                    const SizedBox(height: 42),
                    WireFrame( 
                      color: _p.shell,
                      width: dashboardWidth,
                      margin: EdgeInsets.fromLTRB(
                        0,
                        42,
                        0,
                        isDesktop ? AppSpacing.md : AppSpacing.sm,
                      ),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      border: Border.all(color: _p.ink, width: 2),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _hardShadow(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(weather, weatherAsync.isLoading),
                        const SizedBox(height: AppSpacing.md),
                        geoAsync.when(
                          loading: () => const _Centered(child: CircularProgressIndicator()),
                          error: (e, _) => _Centered(
                            child: Text('Could not load the map data.', style: _small),
                          ),
                          data: (geo) => _content(geo, weather?.readings ?? const {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 280),
                ]
              ),
            )
          )
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
                          label: 'Tournament',
                          route: '/tournament',
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

  Widget _header(ProvinceWeather? weather, bool loading) {
    final updated = _updatedLabel(weather?.readings ?? const {});
    final status = loading
        ? 'Loading live temperatures…'
        : updated != null
            ? 'Live data · updated $updated PHT'
            : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PH HEAT MAP',
                  style: TextStyle(
                    color: _p.ink,
                    fontSize: AppResponsive.titleSize(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  ),
                ),
                if (status.isNotEmpty) Text(status, style: _small),
              ],
            ),
            HeatModeToggle(onRefresh: _refresh),
          ],
        ),
        if (weather?.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          BrutalBox(
            color: AppColors.coral,
            shadow: 0,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    weather!.error!,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                BrutalButton(label: 'Retry', onTap: _refresh),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _content(PhGeo geo, Map<String, WeatherReading> readings) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final mapHeight = wide
            ? math.min(760.0, MediaQuery.of(context).size.height * 0.8)
            : 460.0;

        final map = BrutalBox(
          color: AppColors.dsBlue,
          padding: EdgeInsets.zero,
          shadow: wide ? 6 : 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: mapHeight,
              child: HeatMapView(geo: geo, readings: readings),
            ),
          ),
        );

        const side = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HeatLegend(),
            SizedBox(height: AppSpacing.md),
            HeatDetailPanel(),
          ],
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: map),
              const SizedBox(width: AppSpacing.md),
              const SizedBox(width: 340, child: side),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [map, const SizedBox(height: AppSpacing.md), side],
        );
      },
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 320, child: Center(child: child));
}