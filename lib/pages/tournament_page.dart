import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../tournament_system.dart';

class TournamentPage extends ConsumerStatefulWidget {
  const TournamentPage({super.key});

  @override
  ConsumerState<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends ConsumerState<TournamentPage> {
  bool _isDark = false;
  AppTheme get _theme => AppTheme(isDark: _isDark);

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDark = prefs.getBool('isDark') ?? false;
    });
  }

  

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;
    final isTablet = screenWidth >= 1400 && screenWidth < 2200;
    final isAlmostMobile = screenWidth >= 800 && screenWidth < 1400;

    final dashboardWidth = isMobile
        ? screenWidth * 0.99
        : isTablet
        ? screenWidth * 0.7
        : isAlmostMobile
        ? screenWidth * 0.95
        : screenWidth * 0.5;

    return Scaffold(
      backgroundColor: _theme.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 42),
            WireFrame(
              color: _theme.background2,
              width: dashboardWidth,  
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              boxShadow: BoxShadow(
                color: AppColors.black,
                offset: const Offset(-0, 0),
                blurRadius: 2,
              ),
              borderRadius: BorderRadius.circular(12),
              child: TournamentPanel(theme: _theme),)
          ],
        ),
      ),
    );
  }
}