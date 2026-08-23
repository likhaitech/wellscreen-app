import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_settings_screen.dart';
import 'child_home_screen.dart';
import 'parent_dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color grayText = Color(0xFF4B5563);

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  String selectedRole = 'parent';

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loginUser() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showMessage('Please enter your email and password.');
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        showMessage('Login failed. Please try again.');
        return;
      }

      // Refresh the Firebase token so the latest admin claims are available.
      final tokenResult = await user.getIdTokenResult(true);
      final claims = tokenResult.claims ?? <String, dynamic>{};

      final isAdmin = claims['admin'] == true || claims['role'] == 'admin';

      if (!mounted) return;

      // Admin accounts use Firebase custom claims and go directly
      // to the Admin System Settings screen.
      if (isAdmin) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AdminSettingsScreen()),
          (route) => false,
        );

        return;
      }

      // Read the account role saved during registration.
      final userDocument = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDocument.exists) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        showMessage(
          'Account profile was not found. Please register the account first.',
        );
        return;
      }

      final data = userDocument.data();
      final storedRole = data?['role']?.toString().trim().toLowerCase();

      if (storedRole != 'parent' && storedRole != 'child') {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        showMessage('This account does not have a valid role.');
        return;
      }

      // The role selected on the Login page must match the account role.
      if (storedRole != selectedRole) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        final expectedRole = storedRole == 'parent'
            ? 'Parent / Guardian'
            : 'Child';

        showMessage(
          'This account is registered as $expectedRole. '
          'Please select the correct role.',
        );
        return;
      }

      // Only update login information.
      // IMPORTANT: Do not overwrite the saved account role here.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      if (storedRole == 'child') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? 'Invalid email or password.');
    } catch (e) {
      showMessage('Login error: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 34),

            Center(
              child: Image.asset(
                'assets/icons/wellscreen_icon.png',
                width: 110,
                height: 110,
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'WellScreen',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: purple,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Digital wellness monitoring for parents and children',
              textAlign: TextAlign.center,
              style: TextStyle(color: grayText, fontSize: 15, height: 1.4),
            ),

            const SizedBox(height: 36),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Email Address',
                prefixIcon: const Icon(Icons.email_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: passwordController,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: () {
                    setState(() {
                      obscurePassword = !obscurePassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              decoration: InputDecoration(
                labelText: 'Role',
                prefixIcon: const Icon(Icons.manage_accounts_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'parent',
                  child: Text('Parent / Guardian'),
                ),
                DropdownMenuItem(value: 'child', child: Text('Child')),
              ],
              onChanged: isLoading
                  ? null
                  : (value) {
                      if (value == null) return;

                      setState(() {
                        selectedRole = value;
                      });
                    },
            ),

            const SizedBox(height: 24),

            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: isLoading ? null : loginUser,
                style: FilledButton.styleFrom(
                  backgroundColor: purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Log In',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 18),

            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                );
              },
              child: const Text(
                'Create Account',
                style: TextStyle(color: purple, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
