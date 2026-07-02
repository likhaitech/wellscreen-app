import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key});

  static const Color purple = Color(0xFF5B2BBF);
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color pageBg = Color(0xFFF3F4F6);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softOrange = Color(0xFFFFF4E5);
  static const Color softRed = Color(0xFFFFEFEF);

  Future<void> logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: pageBg,
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Return to Login'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'Profile Settings',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: pageBg,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? <String, dynamic>{};

          final fullName =
              (data['fullName'] ?? user.displayName ?? 'WellScreen User')
                  .toString();

          final email = (data['email'] ?? user.email ?? '').toString();

          final role = (data['role'] ?? 'user').toString();

          final pairingStatus = (data['pairingStatus'] ?? 'not available')
              .toString();

          final roleLabel = role == 'parent'
              ? 'Parent / Guardian'
              : role == 'child'
              ? 'Child Account'
              : 'User Account';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _profileHeader(
                fullName: fullName,
                email: email,
                roleLabel: roleLabel,
                role: role,
                context: context,
              ),
              const SizedBox(height: 20),
              _settingsSection(
                title: 'Account',
                children: [
                  _settingsTile(
                    icon: Icons.person_rounded,
                    iconColor: purple,
                    backgroundColor: softPurple,
                    title: 'Edit Profile',
                    subtitle: 'Update name, photo, and basic account details.',
                    onTap: () {
                      showMessage(
                        context,
                        'Edit profile UI is ready. Backend saving will be connected later.',
                      );
                    },
                  ),
                  _settingsTile(
                    icon: Icons.photo_camera_rounded,
                    iconColor: teal,
                    backgroundColor: softGreen,
                    title: 'Add Profile Photo',
                    subtitle: 'Choose or update the account display photo.',
                    onTap: () {
                      showMessage(
                        context,
                        'Photo upload will be connected by backend later.',
                      );
                    },
                  ),
                  _settingsTile(
                    icon: Icons.email_rounded,
                    iconColor: Colors.orange,
                    backgroundColor: softOrange,
                    title: 'Email Address',
                    subtitle: email.isEmpty ? 'No email found' : email,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _settingsSection(
                title: role == 'child' ? 'Child Device' : 'Parent Controls',
                children: [
                  _settingsTile(
                    icon: role == 'child'
                        ? Icons.link_rounded
                        : Icons.family_restroom_rounded,
                    iconColor: purple,
                    backgroundColor: softPurple,
                    title: role == 'child'
                        ? 'Pairing Status'
                        : 'Child Device Management',
                    subtitle: role == 'child'
                        ? pairingStatus
                        : 'Manage paired child devices and profiles.',
                    onTap: () {},
                  ),
                  _settingsTile(
                    icon: Icons.privacy_tip_rounded,
                    iconColor: teal,
                    backgroundColor: softGreen,
                    title: 'Privacy Boundary',
                    subtitle:
                        'WellScreen does not read messages, passwords, calls, or sensitive files.',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _settingsSection(
                title: 'System',
                children: [
                  _settingsTile(
                    icon: Icons.notifications_rounded,
                    iconColor: Colors.orange,
                    backgroundColor: softOrange,
                    title: 'Notifications',
                    subtitle: 'Manage alert and reminder preferences.',
                    onTap: () {
                      showMessage(
                        context,
                        'Notification settings will be connected later.',
                      );
                    },
                  ),
                  _settingsTile(
                    icon: Icons.logout_rounded,
                    iconColor: Colors.redAccent,
                    backgroundColor: softRed,
                    title: 'Logout',
                    subtitle: 'Sign out from this WellScreen account.',
                    onTap: () => logout(context),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _profileHeader({
    required String fullName,
    required String email,
    required String roleLabel,
    required String role,
    required BuildContext context,
  }) {
    final isChild = role == 'child';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isChild
              ? const [teal, Color(0xFF2F9E78)]
              : const [purple, deepPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x225B2BBF),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.white,
                child: Icon(
                  isChild
                      ? Icons.child_care_rounded
                      : Icons.family_restroom_rounded,
                  color: isChild ? teal : purple,
                  size: 54,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 2,
                child: InkWell(
                  onTap: () {
                    showMessage(
                      context,
                      'Profile photo upload will be connected later.',
                    );
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: purple,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.add_a_photo_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE9DDFF),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              roleLabel,
              style: TextStyle(
                color: isChild ? teal : purple,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: darkText,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: backgroundColor,
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: grayText,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
