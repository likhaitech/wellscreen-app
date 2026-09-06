import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;

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
      showMessage(authErrorMessage(e.code));
    } catch (e) {
      showMessage('Login error: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String authErrorMessage(String code) {
    if (code == 'user-not-found') {
      return 'No account found with this email.';
    }

    if (code == 'wrong-password') {
      return 'Incorrect password.';
    }

    if (code == 'invalid-email') {
      return 'Invalid email address.';
    }

    if (code == 'invalid-credential') {
      return 'Invalid email or password.';
    }

    if (code == 'user-disabled') {
      return 'This account has been disabled.';
    }

    if (code == 'network-request-failed') {
      return 'Network error. Please check your internet connection.';
    }

    return 'Login failed. Please try again.';
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
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              children: [
                _logoHeader(),
                const SizedBox(height: 30),
                _loginCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoHeader() {
    return Column(
      children: [
        Container(
          width: 132,
          height: 132,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(38),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Image.asset(
              'assets/icons/wellscreen_icon.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'WellScreen',
          style: TextStyle(
            color: purple,
            fontSize: 38,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
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
      ],
    );
  }

  Widget _loginCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Login',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkText,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Access your WellScreen account',
            textAlign: TextAlign.center,
            style: TextStyle(color: grayText, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: const Icon(Icons.email_rounded, color: purple),
              filled: true,
              fillColor: pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: purple, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_rounded, color: purple),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => obscurePassword = !obscurePassword);
                },
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: grayText,
                ),
              ),
              filled: true,
              fillColor: pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: purple, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: selectedRole,
            decoration: InputDecoration(
              labelText: 'Role',
              prefixIcon: const Icon(
                Icons.manage_accounts_rounded,
                color: purple,
              ),
              filled: true,
              fillColor: pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: purple, width: 2),
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
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: isLoading ? null : loginUser,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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
                      'Login',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'No account yet?',
                style: TextStyle(color: grayText, fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },
                child: const Text(
                  'Register',
                  style: TextStyle(color: purple, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
