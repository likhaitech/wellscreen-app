import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
    return const Scaffold(
      backgroundColor: Color(0xFF5B2BBF),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WellScreen',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
