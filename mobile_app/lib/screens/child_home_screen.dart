import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softOrange = Color(0xFFFFF4E5);
  static const Color softBlue = Color(0xFFEFF6FF);
  static const Color softRed = Color(0xFFFFEFEF);

  final pairingCodeController = TextEditingController();

  bool isPairing = false;

  @override
  void dispose() {
    pairingCodeController.dispose();
    super.dispose();
  }

  Future<void> pairWithParent() async {
    final code = pairingCodeController.text.trim().replaceAll(' ', '');
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    if (code.length != 6) {
      showMessage('Please enter a valid 6-digit pairing code.');
      return;
    }

    setState(() => isPairing = true);

    try {
      final firestore = FirebaseFirestore.instance;

      final codeRef = firestore.collection('pairing_codes').doc(code);
      final userRef = firestore.collection('users').doc(user.uid);

      await firestore.runTransaction((transaction) async {
        final codeSnapshot = await transaction.get(codeRef);

        if (!codeSnapshot.exists) {
          throw Exception('Pairing code not found.');
        }

        final codeData = codeSnapshot.data() ?? <String, dynamic>{};

        final status = (codeData['status'] ?? '').toString();
        final parentId = (codeData['parentId'] ?? '').toString();
        final childProfileId = (codeData['childId'] ?? '').toString();
        final expiresAt = codeData['expiresAt'];

        if (status != 'active') {
          throw Exception('This pairing code is no longer active.');
        }

        if (parentId.isEmpty || childProfileId.isEmpty) {
          throw Exception('Invalid pairing code data.');
        }

        if (expiresAt is Timestamp) {
          final expiryDate = expiresAt.toDate();

          if (DateTime.now().isAfter(expiryDate)) {
            throw Exception('This pairing code has expired.');
          }
        }

        final childProfileRef = firestore
            .collection('child_profiles')
            .doc(childProfileId);

        transaction.set(userRef, {
          'uid': user.uid,
          'email': user.email,
          'fullName': user.displayName ?? 'Child User',
          'role': 'child',
          'pairingStatus': 'connected',
          'pairedParentId': parentId,
          'pairedChildProfileId': childProfileId,
          'pairingCode': code,
          'pairedAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(codeRef, {
          'status': 'connected',
          'childAccountId': user.uid,
          'childEmail': user.email,
          'connectedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(childProfileRef, {
          'childAccountId': user.uid,
          'childEmail': user.email,
          'pairingStatus': 'connected',
          'connectedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      pairingCodeController.clear();

      if (!mounted) return;

      showMessage('Child device connected to parent successfully.');
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      showMessage(message);
    } finally {
      if (mounted) {
        setState(() => isPairing = false);
      }
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String formatDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final year = date.year.toString();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$month/$day/$year $hour:$minute';
    }

    return 'Not available';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Child Dashboard',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: logout,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? <String, dynamic>{};

          final fullName =
              (data['fullName'] ?? user.displayName ?? 'Child User').toString();

          final email = (data['email'] ?? user.email ?? '').toString();

          final pairingStatus = (data['pairingStatus'] ?? 'not_paired')
              .toString();

          final isConnected =
              pairingStatus == 'connected' ||
              data['pairedParentId'] != null ||
              data['pairedChildProfileId'] != null;

          final pairedAt = formatDate(data['pairedAt']);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _headerCard(
                fullName: fullName,
                email: email,
                isConnected: isConnected,
              ),
              const SizedBox(height: 18),
              if (isConnected)
                _connectedDashboard(data: data, pairedAt: pairedAt)
              else
                _pairingDashboard(),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard({
    required String fullName,
    required String email,
    required bool isConnected,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isConnected
              ? const [teal, Color(0xFF2F9E78)]
              : const [purple, deepPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x225B2BBF),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isConnected ? Icons.verified_rounded : Icons.child_care_rounded,
              color: isConnected ? teal : purple,
              size: 36,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, $fullName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  email,
                  style: const TextStyle(
                    color: Color(0xFFE9DDFF),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isConnected
                      ? 'Connected to parent account for digital wellness support.'
                      : 'Enter the parent pairing code to connect this child device.',
                  style: const TextStyle(color: Colors.white, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pairingDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: const [
            Expanded(
              child: ChildStatCard(
                icon: Icons.link_off_rounded,
                title: 'Status',
                value: 'Not Paired',
                color: Colors.orange,
                backgroundColor: softOrange,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ChildStatCard(
                icon: Icons.privacy_tip_rounded,
                title: 'Privacy',
                value: 'Protected',
                color: purple,
                backgroundColor: softPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: softPurple,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: purple, size: 76),
              const SizedBox(height: 14),
              const Text(
                'Connect to Parent',
                style: TextStyle(
                  color: darkText,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the 6-digit pairing code generated from the parent account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: grayText, height: 1.4),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: pairingCodeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 7,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: purple, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isPairing ? null : pairWithParent,
                  style: FilledButton.styleFrom(
                    backgroundColor: purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(
                    isPairing ? 'Connecting...' : 'Pair Child Device',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.privacy_tip_rounded,
          iconColor: purple,
          backgroundColor: softBlue,
          title: 'Privacy Reminder',
          subtitle:
              'WellScreen monitors usage-related behavior only. It does not read messages, passwords, calls, photos, or sensitive files.',
        ),
      ],
    );
  }

  Widget _connectedDashboard({
    required Map<String, dynamic> data,
    required String pairedAt,
  }) {
    final pairingCode = (data['pairingCode'] ?? 'Not available').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: const [
            Expanded(
              child: ChildStatCard(
                icon: Icons.timer_rounded,
                title: 'Goal',
                value: '2h left',
                color: purple,
                backgroundColor: softPurple,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ChildStatCard(
                icon: Icons.self_improvement_rounded,
                title: 'Focus',
                value: 'Ready',
                color: Colors.orange,
                backgroundColor: softOrange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: softGreen,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            children: [
              const Icon(Icons.verified_rounded, color: teal, size: 78),
              const SizedBox(height: 14),
              const Text(
                'Connected to Parent',
                style: TextStyle(
                  color: darkText,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pairing code: $pairingCode\nPaired at: $pairedAt',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: grayText,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Device Status',
          style: TextStyle(
            color: darkText,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        _infoCard(
          icon: Icons.phone_android_rounded,
          iconColor: purple,
          backgroundColor: softPurple,
          title: 'Android Device',
          subtitle: 'This child account is linked to the parent dashboard.',
        ),
        _infoCard(
          icon: Icons.sync_rounded,
          iconColor: teal,
          backgroundColor: softGreen,
          title: 'Sync Status',
          subtitle:
              'Usage records will sync to the parent dashboard when internet is available.',
        ),
        _infoCard(
          icon: Icons.notifications_active_rounded,
          iconColor: Colors.orange,
          backgroundColor: softOrange,
          title: 'Reminder Status',
          subtitle:
              'Break reminders, cooldown timers, and focus mode notices will appear here.',
        ),
        _infoCard(
          icon: Icons.location_on_rounded,
          iconColor: Colors.redAccent,
          backgroundColor: softRed,
          title: 'Location Support',
          subtitle:
              'GPS sharing UI is ready. Backend location permission and saving will be connected next.',
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            showMessage('GPS function will be connected by backend.');
          },
          style: FilledButton.styleFrom(
            backgroundColor: purple,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.my_location_rounded),
          label: const Text(
            'Share Current Location',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.white,
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: grayText,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChildStatCard extends StatelessWidget {
  const ChildStatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.backgroundColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 31),
          const SizedBox(height: 9),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
