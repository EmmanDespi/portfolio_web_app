import 'package:flutter/material.dart';
import 'package:portfolio/utils/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio/utils/resume_downloader.dart';
import 'package:portfolio/utils/app_theme.dart' as app;

// ── Spacing tokens (app_theme.dart) ─────────────────────────
const _sm = app.AppSpacing.sm; // 12
const _md = app.AppSpacing.md; // 20
const _xl = app.AppSpacing.xl; // 48

const _headerRowMinWidth = 1000.0;

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  bool _isDark = false;
  bool _showOptions = false;
  AppTheme get _neoTheme => AppTheme(isDark: _isDark);

  // ── Theme (app_theme.dart) ─────────────────────────────
  static final ThemeData _lightTheme = app.AppTheme.portfolio(isDark: false);
  static final ThemeData _darkTheme = app.AppTheme.portfolio(isDark: true);

  ThemeData get _theme => _isDark ? _darkTheme : _lightTheme;
  app.AppPalette get _p => _theme.extension<app.AppPalette>()!;
  TextTheme get _text => _theme.textTheme;

  Color get _bg => _p.background;
  Color get _shell => _p.shell;
  Color get _card => _p.card;
  Color get _ink => _p.ink;
  Color get _shadow => _p.shadow;

  Border get _border => Border.all(color: _ink, width: 2);

  BoxShadow _hardShadow(double offset) =>
      BoxShadow(color: _shadow, offset: Offset(offset, offset), blurRadius: 0);

  TextStyle get _heading => _text.titleLarge!.copyWith(
    letterSpacing: 2.5,
    fontSize: app.AppResponsive.isMobile(context) ? 16 : null,
  );

  TextStyle get _subheading => _text.labelLarge!.copyWith(
    fontSize: 14,
    letterSpacing: 2.5,
  );

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

  Future<void> _toggleTheme(bool value) async {
    setState(() => _isDark = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', value);
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _downloadResume() async {
    final launched = await downloadResume();

    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open resume.')));
    }
  }

  final experiences = [
    {
      'initials': 'K',
      'title': 'Senior Software Engineer (Full Stack)',
      'company': 'Kivo Motion  •  May 2025 – April 2026',
      'invertAvatar': false,
    },
    {
      'initials': 'D',
      'title': 'Robotics Software Engineer',
      'company': 'Dyson  •  Dec 2023 – April 2025',
    },
    {
      'initials': 'T',
      'title': 'Embedded Software Engineer',
      'company': 'Thales  •  July 2022 – Nov 2023',
    },
    {
      'initials': 'T',
      'title': 'Full Stack Developer',
      'company': 'Tesda  •  Sept 2021 – June 2022',
    },
    {
      'initials': 'F',
      'title': 'CIE Operator',
      'company': 'FactSet  •  July 2020 – March 2021',
    },
    {
      'initials': 'N',
      'title': 'Intern Software Engineer',
      'company': 'Nokia  •  Dec 2019 – March 2020',
    },
    {
      'initials': 'F',
      'title': 'Freelance Software Developer',
      'company': 'Self-employed  •  Dec 2019 – Present',
      'invertAvatar': false,
    },
  ];

  final frontEndTechs = [
    'Flutter',
    'HTML',
    'CSS',
    'React.js',
    'React Native',
    'SwiftUI',
    'Vite',
    'Tailwind CSS',
    'Material UI',
  ];
  final backEndTechs = [
    'Node.js',
    'Firebase',
    'REST API',
    'Python',
    'MySQL',
    'MongoDB',
    'Git',
    'Docker',
    'Kubernetes',
    'Data Pipelines (ETL/ELT)',
    'Azure',
  ];

  final cloudTools = [
    'AWS Cloud Services',
    'Github',
    'VS Code',
    'Postman',
    'Figma',
    'Jira',
    'Kafka',
    'Kanban',
    'Google API',
    'Vercel',
  ];
  final languages = [
    'C',
    'C++',
    'C#',
    'Go Lang',
    'JavaScript',
    'Python',
    'Java',
    'Dart',
    'Swift',
    'Kotlin',
  ];

  // ═══════════════════════════════════════════════════════════
  // PAGE SHELL — same skeleton as TournamentPage:
  // Scaffold → SingleChildScrollView → Column → 42px gap → card
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme,
      child: Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 42),
                _buildDashboard(context),
                const SizedBox(height: 280),
              ],
            ),
          ),
          if (_showOptions)
            Positioned(
              bottom: 80,
              right: 20,
              child: WireFrame(
                width: 220,
                color: _card,
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
                        label: 'Tournament',
                        route: '/tournament',
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
        ],
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

  Widget _buildDashboard(BuildContext context) {
    final isMobile = app.AppResponsive.isMobile(context);
    final isDesktop = app.AppResponsive.isDesktop(context);
    final isLarge = app.AppResponsive.isLargeDesktop(context);
    final dashboardWidth = app.AppResponsive.dashboardWidth(context);

    final aboutWidth = dashboardWidth * (isMobile ? 0.87 : isLarge ? 0.6 : 0.45);
    final expWidth = dashboardWidth * (isMobile ? 0.87 : isLarge ? 0.28 : 0.45);

    final cardShadow = _hardShadow(isDesktop ? 6 : 4);

    return WireFrame(
      color: _shell,
      width: dashboardWidth,
      margin: EdgeInsets.all(!isDesktop ? _sm : _md),
      padding: const EdgeInsets.all(_sm),
      border: _border,
      borderRadius: BorderRadius.circular(12),
      boxShadow: _hardShadow(isDesktop ? 8 : 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _sectionDivider('About'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: isMobile
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  // Mobile: experience stacks above the tech stack.
                  if (isMobile)
                    WireFrame(
                      color: _card,
                      padding: const EdgeInsets.all(_sm),
                      margin: const EdgeInsets.only(top: _md, bottom: _sm),
                      border: _border,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: cardShadow,
                      width: expWidth,
                      child: _buildExperiencePanel(),
                    ),
                  WireFrame(
                    color: _card,
                    padding: const EdgeInsets.all(_sm),
                    border: _border,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: cardShadow,
                    width: aboutWidth,
                    child: _buildTechStackData(),
                  ),
                  const SizedBox(height: _sm),
                ],
              ),
              // Wider screens: experience sits beside the tech stack.
              if (!isMobile)
                WireFrame(
                  color: _card,
                  padding: const EdgeInsets.all(_sm),
                  margin: const EdgeInsets.fromLTRB(22, 4, 12, 12),
                  border: _border,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: cardShadow,
                  width: expWidth,
                  child: _buildExperiencePanel(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final stacked = w < _headerRowMinWidth;

        // ── Shared: avatar flip card ──────────────────────────
        Widget avatarFace(String asset, BoxFit fit) => WireFrame(
          padding: const EdgeInsets.all(4),
          width: stacked ? w * 0.22 : w * 0.12,
          height: stacked
              ? w * 0.22
              : MediaQuery.of(context).size.height * 0.11,
          color: _card,
          border: _border,
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(asset, fit: fit),
        );

        final avatar = FlipCardPanel(
          front: avatarFace('assets/profile.gif', BoxFit.fill),
          back: avatarFace('assets/logo.png', BoxFit.contain),
        );

        // ── Shared: name + title + chips ─────────────────────
        TextStyle headerStyle(double size, FontWeight weight) => TextStyle(
          color: _ink,
          fontSize: size,
          letterSpacing: 2,
          fontWeight: weight,
        );

        final nameBlock = Column(
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            const SizedBox(height: _sm),
            Text(
              'Emmanuel Despi',
              textAlign: stacked ? TextAlign.center : TextAlign.start,
              style: headerStyle(
                stacked ? 20 : 22,
                FontWeight.w900,
              ).copyWith(letterSpacing: 2.5),
            ),
            Wrap(
              spacing: 8,
              alignment: stacked ? WrapAlignment.center : WrapAlignment.start,
              children: [
                Text(
                  'BSCPE',
                  style: headerStyle(stacked ? 16 : 18, FontWeight.w500),
                ),
                Text(
                  '• Far Eastern University',
                  style: headerStyle(16, FontWeight.w500),
                ),
                Text(
                  'Institute of Technology',
                  style: headerStyle(16, FontWeight.w500),
                ),
              ],
            ),
            Text(
              'Software Engineer • Full Stack Developer • Technical Consultant',
              textAlign: stacked ? TextAlign.center : TextAlign.start,
              softWrap: true,
              style: headerStyle(stacked ? 14 : 16, FontWeight.w500),
            ),
            const SizedBox(height: _sm),
            Wrap(
              spacing: _sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: stacked ? WrapAlignment.center : WrapAlignment.start,
              children: [
                ActionChip(
                  avatar: Icon(
                    Icons.picture_as_pdf,
                    color: app.AppColors.coral,
                    size: 16,
                  ),
                  label: Text(
                    'Resume',
                    style: const TextStyle(
                      color: app.AppColors.ink,
                      fontSize: 14,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  backgroundColor: app.AppColors.line,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  side: BorderSide(color: _ink, width: 2),
                  onPressed: _downloadResume,
                ),
                NeoSwitch(
                  value: _isDark,
                  theme: _neoTheme,
                  onChanged: _toggleTheme,
                ),
              ],
            ),
          ],
        );

        // ── Shared: contact info ──────────────────────────────
        final contactStyle = headerStyle(stacked ? 14 : 16, FontWeight.w400);
        final contactBlock = Column(
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            const SizedBox(height: _sm),
            Text('Las Pinas City', style: contactStyle),
            Text('emmanuelrobisodespi@gmail.com', style: contactStyle),
            Text('09056248875', style: contactStyle),
          ],
        );

        // ── Stacked: Column layout ────────────────────────────
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatar,
              const SizedBox(height: _sm),
              nameBlock,
              const SizedBox(height: _sm),
              contactBlock,
            ],
          );
        }

        // ── Wide: Row layout ──────────────────────────────────
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: w * 0.015),
            avatar,
            const SizedBox(width: _sm),
            Expanded(child: nameBlock),
            SizedBox(width: w * 0.05),
            contactBlock,
            SizedBox(width: w * 0.015),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SECTION DIVIDER
  // ═══════════════════════════════════════════════════════════
  Widget _sectionDivider(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(width: _sm),
          Expanded(child: Container(height: 2, color: _ink)),
        ],
      ),
    );
  }

  Widget _rule() => const Divider(); // dividerTheme

  // ═══════════════════════════════════════════════════════════
  // ABOUT (currently not mounted in the dashboard)
  // ═══════════════════════════════════════════════════════════
  Widget _buildAbout() {
    final isCompact = !app.AppResponsive.isDesktop(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            Text(
              'A Software Engineer with broad experience across embedded systems, robotics, and web / mobile full-stack applications. Adept at delivering end-to-end solutions from hardware-level firmware to cloud-connected consumer apps. \n\nTrained in software development, Design Patterns, industry standard coding practices, system security, Scrum, Agile, and microservices architecture. Holds a Career Service Professional certification.',
              style: _text.bodyLarge!.copyWith(
                color: _ink,
                fontWeight: FontWeight.w600,
                fontSize: isCompact ? 14 : 16,
                height: 1.5,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TECH STACK
  // ═══════════════════════════════════════════════════════════
  Widget _techChip(String label) {
    // background, label style, shape and border come from chipTheme
    return Chip(label: Text(label));
  }

  Widget _techGroup(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _subheading),
        const SizedBox(height: _sm),
        Wrap(
          spacing: _sm,
          runSpacing: _sm,
          children: items.map(_techChip).toList(),
        ),
      ],
    );
  }

  Widget _groupDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _sm),
      child: _rule(),
    );
  }

  Widget _buildTechStackData() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tech Stack & Skills', style: _heading),
        const SizedBox(height: _sm),
        _techGroup('Front End', frontEndTechs),
        _groupDivider(),
        _techGroup('Back End', backEndTechs),
        _groupDivider(),
        _techGroup('Cloud and Tools', cloudTools),
        _groupDivider(),
        _techGroup('Languages', languages),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // EXPERIENCE
  // ═══════════════════════════════════════════════════════════
  Widget _experienceItem({
    required String initials,
    required String title,
    required String company,
    bool invertAvatar = false,
  }) {
    final base = _text.bodyMedium!.copyWith(
      color: _ink,
      fontSize: 13,
      letterSpacing: 1.5,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            app.NeoAvatar(
              initials: initials,
              isDark: _isDark,
            ),
            const SizedBox(width: _sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    softWrap: true,
                    style: base.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    company,
                    softWrap: true,
                    style: base.copyWith(fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: _sm),
        _rule(),
        const SizedBox(height: _sm),
      ],
    );
  }

  Widget _buildExperiencePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Work Experience', style: _heading),
        const SizedBox(height: 22),
        Column(
          children: experiences.map((exp) {
            return _experienceItem(
              initials: exp['initials'] as String,
              title: exp['title'] as String,
              company: exp['company'] as String,
              invertAvatar: exp['invertAvatar'] as bool? ?? false,
            );
          }).toList(),
        ),
      ],
    );
  }
}