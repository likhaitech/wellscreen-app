import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'alerts_reports_screen.dart';
import 'device_pairing_screen.dart';
import 'login_screen.dart';
import 'rule_settings_screen.dart';
import 'usage_summary_screen.dart';

class ParentDashboardScreen extends StatelessWidget {
  const ParentDashboardScreen({super.key});

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softOrange = Color(0xFFFFF4E5);

  Future<void> logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> childProfilesStream(String uid) {
    return FirebaseFirestore.instance
        .collection('child_profiles')
        .where('parentId', isEqualTo: uid)
        .snapshots();
  }

  bool isChildConnected(Map<String, dynamic> data) {
    final pairingStatus = (data['pairingStatus'] ?? '').toString();
    final childEmail = (data['childEmail'] ?? '').toString();
    final childAccountId = (data['childAccountId'] ?? '').toString();

    return pairingStatus == 'connected' ||
        childEmail.isNotEmpty ||
        childAccountId.isNotEmpty;
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
    final parentUser = FirebaseAuth.instance.currentUser;

    if (parentUser == null) {
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

    final parentEmail = parentUser.email ?? 'Parent account';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Parent Dashboard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => logout(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: childProfilesStream(parentUser.uid),
        builder: (context, snapshot) {
          final childDocs = snapshot.data?.docs ?? [];

          final connectedChildren = childDocs.where((doc) {
            return isChildConnected(doc.data());
          }).toList();

          final waitingChildren = childDocs.where((doc) {
            return !isChildConnected(doc.data());
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Welcome, Parent',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: darkText,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                parentEmail,
                style: const TextStyle(
                  color: purple,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Review paired child devices, usage summaries, alerts, recommendations, restrictions, and reports.',
                style: TextStyle(color: grayText, height: 1.4),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: DashboardMiniCard(
                      icon: Icons.child_care_rounded,
                      title: 'Paired',
                      value: '${connectedChildren.length}',
                      color: Colors.green,
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DashboardMiniCard(
                      icon: Icons.pending_actions_rounded,
                      title: 'Waiting',
                      value: '${waitingChildren.length}',
                      color: Colors.orange,
                      onTap: () {},
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Child Devices',
                    style: TextStyle(
                      color: darkText,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DevicePairingScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_link_rounded),
                    label: const Text(
                      'Add',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: purple),
                  ),
                )
              else if (childDocs.isEmpty)
                _emptyDeviceCard(context)
              else
                ...childDocs.map((doc) {
                  final data = doc.data();
                  return _childDeviceCard(context, data);
                }),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: DashboardMiniCard(
                      icon: Icons.timer_rounded,
                      title: 'Screen Time',
                      value: '4h 20m',
                      color: purple,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UsageSummaryScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DashboardMiniCard(
                      icon: Icons.warning_amber_rounded,
                      title: 'Alerts',
                      value: '3 New',
                      color: Colors.orange,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AlertsReportsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              const Card(
                elevation: 2,
                shadowColor: Colors.black12,
                child: ListTile(
                  contentPadding: EdgeInsets.all(18),
                  leading: Icon(Icons.apps_rounded, color: purple, size: 34),
                  title: Text(
                    'Most Used App',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: darkText,
                    ),
                  ),
                  subtitle: Text(
                    'YouTube - 1 hour 45 minutes today',
                    style: TextStyle(color: grayText),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const Card(
                elevation: 2,
                shadowColor: Colors.black12,
                child: ListTile(
                  contentPadding: EdgeInsets.all(18),
                  leading: Icon(
                    Icons.lightbulb_rounded,
                    color: purple,
                    size: 34,
                  ),
                  title: Text(
                    'Recommendation',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: darkText,
                    ),
                  ),
                  subtitle: Text(
                    'Set a cooldown timer after long app sessions.',
                    style: TextStyle(color: grayText),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DevicePairingScreen(),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: purple,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text(
                  'Device Pairing',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RuleSettingsScreen(),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.rule_rounded),
                label: const Text(
                  'Rule Settings',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyDeviceCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: softPurple,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const Icon(Icons.devices_other_rounded, color: purple, size: 72),
          const SizedBox(height: 14),
          const Text(
            'No Child Device Paired Yet',
            style: TextStyle(
              color: darkText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a child profile and generate a pairing code to connect a child Android device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: purple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.add_link_rounded),
            label: const Text(
              'Pair Child Device',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _childDeviceCard(BuildContext context, Map<String, dynamic> data) {
    final childName = (data['name'] ?? 'Child Profile').toString();
    final age = (data['age'] ?? '').toString();
    final childEmail = (data['childEmail'] ?? 'No child email connected yet')
        .toString();
    final childAccountId = (data['childAccountId'] ?? '').toString();
    final pairingStatus = (data['pairingStatus'] ?? 'waiting').toString();
    final connectedAt = formatDate(data['connectedAt']);
    final createdAt = formatDate(data['createdAt']);

    final connected = isChildConnected(data);

    final statusText = connected ? 'Connected' : 'Waiting for child device';
    final statusColor = connected ? Colors.green : Colors.orange;
    final statusBg = connected ? softGreen : softOrange;

    return Card(
      elevation: 3,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: statusBg,
                  child: Icon(
                    connected
                        ? Icons.verified_rounded
                        : Icons.pending_actions_rounded,
                    color: statusColor,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        childName,
                        style: const TextStyle(
                          color: darkText,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        age.isEmpty ? 'Age not set' : 'Age: $age',
                        style: const TextStyle(color: grayText, height: 1.3),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _deviceInfoRow(
              icon: Icons.email_rounded,
              label: 'Child Email',
              value: childEmail,
            ),

            _deviceInfoRow(
              icon: Icons.phone_android_rounded,
              label: 'Device',
              value: connected ? 'Android Device' : 'Not connected yet',
            ),

            _deviceInfoRow(
              icon: Icons.link_rounded,
              label: 'Pairing Status',
              value: pairingStatus,
            ),

            _deviceInfoRow(
              icon: Icons.access_time_rounded,
              label: connected ? 'Connected At' : 'Profile Created',
              value: connected ? connectedAt : createdAt,
            ),

            if (childAccountId.isNotEmpty)
              _deviceInfoRow(
                icon: Icons.badge_rounded,
                label: 'Child Account ID',
                value: childAccountId,
              ),
          ],
        ),
      ),
    );
  }

  Widget _deviceInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: purple, size: 20),
          const SizedBox(width: 10),
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: const TextStyle(
                color: grayText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: darkText,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardMiniCard extends StatelessWidget {
  const DashboardMiniCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF4B5563),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
