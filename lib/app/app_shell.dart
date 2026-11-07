import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../screens/community_screen.dart';
import '../screens/help_desk_screen.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/services_screen.dart';
import 'app_language.dart';
import 'app_theme.dart';

class OrakzaiApp extends StatefulWidget {
  const OrakzaiApp({this.authController, super.key});

  final AuthController? authController;

  @override
  State<OrakzaiApp> createState() => _OrakzaiAppState();
}

class _OrakzaiAppState extends State<OrakzaiApp> {
  int _selectedIndex = 0;
  AppLanguage _language = AppLanguage.english;
  late final AuthController _authController;

  @override
  void initState() {
    super.initState();
    _authController = widget.authController ?? AuthController();
    _authController.restoreSession();
  }

  @override
  void dispose() {
    if (widget.authController == null) _authController.dispose();
    super.dispose();
  }

  void _openHelpDesk() {
    setState(() => _selectedIndex = 2);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orakzai',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) => Directionality(
        textDirection: _language.isRightToLeft
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            HomeScreen(language: _language, onOpenHelpDesk: _openHelpDesk),
            const CommunityScreen(),
            const HelpDeskScreen(),
            const ServicesScreen(),
            ProfileScreen(
              language: _language,
              authController: _authController,
              onLanguageChanged: (language) {
                setState(() => _language = language);
              },
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          backgroundColor: Colors.white,
          indicatorColor: AppColors.goldWash,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: AppCopy.text(_language, 'home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_outline_rounded),
              selectedIcon: const Icon(Icons.people_rounded),
              label: AppCopy.text(_language, 'community'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.support_agent_outlined),
              selectedIcon: const Icon(Icons.support_agent_rounded),
              label: AppCopy.text(_language, 'helpDesk'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.grid_view_outlined),
              selectedIcon: const Icon(Icons.grid_view_rounded),
              label: AppCopy.text(_language, 'services'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: AppCopy.text(_language, 'profile'),
            ),
          ],
        ),
      ),
    );
  }
}
