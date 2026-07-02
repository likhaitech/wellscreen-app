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
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softOrange = Color(0xFFFFF4E5);
  static const Color softBlue = Color(0xFFEFF6FF);
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

  String locationText(Map<String, dynamic> data) {
    final latestLocation = data['latestLocation'];

    if (latestLocation is Map) {
      final latitude = latestLocation['latitude'];
      final longitude = latestLocation['longitude'];

      if (latitude != null && longitude != null) {
        return '${formatCoordinate(latitude)}, ${formatCoordinate(longitude)}';
      }
    }

    return 'Not shared yet';
  }

  String formatCoordinate(dynamic value) {
    if (value is num) {
      return value.toStringAsFixed(5);
    }

    return value.toString();
  }

  String locationUpdatedText(Map<String, dynamic> data) {
    final updatedAt = data['locationUpdatedAt'];

    if (updatedAt is Timestamp) {
      return formatDate(updatedAt);
    }

    return 'Waiting for update';
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
          style: TextStyle(fontWeight: FontWeight.w900),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _headerCard(parentEmail),
              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: DashboardStatCard(
                      icon: Icons.verified_rounded,
                      title: 'Paired',
                      value: '${connectedChildren.length}',
                      color: teal,
                      backgroundColor: softGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DashboardStatCard(
                      icon: Icons.pending_actions_rounded,
                      title: 'Waiting',
                      value: '${waitingChildren.length}',
                      color: Colors.orange,
                      backgroundColor: softOrange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DashboardStatCard(
                      icon: Icons.devices_rounded,
                      title: 'Total',
                      value: '${childDocs.length}',
                      color: purple,
                      backgroundColor: softPurple,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              _sectionHeader(
                title: 'Child Devices',
                actionLabel: 'Add',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DevicePairingScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 10),

              if (snapshot.connectionState == ConnectionState.waiting)
                _loadingDeviceCard()
              else if (childDocs.isEmpty)
                _emptyDeviceCard(context)
              else
                ...childDocs.map((doc) {
                  return _childDeviceCard(doc.data());
                }),

              const SizedBox(height: 22),

              const Text(
                'Usage Snapshot',
                style: TextStyle(
                  color: darkText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 10),

              _usageOverviewCard(),

              const SizedBox(height: 22),

              const Text(
                'Quick Actions',
                style: TextStyle(
                  color: darkText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _quickActionCard(
                      context: context,
                      icon: Icons.add_link_rounded,
                      title: 'Pair Device',
                      subtitle: 'Connect child phone',
                      color: purple,
                      backgroundColor: softPurple,
                      destination: const DevicePairingScreen(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _quickActionCard(
                      context: context,
                      icon: Icons.bar_chart_rounded,
                      title: 'Usage',
                      subtitle: 'View reports',
                      color: teal,
                      backgroundColor: softGreen,
                      destination: const UsageSummaryScreen(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _quickActionCard(
                      context: context,
                      icon: Icons.rule_rounded,
                      title: 'Rules',
                      subtitle: 'Set restrictions',
                      color: Colors.orange,
                      backgroundColor: softOrange,
                      destination: const RuleSettingsScreen(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _quickActionCard(
                      context: context,
                      icon: Icons.notifications_active_rounded,
                      title: 'Alerts',
                      subtitle: 'Review events',
                      color: Colors.redAccent,
                      backgroundColor: softRed,
                      destination: const AlertsReportsScreen(),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard(String email) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [purple, deepPurple],
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
            child: const Icon(
              Icons.family_restroom_rounded,
              color: purple,
              size: 36,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome, Parent',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
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
                const Text(
                  'Monitor paired child devices, review alerts, and guide healthy screen habits.',
                  style: TextStyle(color: Colors.white, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: darkText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            actionLabel,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _loadingDeviceCard() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: softPurple,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(child: CircularProgressIndicator(color: purple)),
    );
  }

  Widget _emptyDeviceCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: softBlue,
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
            'Create a child profile and generate a pairing code to connect a monitored Android device.',
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
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.add_link_rounded),
            label: const Text(
              'Pair Child Device',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _childDeviceCard(Map<String, dynamic> data) {
    final childName = (data['name'] ?? 'Child Profile').toString();
    final age = (data['age'] ?? '').toString();
    final childEmail = (data['childEmail'] ?? 'No child email connected yet')
        .toString();
    final childAccountId = (data['childAccountId'] ?? '').toString();
    final pairingStatus = (data['pairingStatus'] ?? 'waiting').toString();

    final connected = isChildConnected(data);
    final statusText = connected ? 'Connected' : 'Waiting';
    final statusColor = connected ? teal : Colors.orange;
    final statusBg = connected ? softGreen : softOrange;

    final connectedAt = formatDate(data['connectedAt']);
    final createdAt = formatDate(data['createdAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: statusBg,
                child: Icon(
                  connected
                      ? Icons.verified_rounded
                      : Icons.pending_actions_rounded,
                  color: statusColor,
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      childName,
                      style: const TextStyle(
                        color: darkText,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      age.isEmpty ? 'Age not set' : 'Age: $age',
                      style: const TextStyle(
                        color: grayText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(
                text: statusText,
                textColor: statusColor,
                backgroundColor: statusBg,
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
            label: 'Pairing',
            value: pairingStatus,
          ),
          _deviceInfoRow(
            icon: Icons.location_on_rounded,
            label: 'Location',
            value: locationText(data),
          ),
          _deviceInfoRow(
            icon: Icons.update_rounded,
            label: 'GPS Updated',
            value: locationUpdatedText(data),
          ),
          _deviceInfoRow(
            icon: Icons.access_time_rounded,
            label: connected ? 'Connected At' : 'Created At',
            value: connected ? connectedAt : createdAt,
          ),

          if (childAccountId.isNotEmpty)
            _deviceInfoRow(
              icon: Icons.badge_rounded,
              label: 'Child UID',
              value: childAccountId,
            ),
        ],
      ),
    );
  }

  Widget _statusPill({
    required String text,
    required Color textColor,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w900,
          fontSize: 12,
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
            width: 105,
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

  Widget _usageOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: softPurple,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          _usageRow(
            icon: Icons.timer_rounded,
            title: 'Today’s Screen Time',
            value: '4h 20m',
            color: purple,
          ),
          const Divider(height: 24),
          _usageRow(
            icon: Icons.apps_rounded,
            title: 'Most Used App',
            value: 'YouTube - 1h 45m',
            color: teal,
          ),
          const Divider(height: 24),
          _usageRow(
            icon: Icons.warning_amber_rounded,
            title: 'Latest Alert',
            value: 'Late-night use detected',
            color: Colors.orange,
          ),
          const Divider(height: 24),
          _usageRow(
            icon: Icons.lightbulb_rounded,
            title: 'Recommendation',
            value: 'Set a cooldown timer',
            color: purple,
          ),
        ],
      ),
    );
  }

  Widget _usageRow({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.white,
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: grayText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _quickActionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color backgroundColor,
    required Widget destination,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: darkText,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: grayText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardStatCard extends StatelessWidget {
  const DashboardStatCard({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 2),
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
