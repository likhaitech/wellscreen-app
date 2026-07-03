import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'child_home_screen.dart';
import 'login_screen.dart';
import 'parent_dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);

  @override
  void initState() {
    super.initState();
    startSplash();
  }

  Future<void> startSplash() async {
    await Future.delayed(const Duration(milliseconds: 1800));

    if (!mounted) return;

    if (Firebase.apps.isEmpty) {
      goToLogin();
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        goToLogin();
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      final data = userDoc.data() ?? <String, dynamic>{};
      final role = (data['role'] ?? '').toString().toLowerCase();

      if (role == 'parent') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
        );
      } else if (role == 'child') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
        );
      } else {
        goToLogin();
      }
    } catch (_) {
      if (!mounted) return;
      goToLogin();
    }
  }

  void goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [purple, deepPurple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 138,
                height: 138,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(38),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/icons/wellscreen_icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.health_and_safety_rounded,
                        color: purple,
                        size: 80,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'WellScreen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 42),
                child: Text(
                  'A mobile system for monitoring and regulating unhealthy smartphone use.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE9DDFF),
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 34),
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(teal),
                ),
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  'Digital wellness support for families',
                  style: TextStyle(
                    color: Color(0xFFE9DDFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
