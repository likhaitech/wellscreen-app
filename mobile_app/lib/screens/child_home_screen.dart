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
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);

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

        final codeData = codeSnapshot.data() as Map<String, dynamic>;

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
          'Child Device',
          style: TextStyle(fontWeight: FontWeight.w800),
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
          final data = snapshot.data?.data() ?? {};

          final fullName =
              (data['fullName'] ?? user.displayName ?? 'Child User').toString();

          final email = (data['email'] ?? user.email ?? '').toString();

          final pairingStatus = (data['pairingStatus'] ?? 'not_paired')
              .toString();

          final isConnected =
              pairingStatus == 'connected' ||
              data['pairedParentId'] != null ||
              data['pairedChildProfileId'] != null;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Hello, $fullName',
                style: const TextStyle(
                  color: darkText,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                email,
                style: const TextStyle(
                  color: purple,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This page is used to connect the child account or child device to a parent account using a pairing code.',
                style: TextStyle(color: grayText, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (isConnected) _buildConnectedView() else _buildPairingView(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPairingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: softPurple,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              const Icon(Icons.link_rounded, color: purple, size: 74),
              const SizedBox(height: 14),
              const Text(
                'Connect to Parent',
                style: TextStyle(
                  color: darkText,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the 6-digit pairing code generated from the parent account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: grayText, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: pairingCodeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isPairing ? null : pairWithParent,
                  style: FilledButton.styleFrom(
                    backgroundColor: purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(
                    isPairing ? 'Connecting...' : 'Pair Device',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.privacy_tip_rounded,
          title: 'Privacy Reminder',
          subtitle:
              'WellScreen connects usage-related monitoring only. It does not read private messages, passwords, calls, or sensitive files.',
          iconColor: purple,
        ),
      ],
    );
  }

  Widget _buildConnectedView() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: softPurple,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Column(
            children: [
              Icon(Icons.verified_rounded, color: Colors.green, size: 78),
              SizedBox(height: 14),
              Text(
                'Connected to Parent',
                style: TextStyle(
                  color: darkText,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This child account is already linked to a parent account for monitoring and digital wellness guidance.',
                textAlign: TextAlign.center,
                style: TextStyle(color: grayText, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.timer_rounded,
          title: 'Today’s Goal',
          subtitle: 'Stay within the screen-time goal set by the parent.',
          iconColor: purple,
        ),
        _infoCard(
          icon: Icons.self_improvement_rounded,
          title: 'Focus Status',
          subtitle: 'Focus mode and cooldown reminders will appear here.',
          iconColor: Colors.orange,
        ),
        _infoCard(
          icon: Icons.sync_rounded,
          title: 'Sync Status',
          subtitle:
              'Usage records will sync to the parent dashboard when internet is available.',
          iconColor: Colors.green,
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
  }) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, color: iconColor, size: 34),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            subtitle,
            style: const TextStyle(color: grayText, height: 1.4),
          ),
        ),
      ),
    );
  }
}
