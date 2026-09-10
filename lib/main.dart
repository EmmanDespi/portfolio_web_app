import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portfolio/pages/tournament_page.dart';
import 'utils/globalData.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'orderpage.dart';
import 'pages/portfolio_page.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter _router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const PortfolioPage()
        // ),
        // GoRoute(
        //   path: '/credentials',
        //   builder: (context, state) => const CredentialsPage(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const ShoppingPage(),
        ),
        GoRoute(
          path: '/tournament',
          builder: (context, state) => const TournamentPage(),
        ),
      ],
    );

    return MaterialApp.router(
      routerConfig: _router,
      title: 'Portfolio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.title = 'Porfolio'});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _Namecontroller = TextEditingController();
  double panelWidth = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 31, 31, 31),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.01),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [Color(0xFFFF6A00), Color(0xFF8E2DE2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Text(
                'Welcome to your world',
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width * 0.05,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(
                      blurRadius: 5,
                      color: const Color.fromARGB(255, 245, 245, 245).withOpacity(0.8),
                      offset: Offset(4,4),
                    ),
                  ],
                ),
              ),
            ),
             ElevatedButton(
              onPressed: () {
                context.go('/credentials');
              },
              child: const Text('Go to Credentials'),
            ),
            ElevatedButton(
              onPressed: () {
                context.go('/dashboard');
              },
              child: const Text('Go to Dashboard'),
            ),
            ElevatedButton(
              onPressed: () {
                context.go('/review');
              },
              child: const Text('Go to Interview Reviewer'),
            ),
          ],
        ),
      ),
    );
  }
}
