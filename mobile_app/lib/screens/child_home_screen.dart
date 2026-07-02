import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  final TextEditingController pairingCodeController = TextEditingController();

  bool isPairing = false;

  @override
  void dispose() {
    pairingCodeController.dispose();
    super.dispose();
  }

  Future<void> pairChildDevice() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again before pairing.');
      return;
    }

    final code = pairingCodeController.text.trim();

    if (code.length != 6) {
      showMessage('Please enter a valid 6-digit pairing code.');
      return;
    }

    setState(() => isPairing = true);

    try {
      final pairingRef = FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final pairingSnapshot = await transaction.get(pairingRef);

        if (!pairingSnapshot.exists) {
          throw Exception('Invalid pairing code.');
        }

        final data = pairingSnapshot.data();

        if (data == null) {
          throw Exception('Pairing code data is missing.');
        }

        final status = data['status'] as String? ?? 'inactive';
        final isPaired = data['isPaired'] as bool? ?? false;
        final expiresAt = data['expiresAt'];

        if (status != 'active') {
          throw Exception('This pairing code is no longer active.');
        }

        if (isPaired) {
          throw Exception('This pairing code is already paired.');
        }

        if (expiresAt is Timestamp &&
            expiresAt.toDate().isBefore(DateTime.now())) {
          throw Exception('This pairing code has expired.');
        }

        final childId = data['childId'] as String?;
        final parentId = data['parentId'] as String?;

        if (childId == null || parentId == null) {
          throw Exception('Pairing record is incomplete.');
        }

        final childProfileRef = FirebaseFirestore.instance
            .collection('child_profiles')
            .doc(childId);

        final childDeviceRef = FirebaseFirestore.instance
            .collection('child_devices')
            .doc(user.uid);

        transaction.set(pairingRef, {
          'status': 'paired',
          'isPaired': true,
          'childUserId': user.uid,
          'childEmail': user.email,
          'deviceName': 'Android Child Device',
          'pairedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(childProfileRef, {
          'childId': childId,
          'parentId': parentId,
          'childUserId': user.uid,
          'childEmail': user.email,
          'pairingCode': code,
          'pairingStatus': 'paired',
          'deviceStatus': 'connected',
          'deviceName': 'Android Child Device',
          'pairedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(childDeviceRef, {
          'childUserId': user.uid,
          'childEmail': user.email,
          'parentId': parentId,
          'childId': childId,
          'pairingCode': code,
          'deviceName': 'Android Child Device',
          'deviceStatus': 'connected',
          'pairingStatus': 'paired',
          'lastOpenedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      pairingCodeController.clear();
      showMessage('Device paired successfully.');
    } catch (e) {
      showMessage(_cleanErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => isPairing = false);
      }
    }
  }

  String _cleanErrorMessage(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Child Home',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Child Device Setup',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the pairing code from the parent device to connect this monitored Android device.',
            style: TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: softPurple,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.phone_android_rounded,
                  color: purple,
                  size: 72,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pair This Device',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ask your parent or guardian for the 6-digit pairing code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: grayText, height: 1.4),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: pairingCodeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '------',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isPairing ? null : pairChildDevice,
                    style: FilledButton.styleFrom(
                      backgroundColor: purple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(
                      isPairing ? 'Pairing...' : 'Connect to Parent',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Device Status',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 12),

          if (user == null)
            const ChildStatusCard(
              icon: Icons.info_outline_rounded,
              iconColor: Colors.orange,
              title: 'No child account found',
              subtitle: 'Please log in again before pairing this device.',
            )
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('child_devices')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ChildStatusCard(
                    icon: Icons.hourglass_top_rounded,
                    iconColor: purple,
                    title: 'Checking pairing status',
                    subtitle: 'Preparing child device information...',
                  );
                }

                if (snapshot.hasError) {
                  return ChildStatusCard(
                    icon: Icons.error_outline_rounded,
                    iconColor: Colors.red,
                    title: 'Unable to load device status',
                    subtitle: snapshot.error.toString(),
                  );
                }

                final data = snapshot.data?.data();

                if (data == null) {
                  return const ChildStatusCard(
                    icon: Icons.link_off_rounded,
                    iconColor: Colors.orange,
                    title: 'Not paired yet',
                    subtitle:
                        'Enter the parent pairing code above to connect this device.',
                  );
                }

                final pairingStatus =
                    data['pairingStatus'] as String? ?? 'waiting';
                final deviceStatus =
                    data['deviceStatus'] as String? ?? 'not_connected';
                final childEmail =
                    data['childEmail'] as String? ?? 'Child user';
                final code = data['pairingCode'] as String? ?? 'No code';

                return ChildStatusCard(
                  icon: Icons.check_circle_rounded,
                  iconColor: Colors.green,
                  title: 'Connected to Parent Account',
                  subtitle:
                      'Account: $childEmail\nPairing: ${_formatStatus(pairingStatus)}\nDevice: ${_formatStatus(deviceStatus)}\nCode: $code',
                );
              },
            ),

          const SizedBox(height: 16),

          const ChildStatusCard(
            icon: Icons.flag_rounded,
            iconColor: purple,
            title: 'Screen Goals',
            subtitle:
                'Daily screen-time goals and reminders will appear here after the parent configures rules.',
          ),

          const ChildStatusCard(
            icon: Icons.notifications_active_rounded,
            iconColor: Colors.orange,
            title: 'Reminders',
            subtitle:
                'Break reminders and cooldown prompts will appear here during prototype testing.',
          ),

          const ChildStatusCard(
            icon: Icons.lock_clock_rounded,
            iconColor: purple,
            title: 'Focus Mode',
            subtitle:
                'Focus mode and scheduled lock status will be shown here once restrictions are active.',
          ),
        ],
      ),
    );
  }

  String _formatStatus(String value) {
    return value.replaceAll('_', ' ').toUpperCase();
  }
}

class ChildStatusCard extends StatelessWidget {
  const ChildStatusCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
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
