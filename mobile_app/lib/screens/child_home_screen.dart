import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_rule.dart';
import '../services/app_rules_service.dart';
import '../widgets/wellscreen_bottom_nav.dart';
import 'login_screen.dart';
import 'profile_settings_screen.dart';

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
  static const Color pageBg = Color(0xFFF3F4F6);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softBlue = Color(0xFFEFF6FF);
  static const Color softRed = Color(0xFFFFEFEF);

  final AppRulesService _rulesService = AppRulesService();
  final pairingCodeController = TextEditingController();

  int currentIndex = 0;
  bool isPairing = false;
  bool isSharingLocation = false;

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
          'fullName': user.displayName ?? 'Student User',
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

      showConnectedSuccessDialog();
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      showMessage(message);
    } finally {
      if (mounted) {
        setState(() => isPairing = false);
      }
    }
  }

  Future<void> shareDemoLocation(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    if (childProfileId.isEmpty) {
      showMessage('Pair this device first before sharing GPS location.');
      return;
    }

    setState(() => isSharingLocation = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      final childProfileRef = firestore
          .collection('child_profiles')
          .doc(childProfileId);

      final demoLocation = {
        'latitude': 10.34030,
        'longitude': 123.94160,
        'label': 'Mandaue City, Cebu demo location',
      };

      await firestore.runTransaction((transaction) async {
        transaction.set(userRef, {
          'latestLocation': demoLocation,
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(childProfileRef, {
          'latestLocation': demoLocation,
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      if (!mounted) return;

      showMessage('Demo GPS location shared to parent dashboard.');
    } catch (e) {
      showMessage('Failed to share GPS location: $e');
    } finally {
      if (mounted) {
        setState(() => isSharingLocation = false);
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

  void handleBottomNavTap(int index) {
    if (index == 0) {
      setState(() => currentIndex = 0);
      return;
    }

    if (index == 1) {
      showMessage('Pairing is available on the student dashboard.');
    } else if (index == 2) {
      showMessage('Student usage reports will sync here.');
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
      );
    }
  }

  void showConnectedSuccessDialog() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          title: const Text(
            'Device Connected',
            textAlign: TextAlign.center,
            style: TextStyle(color: darkText, fontWeight: FontWeight.w900),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: softGreen,
                child: Icon(Icons.verified_rounded, color: teal, size: 55),
              ),
              SizedBox(height: 16),
              Text(
                'This student device is now connected to the parent dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: grayText,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
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

  String locationText(Map<String, dynamic> data) {
    final latestLocation = data['latestLocation'];

    if (latestLocation is Map) {
      final label = latestLocation['label'];
      final latitude = latestLocation['latitude'];
      final longitude = latestLocation['longitude'];

      if (label != null && label.toString().isNotEmpty) {
        return label.toString();
      }

      if (latitude != null && longitude != null) {
        return '${formatCoordinate(latitude)}, ${formatCoordinate(longitude)}';
      }
    }

    return 'Not shared yet';
  }

  String locationUpdatedText(Map<String, dynamic> data) {
    final updatedAt = data['locationUpdatedAt'];

    if (updatedAt is Timestamp) {
      return formatDate(updatedAt);
    }

    return 'Waiting for update';
  }

  String formatCoordinate(dynamic value) {
    if (value is num) {
      return value.toStringAsFixed(5);
    }

    return value.toString();
  }

  bool isConnected(Map<String, dynamic> data) {
    final pairingStatus = (data['pairingStatus'] ?? '').toString();

    return pairingStatus == 'connected' ||
        data['pairedParentId'] != null ||
        data['pairedChildProfileId'] != null;
  }

  String appTitle(AppRule rule) {
    final name = rule.appName.trim();

    if (name.isNotEmpty) {
      return name;
    }

    return rule.packageName.trim().isNotEmpty
        ? rule.packageName
        : 'Unknown App';
  }

  IconData appIconForName(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('youtube')) {
      return Icons.play_arrow_rounded;
    }

    if (lower.contains('tiktok') || lower.contains('music')) {
      return Icons.music_note_rounded;
    }

    if (lower.contains('facebook') || lower.contains('meta')) {
      return Icons.public_rounded;
    }

    if (lower.contains('game') ||
        lower.contains('mobile legends') ||
        lower.contains('roblox')) {
      return Icons.sports_esports_rounded;
    }

    if (lower.contains('chrome') ||
        lower.contains('browser') ||
        lower.contains('google')) {
      return Icons.language_rounded;
    }

    if (lower.contains('message') || lower.contains('chat')) {
      return Icons.chat_bubble_rounded;
    }

    return Icons.apps_rounded;
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
      backgroundColor: pageBg,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data() ?? <String, dynamic>{};
            final connected = isConnected(data);

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              children: [
                _topBar(),
                const SizedBox(height: 18),
                _studentProfileCard(data, connected),
                const SizedBox(height: 22),
                if (!connected) _pairingCard(),
                if (!connected) const SizedBox(height: 22),
                _screenTimeAndRiskSection(),
                const SizedBox(height: 18),
                _gpsCard(data, connected),
                if (connected) const SizedBox(height: 22),
                if (connected) _activeRulesCard(data),
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
          WellScreenNavItem(icon: Icons.link_rounded, label: 'Pairing'),
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
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileSettingsScreen(),
                ),
              );
            },
            icon: const Icon(
              Icons.account_circle_rounded,
              color: Colors.white,
              size: 34,
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

  Widget _studentProfileCard(Map<String, dynamic> data, bool connected) {
    final user = FirebaseAuth.instance.currentUser;

    final fullName = (data['fullName'] ?? user?.displayName ?? 'Student User')
        .toString();

    final email = (data['email'] ?? user?.email ?? '').toString();

    final photoUrl = (data['profilePhotoUrl'] ?? user?.photoURL ?? '')
        .toString();

    return _whiteCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;

          final profileRow = Row(
            children: [
              _profileAvatar(photoUrl, connected),
              const SizedBox(width: 14),
              Expanded(
                child: _profileInfo(
                  fullName: fullName,
                  email: email,
                  connected: connected,
                ),
              ),
            ],
          );

          final buttons = Row(
            children: [
              Expanded(
                child: _smallPurpleButton(
                  label: connected ? 'Share GPS' : 'Pair Device',
                  onTap: () {
                    if (connected) {
                      shareDemoLocation(data);
                    } else {
                      showMessage('Enter the pairing code below.');
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _smallPurpleButton(
                  label: 'Profile',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileSettingsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              children: [profileRow, const SizedBox(height: 14), buttons],
            );
          }

          return Row(
            children: [
              Expanded(child: profileRow),
              const SizedBox(width: 14),
              SizedBox(width: 250, child: buttons),
            ],
          );
        },
      ),
    );
  }

  Widget _profileAvatar(String photoUrl, bool connected) {
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 40,
        backgroundColor: connected ? softGreen : softBlue,
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: 76,
            height: 76,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                connected ? Icons.person_rounded : Icons.person_add_alt_rounded,
                color: connected ? teal : purple,
                size: 45,
              );
            },
          ),
        ),
      );
    }

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
    required String fullName,
    required String email,
    required bool connected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$fullName's Phone",
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
                connected ? 'Online - $email' : 'Waiting for parent pairing',
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

  Widget _pairingCard() {
    return _whiteCard(
      child: Column(
        children: [
          const Icon(Icons.link_rounded, color: purple, size: 62),
          const SizedBox(height: 12),
          const Text(
            'Connect to Parent Dashboard',
            textAlign: TextAlign.center,
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
            style: TextStyle(
              color: grayText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
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
              icon: const Icon(Icons.verified_rounded),
              label: Text(
                isPairing ? 'Connecting...' : 'Pair Student Device',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
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
              'Wellness Level',
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

  Widget _gpsCard(Map<String, dynamic> data, bool connected) {
    final location = locationText(data);
    final updated = locationUpdatedText(data);

    return _whiteCard(
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: connected ? softGreen : softRed,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              connected
                  ? Icons.location_on_rounded
                  : Icons.location_off_rounded,
              color: connected ? teal : Colors.redAccent,
              size: 34,
            ),
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
                  connected ? location : 'Pair device first',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: grayText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  connected
                      ? 'Updated: $updated'
                      : 'Location sharing becomes available after pairing.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grayText, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: connected && !isSharingLocation
                ? () => shareDemoLocation(data)
                : null,
            icon: Icon(
              isSharingLocation
                  ? Icons.sync_rounded
                  : Icons.my_location_rounded,
              color: connected ? purple : grayText,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeRulesCard(Map<String, dynamic> data) {
    final parentId = (data['pairedParentId'] ?? '').toString();

    if (parentId.isEmpty) {
      return _rulesMessageCard(
        icon: Icons.sync_problem_rounded,
        title: 'Rules Sync Waiting',
        message:
            'The parent account is connected, but the rule source is not ready yet.',
      );
    }

    return StreamBuilder<List<AppRule>>(
      stream: _rulesService.watchRulesForParent(parentId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _rulesMessageCard(
            icon: Icons.warning_rounded,
            title: 'Rules Sync Error',
            message: 'Unable to load monitored and restricted apps right now.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _whiteCard(
            child: const Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: purple,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Loading parent app rules...',
                    style: TextStyle(
                      color: grayText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final rules = snapshot.data ?? <AppRule>[];

        final activeRules =
            rules
                .where((rule) => rule.monitorEnabled || rule.restrictEnabled)
                .toList()
              ..sort(
                (a, b) => appTitle(
                  a,
                ).toLowerCase().compareTo(appTitle(b).toLowerCase()),
              );

        final monitoredCount = activeRules
            .where((rule) => rule.monitorEnabled)
            .length;

        final restrictedCount = activeRules
            .where((rule) => rule.restrictEnabled)
            .length;

        final restrictedRules = activeRules
            .where((rule) => rule.restrictEnabled)
            .toList();

        final monitoredOnlyRules = activeRules
            .where((rule) => rule.monitorEnabled && !rule.restrictEnabled)
            .toList();

        if (activeRules.isEmpty) {
          return _rulesMessageCard(
            icon: Icons.rule_folder_rounded,
            title: 'No Active App Rules',
            message:
                'When the parent selects Monitor or Restrict in View Rules, the apps will appear here.',
          );
        }

        return _whiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: softBlue,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: purple,
                      size: 31,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Parent App Rules',
                          style: TextStyle(
                            color: darkText,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Synced from parent dashboard',
                          style: TextStyle(
                            color: grayText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ruleCountBadge(
                      label: 'Monitored',
                      count: monitoredCount,
                      icon: Icons.visibility_rounded,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ruleCountBadge(
                      label: 'Restricted',
                      count: restrictedCount,
                      icon: Icons.block_rounded,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              if (restrictedRules.isNotEmpty) const SizedBox(height: 18),
              if (restrictedRules.isNotEmpty)
                _appRuleGroup(
                  title: 'Restricted Apps',
                  rules: restrictedRules,
                  color: const Color(0xFFDC2626),
                  icon: Icons.block_rounded,
                ),
              if (monitoredOnlyRules.isNotEmpty) const SizedBox(height: 18),
              if (monitoredOnlyRules.isNotEmpty)
                _appRuleGroup(
                  title: 'Monitored Apps',
                  rules: monitoredOnlyRules,
                  color: const Color(0xFF2563EB),
                  icon: Icons.visibility_rounded,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _rulesMessageCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return _whiteCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: softBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: purple, size: 31),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
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

  Widget _ruleCountBadge({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appRuleGroup({
    required String title,
    required List<AppRule> rules,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...rules.map((rule) => _appRuleRow(rule)),
      ],
    );
  }

  Widget _appRuleRow(AppRule rule) {
    final name = appTitle(rule);
    final restricted = rule.restrictEnabled;
    final color = restricted
        ? const Color(0xFFDC2626)
        : const Color(0xFF2563EB);

    final status = restricted
        ? rule.monitorEnabled
              ? 'Blocked + Monitored'
              : 'Blocked'
        : 'Monitored';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: color,
            child: Icon(appIconForName(name), color: Colors.white, size: 26),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rule.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: grayText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
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
            children: const [
              Expanded(
                child: Text(
                  'Top Apps Today',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Demo Data',
                style: TextStyle(color: purple, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
}
