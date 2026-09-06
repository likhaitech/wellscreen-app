import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_settings_screen.dart';
import 'child_home_screen.dart';
import 'login_screen.dart';
import 'parent_dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Color purple = AppColors.primary;
  static const Color teal = AppColors.accent;
  static const Color darkText = AppColors.textPrimary;

  @override
  void initState() {
    super.initState();

    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await Future<void>.delayed(const Duration(seconds: 2));

    final user = FirebaseAuth.instance.currentUser;

    // No saved Firebase session -> normal login.
    if (user == null) {
      _openLogin();
      return;
    }

    try {
      // Check admin claims first.
      final tokenResult = await user.getIdTokenResult();
      final claims = tokenResult.claims ?? <String, dynamic>{};

      final isAdmin = claims['admin'] == true || claims['role'] == 'admin';

      if (!mounted) return;

      if (isAdmin) {
        _replaceWith(const AdminSettingsScreen());
        return;
      }

      // Restore Parent / Child role from Firestore.
      final userDocument = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (!userDocument.exists) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        _openLogin();
        return;
      }

      final data = userDocument.data();

      final role = data?['role']?.toString().trim().toLowerCase();

      if (role == 'child') {
        _replaceWith(const ChildHomeScreen());
        return;
      }

      if (role == 'parent') {
        _replaceWith(const ParentDashboardScreen());
        return;
      }

      // Invalid account role.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      _openLogin();
    } catch (e) {
      if (!mounted) return;

      // Keep the Firebase session instead of automatically
      // signing the user out because of a temporary error.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to restore session: $e')));

      _openLogin();
    }
  }

  void _openLogin() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _replaceWith(Widget screen) {
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SizedBox.expand(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(42),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(36),
                          child: Image.asset(
                            'assets/icons/wellscreen_icon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'WellScreen',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: purple,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Smart Parental Control\nfor Digital Wellness',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: darkText,
                          fontSize: 17,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 42),
                      const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(teal),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Text(
                  'Digital wellness support for families',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: purple, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
