import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/wellscreen_bottom_nav.dart';
import 'alerts_reports_screen.dart';
import 'device_pairing_screen.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';
import 'rule_settings_screen.dart';
import 'usage_summary_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color pageBg = Color(0xFFF3F4F6);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softBlue = Color(0xFFEFF6FF);

  int currentIndex = 0;

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

  String locationText(Map<String, dynamic>? data) {
    if (data == null) return 'Not shared yet';

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

  String locationUpdatedText(Map<String, dynamic>? data) {
    if (data == null) return 'Waiting for update';

    final updatedAt = data['locationUpdatedAt'];

    if (updatedAt is Timestamp) {
      return formatDate(updatedAt);
    }

    return 'Waiting for update';
  }

  void handleBottomNavTap(int index) {
    if (index == 0) {
      setState(() => currentIndex = 0);
      return;
    }

    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
      );
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsageSummaryScreen()),
      );
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
      );
    }
  }

  Map<String, dynamic>? getPrimaryChild(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> childDocs,
  ) {
    if (childDocs.isEmpty) return null;

    for (final doc in childDocs) {
      final data = doc.data();
      if (isChildConnected(data)) return data;
    }

    return childDocs.first.data();
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

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: childProfilesStream(parentUser.uid),
          builder: (context, snapshot) {
            final childDocs = snapshot.data?.docs ?? [];
            final primaryChild = getPrimaryChild(childDocs);

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              children: [
                _topBar(),
                const SizedBox(height: 18),
                _deviceProfileCard(primaryChild),
                const SizedBox(height: 22),
                _screenTimeAndRiskSection(),
                const SizedBox(height: 18),
                _gpsCard(primaryChild),
                const SizedBox(height: 22),
                _topAppsSection(),
                const SizedBox(height: 22),
                _weeklyTrendSection(),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: WellScreenBottomNav(
        currentIndex: currentIndex,
        items: const [
          WellScreenNavItem(icon: Icons.home_rounded, label: 'Home'),
          WellScreenNavItem(
            icon: Icons.phone_android_rounded,
            label: 'Devices',
          ),
          WellScreenNavItem(icon: Icons.analytics_rounded, label: 'Reports'),
          WellScreenNavItem(icon: Icons.settings_rounded, label: 'Settings'),
        ],
        onTap: handleBottomNavTap,
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [purple, deepPurple],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          _logoBox(),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'WellScreen',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Alerts',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlertsReportsScreen()),
              );
            },
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white,
              size: 33,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBox() {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(31),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31),
        child: Image.asset(
          'assets/icons/wellscreen_icon.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.health_and_safety_rounded,
              color: purple,
              size: 38,
            );
          },
        ),
      ),
    );
  }

  Widget _deviceProfileCard(Map<String, dynamic>? child) {
    final childName = (child?['name'] ?? 'Child Profile').toString();
    final childEmail = (child?['childEmail'] ?? 'Pair a child account first')
        .toString();
    final connected = child != null && isChildConnected(child);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;

        return _whiteCard(
          padding: const EdgeInsets.all(18),
          child: compact
              ? Column(
                  children: [
                    Row(
                      children: [
                        _profileAvatar(connected),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _profileInfo(
                            childName: childName,
                            childEmail: childEmail,
                            connected: connected,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _smallPurpleButton(
                            label: 'View Location',
                            onTap: () {
                              showMessage(
                                'GPS Location: ${locationText(child)}',
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _smallPurpleButton(
                            label: 'View Rules',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RuleSettingsScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    _profileAvatar(connected),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _profileInfo(
                        childName: childName,
                        childEmail: childEmail,
                        connected: connected,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        SizedBox(
                          width: 130,
                          child: _smallPurpleButton(
                            label: 'View Location',
                            onTap: () {
                              showMessage(
                                'GPS Location: ${locationText(child)}',
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 130,
                          child: _smallPurpleButton(
                            label: 'View Rules',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RuleSettingsScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _profileAvatar(bool connected) {
    return CircleAvatar(
      radius: 40,
      backgroundColor: connected ? softGreen : softBlue,
      child: Icon(
        connected ? Icons.person_rounded : Icons.person_add_alt_rounded,
        color: connected ? teal : purple,
        size: 45,
      ),
    );
  }

  Widget _profileInfo({
    required String childName,
    required String childEmail,
    required bool connected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          connected ? '$childName’s Phone' : childName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: darkText,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: connected ? teal : Colors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                connected ? 'Online • $childEmail' : 'Waiting for pairing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: grayText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _smallPurpleButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: purple,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _screenTimeAndRiskSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _screenTimeCard()),
        const SizedBox(width: 14),
        Expanded(child: _riskCard()),
      ],
    );
  }

  Widget _screenTimeCard() {
    return _whiteCard(
      child: SizedBox(
        height: 170,
        child: Column(
          children: [
            const Text(
              'Screen Time\nToday',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: darkText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const Spacer(),
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '4',
                      style: TextStyle(
                        fontSize: 43,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: 'h ',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: '25',
                      style: TextStyle(
                        fontSize: 43,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: 'm',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Daily Limit: 6h',
              style: TextStyle(color: grayText, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: const LinearProgressIndicator(
                value: 0.72,
                minHeight: 7,
                color: purple,
                backgroundColor: Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskCard() {
    return _whiteCard(
      child: const SizedBox(
        height: 170,
        child: Column(
          children: [
            Text(
              'Risk Level',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: darkText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Spacer(),
            Icon(Icons.shield_rounded, color: teal, size: 62),
            SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Low Risk',
                style: TextStyle(
                  color: teal,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '32/100',
                style: TextStyle(
                  color: darkText,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gpsCard(Map<String, dynamic>? child) {
    final location = locationText(child);
    final updated = locationUpdatedText(child);

    return _whiteCard(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: softGreen,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.location_on_rounded, color: teal, size: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GPS Location',
                  style: TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: grayText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Updated: $updated',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grayText, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              showMessage('GPS Location: $location');
            },
            icon: const Icon(
              Icons.my_location_rounded,
              color: purple,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  Widget _topAppsSection() {
    return _whiteCard(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Top Apps Today',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UsageSummaryScreen(),
                    ),
                  );
                },
                child: const Text(
                  'View All',
                  style: TextStyle(color: purple, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _appUsageRow(
            icon: Icons.play_arrow_rounded,
            iconColor: Colors.red,
            appName: 'YouTube',
            time: '1h 45m',
            value: 0.70,
          ),
          _appUsageRow(
            icon: Icons.music_note_rounded,
            iconColor: Colors.black,
            appName: 'TikTok',
            time: '1h 10m',
            value: 0.52,
          ),
          _appUsageRow(
            icon: Icons.public_rounded,
            iconColor: Colors.blue,
            appName: 'Facebook',
            time: '40m',
            value: 0.41,
          ),
          _appUsageRow(
            icon: Icons.sports_esports_rounded,
            iconColor: Colors.blueGrey,
            appName: 'Mobile Game',
            time: '50m',
            value: 0.47,
          ),
        ],
      ),
    );
  }

  Widget _appUsageRow({
    required IconData icon,
    required Color iconColor,
    required String appName,
    required String time,
    required double value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: iconColor,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    color: purple,
                    backgroundColor: const Color(0xFFD1D5DB),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              time,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: darkText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyTrendSection() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final values = [8.0, 4.2, 6.0, 3.3, 8.0, 5.5, 7.2];

    return _whiteCard(
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  'Weekly Trend',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'This Week',
                style: TextStyle(color: grayText, fontWeight: FontWeight.w800),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: grayText),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(days.length, (index) {
                final height = 24 + (values[index] / 8.0) * 88;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 28,
                        height: height,
                        decoration: BoxDecoration(
                          color: purple,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          days[index],
                          style: const TextStyle(
                            color: purple,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _whiteCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
