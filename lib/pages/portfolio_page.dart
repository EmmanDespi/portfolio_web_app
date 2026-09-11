import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../orderpage.dart';
import '../utils/resume_downloader.dart';
import '../tournament_system.dart';

// ── Breakpoints ─────────────────────────────────────────────
//   phone   < 600 px  →  2 columns
//   tablet  < 900 px  →  3 columns
//   desktop ≥ 900 px  →  5 columns

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> {
  bool _isDark = false;
  AppTheme get _theme => AppTheme(isDark: _isDark);
  bool _showOptions = false; // toggle for floating container


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

  // // ── Opens the resume PDF in a new browser tab ─────────────
  // Future<void> _launchResume() async {
  //   const resumeUrl = '../assets/files/Emmanuel_Despi_Resume.pdf';
  //   final uri = Uri.parse(resumeUrl);
  //   try {
  //     // On web, skip canLaunchUrl — it throws MissingPluginException
  //     // Just call launchUrl directly with webOnlyWindowName: '_blank'
  //     if (kIsWeb) {
  //       await launchUrl(uri, webOnlyWindowName: '_blank');
  //     } else {
  //       if (await canLaunchUrl(uri)) {
  //         await launchUrl(uri);
  //       } else {
  //         throw 'Could not launch $resumeUrl';
  //       }
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(
  //         context,
  //       ).showSnackBar(const SnackBar(content: Text('Could not open resume.')));
  //     }
  //   }
  // }
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
    'Python', // fixed typo from "Pythonn"
    'Java',
    'Dart',
    'Swift',
    'Kotlin',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.oatcream,
      body: Stack(
        children:[ 
          
          SingleChildScrollView(
            child: Column(
              children: [
              _buildDashboard(context)
              ]
            ),
          ),
          if (_showOptions)
          Positioned(
            bottom: MediaQuery.of(context).size.height < 1000 ? 100 : 80,
            right: 20,
            child: WireFrame(
              width: 220,
              color: _theme.background,
              padding: const EdgeInsets.all(12),
              boxShadow: BoxShadow(
                color: AppColors.black,
                offset: const Offset(-3, 3),
                blurRadius: 0,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(Icons.emoji_events, color: _theme.textPrimary,),
                      title: Text(
                        "Tournament",
                        style: TextStyle(
                          color: _theme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                        ),
                      ),
                      onTap: () => context.go('/tournament'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]
      ),

      floatingActionButton: FloatingActionButton(
      backgroundColor: _theme.background2,
      child: Icon(_showOptions ? Icons.close : Icons.menu, color: _theme.textSecondary),
      onPressed: () {
        setState(() {
          _showOptions = !_showOptions;
        });
      },
    ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;
    final isTablet = screenWidth >= 1400 && screenWidth < 2200;
    final isAlmostMobile = screenWidth >= 800 && screenWidth < 1400;

    final dashboardWidth = isMobile
        ? screenWidth * 0.99
        : isTablet
        ? screenWidth * 0.7
        : isAlmostMobile
        ? screenWidth * 0.9
        : screenWidth * 0.5;
    final aboutWidth = isMobile
        ? dashboardWidth * 0.87
        : isAlmostMobile || isTablet
        ? dashboardWidth * 0.45
        : dashboardWidth * 0.6;
    final expWidth = isMobile
        ? dashboardWidth * 0.87
        : isAlmostMobile || isTablet
        ? dashboardWidth * 0.45
        : dashboardWidth * 0.28;

    return NeomorphismPanel(
      height: MediaQuery.of(context).size.height,
      borderRadius: BorderRadius.circular(0),
      padding: EdgeInsets.all(0),
      margin: const EdgeInsets.all(0),
      color: _theme.background,
      child: Center(
        // ── Main scrollable content ──────────────────────────
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 42),
              WireFrame(
                // border: Border.all(color: Colors.red, width: 1.5),
                theme: _theme,
                color: _theme.background2,
                padding: EdgeInsets.all(12),
                margin: !(isAlmostMobile || isMobile)
                    ? EdgeInsets.fromLTRB(
                        0,
                        MediaQuery.of(context).size.height * 0.1,
                        0,
                        MediaQuery.of(context).size.height * 0.1,
                      )
                    : EdgeInsets.all(0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _theme.background2, width: 5),
                width: dashboardWidth,
                boxShadow: BoxShadow(
                  color: AppColors.black,
                  offset: isAlmostMobile || isMobile ? Offset.zero : Offset(-10, 10),
                  blurRadius: 2,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _sectionDivider('About'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: !isMobile
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            // WireFrame(
                            //   color: _theme.surface,
                            //   padding: const EdgeInsets.all(12),
                            //   width: aboutWidth,
                            //   theme: AppTheme(isDark: _isDark),
                            //   child: _buildAbout(),
                            // ),
                            !isMobile
                                ? SizedBox(height: 0)
                                : WireFrame(
                                    color: _theme.surface,
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(
                                      top: 24,
                                      bottom: 12,
                                    ),
                                    boxShadow: BoxShadow(
                                      color: AppColors.black,
                                      offset:Offset(-3, 3),
                                      blurRadius: 2,
                                    ),
                                    width: expWidth,
                                    theme: AppTheme(isDark: _isDark),
                                    child: _buildExperiencePanel(),
                                  ),
                            WireFrame(
                              color: _theme.surface,
                              padding: const EdgeInsets.all(12),
                              boxShadow: BoxShadow(
                                color: AppColors.black,
                                offset: isAlmostMobile || isMobile ? Offset(-3, 3) : Offset(-10, 10),
                                blurRadius: 2,
                              ),
                              width: aboutWidth,
                              theme: AppTheme(isDark: _isDark),
                              child: _buildTechStackData(),
                            ),
                            SizedBox(height: 12),
                          ],
                        ),
                        isMobile
                            ? SizedBox(width: 0)
                            : WireFrame(
                                color: _theme.surface,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.fromLTRB(
                                  22,
                                  4,
                                  12,
                                  12,
                                ),
                                width: expWidth,
                                theme: AppTheme(isDark: _isDark),
                                child: _buildExperiencePanel(),
                              ),
                      ],
                    ),
                  ],
                ),
              ),
              // SizedBox(height: 32),
              // Divider(thickness: 15, color: _theme.surface),
              // SizedBox(height: 32),
              // WireFrame(
              //   theme: _theme,
              //   color: _theme.background,
              //   padding: EdgeInsets.all(12),
              //   borderRadius: BorderRadius.circular(2),
              //   border: Border.all(color: _theme.surface, width: 5),
              //   width: screenWidth * 0.7,
              //   child: SizedBox(height: 1200),
              // ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = MediaQuery.of(context).size.width < 2200;
        final w = constraints.maxWidth;

        // ── Shared: avatar flip card ──────────────────────────
        final avatar = FlipCardPanel(
          front: WireFrame(
            padding: const EdgeInsets.all(4),
            width: isMobile ? w * 0.22 : w * 0.12,
            height: isMobile
                ? w * 0.22
                : MediaQuery.of(context).size.height * 0.11,
            color: _theme.surface,
            child: Image.asset('assets/profile.gif', fit: BoxFit.fill),
          ),
          back: WireFrame(
            padding: const EdgeInsets.all(4),
            width: isMobile ? w * 0.22 : w * 0.12,
            height: isMobile
                ? w * 0.22
                : MediaQuery.of(context).size.height * 0.11,
            color: _theme.surface,
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
        );

        // ── Shared: name + title + chips ─────────────────────
        final nameBlock = Column(
          crossAxisAlignment: isMobile
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            SizedBox(height: 12),
            Text(
              'Emmanuel Despi',
              textAlign: isMobile ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                color: _theme.textTertiary,
                fontSize: isMobile ? 20 : 22,
                letterSpacing: 2.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            Wrap(
              spacing: 8,
              alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
              children: [
                Text(
                  'BSCPE',
                  style: TextStyle(
                    color: _theme.textTertiary,
                    fontSize: isMobile ? 16 : 18,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '• Far Eastern University',
                  style: TextStyle(
                    color: _theme.textTertiary,
                    fontSize: isMobile ? 16 : 16,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Institute of Technology',
                  style: TextStyle(
                    color: _theme.textTertiary,
                    fontSize: isMobile ? 16 : 16,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Text(
              'Software Engineer • Full Stack Developer • Technical Consultant',
              textAlign: isMobile ? TextAlign.center : TextAlign.start,
              softWrap: true,
              style: TextStyle(
                color: _theme.textTertiary,
                fontSize: isMobile ? 14 : 16,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
              children: [
                ActionChip(
                  avatar: Icon(
                    Icons.picture_as_pdf,
                    color: AppColors.dsBlue,
                    size: 16,
                  ),
                  label: Text(
                    'Resume',
                    style: TextStyle(
                      color: _theme.textPrimary,
                      fontSize: 14,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  backgroundColor: _theme.surface,
                  onPressed: _downloadResume,
                ),
                NeoSwitch(
                  value: _isDark,
                  theme: _theme,
                  onChanged: _toggleTheme,
                )
              ],
            ),
          ],
        );

        // ── Shared: contact info ──────────────────────────────
        final contactBlock = Column(
          crossAxisAlignment: isMobile
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            SizedBox(height: 12),
            Text(
              'Las Pinas City',
              style: TextStyle(
                color: _theme.textTertiary,
                fontSize: isMobile ? 14 : 16,
                letterSpacing: 2,
              ),
            ),
            Text(
              'emmanuelrobisodespi@gmail.com',
              style: TextStyle(
                color: _theme.textTertiary,
                fontSize: isMobile ? 14 : 16,
                letterSpacing: 2,
              ),
            ),
            Text(
              '09056248875',
              style: TextStyle(
                color: _theme.textTertiary,
                fontSize: isMobile ? 14 : 16,
                letterSpacing: 2,
              ),
            ),
          ],
        );

        // ── Mobile: Column layout ─────────────────────────────
        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatar,
              const SizedBox(height: 12),
              nameBlock,
              const SizedBox(height: 12),
              contactBlock,
            ],
          );
        }

        // ── Desktop: Row layout ───────────────────────────────
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: w * 0.015),
            avatar,
            const SizedBox(width: 12),
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
              color: _theme.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: _theme.textSecondary)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════
  Widget _buildAbout() {
    final isMobile = MediaQuery.of(context).size.width < 1380;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text(
        //   'About Me',
        //   style: TextStyle(
        //     color: _theme.textPrimary,
        //     fontSize: 18,
        //     fontWeight: FontWeight.w800,
        //     letterSpacing: 2.5,
        //   ),
        // ),
        Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            Text(
              'A Software Engineer with broad experience across embedded systems, robotics, and web / mobile full-stack applications. Adept at delivering end-to-end solutions from hardware-level firmware to cloud-connected consumer apps. \n\nTrained in software development, Design Patterns, Indusstry staanddardd codiing practices, system security, Scrum, Agile, and microservices architecture. Holds a Career Service Professional certification.',
              style: TextStyle(
                color: _theme.textPrimary,
                fontFamily: 'SF Pro Text',
                fontWeight: FontWeight.w600,
                fontSize: isMobile ? 14 : 16,
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
  // ═══════════════════════════════════════════════════════════
  Widget _buildTechStackData() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tech Stack & Skills',
          style: TextStyle(
            color: _theme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
          ),
        ),
        SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Front End',
              style: TextStyle(
                color: _theme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
              ),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: frontEndTechs.map((lang) {
                return Chip(
                  label: Text(lang),
                  backgroundColor: _theme.surface,
                  labelStyle: TextStyle(color: _theme.textPrimary),
                  side: BorderSide(
                    color: _theme.textPrimary, // Your desired border color
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 12),
            Divider(),
            SizedBox(height: 12),
            Text(
              'Back End',
              style: TextStyle(
                color: _theme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
              ),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: backEndTechs.map((lang) {
                return Chip(
                  label: Text(lang),
                  backgroundColor: _theme.surface,
                  labelStyle: TextStyle(color: _theme.textPrimary),
                  side: BorderSide(
                    color: _theme.textPrimary, // Your desired border color
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 12),
            Divider(),
            SizedBox(height: 12),
            Text(
              'Cloud and Tools',
              style: TextStyle(
                color: _theme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
              ),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cloudTools.map((lang) {
                return Chip(
                  label: Text(lang),
                  backgroundColor: _theme.surface,
                  labelStyle: TextStyle(color: _theme.textPrimary),
                  side: BorderSide(
                    color: _theme.textPrimary, // Your desired border color
                  ),
                );
              }).toList(),
            ),
            Divider(),
            SizedBox(height: 12),
            Text(
              'Languages',
              style: TextStyle(
                color: _theme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
              ),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: languages.map((lang) {
                return Chip(
                  label: Text(lang),
                  backgroundColor: _theme.surface,
                  labelStyle: TextStyle(color: _theme.textPrimary),
                  side: BorderSide(
                    color: _theme.textPrimary, // Your desired border color
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _experienceItem({
    required String initials,
    required String title,
    required String company,
    bool invertAvatar = false,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final double fontSize = 13.0.clamp(12.0, 18.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NeoAvatar(
              initials: initials,
              theme: AppTheme(isDark: invertAvatar ? !_isDark : _isDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    softWrap: true,
                    style: TextStyle(
                      color: _theme.textPrimary,
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    company,
                    softWrap: true,
                    style: TextStyle(
                      color: _theme.textPrimary,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: _theme.border),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildExperiencePanel() {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Work Experience',
          style: TextStyle(
            color: _theme.textPrimary,
            fontSize: isMobile ? 14 : 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
          ),
        ),
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

// ── DELETED (replaced by _cell helper above) ────────────────
// ignore: unused_element
class _OldBody extends StatelessWidget {
  const _OldBody();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// keep legacy Row children below so git history is preserved
