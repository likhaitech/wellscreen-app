import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'alerts_reports_screen.dart';
import 'rule_settings_screen.dart';

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);

  final TextEditingController childNameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();

  String? pairingCode;
  String? selectedChildId;
  String? selectedChildName;
  int? selectedChildAge;

  String? selectedChildEmail;
  String? selectedDeviceName;
  String? selectedLastReportDate;

  String selectedPairingStatus = 'waiting';
  String selectedDeviceStatus = 'not_connected';

  bool isSaving = false;
  bool showAddChildForm = false;

  bool get selectedChildIsPaired =>
      selectedPairingStatus == 'paired' || selectedDeviceStatus == 'connected';

  @override
  void initState() {
    super.initState();

    unawaited(_syncParentNameToExistingPairings());
  }

  @override
  void dispose() {
    childNameController.dispose();
    ageController.dispose();
    super.dispose();
  }

  Future<String> _getParentName(User user) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = snapshot.data();

      final fullName = data?['fullName'];

      if (fullName is String && fullName.trim().isNotEmpty) {
        return fullName.trim();
      }

      final name = data?['name'];

      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }

      final displayName = data?['displayName'];

      if (displayName is String && displayName.trim().isNotEmpty) {
        return displayName.trim();
      }
    } catch (_) {
      // Fall back to Firebase Auth information below.
    }

    final authDisplayName = user.displayName;

    if (authDisplayName != null && authDisplayName.trim().isNotEmpty) {
      return authDisplayName.trim();
    }

    return 'Parent / Guardian';
  }

  Future<void> _syncParentNameToExistingPairings() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    try {
      final parentName = await _getParentName(user);

      final children = await FirebaseFirestore.instance
          .collection('child_profiles')
          .where('parentId', isEqualTo: user.uid)
          .get();

      for (final childDoc in children.docs) {
        final data = childDoc.data();

        await childDoc.reference.set({
          'parentName': parentName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final childUserId = data['childUserId'] as String?;

        if (childUserId == null || childUserId.isEmpty) {
          continue;
        }

        final deviceRef = FirebaseFirestore.instance
            .collection('child_devices')
            .doc(childUserId);

        final deviceSnapshot = await deviceRef.get();

        if (!deviceSnapshot.exists) {
          continue;
        }

        await deviceRef.set({
          'parentName': parentName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // Do not prevent the Devices screen from loading if an older
      // pairing record cannot be backfilled.
    }
  }

  String generateCode() {
    final random = Random();

    return (100000 + random.nextInt(900000)).toString();
  }

  void openAddChildForm() {
    childNameController.clear();
    ageController.clear();

    setState(() {
      selectedChildId = null;
      selectedChildName = null;
      selectedChildAge = null;

      selectedChildEmail = null;
      selectedDeviceName = null;
      selectedLastReportDate = null;

      pairingCode = null;

      selectedPairingStatus = 'waiting';
      selectedDeviceStatus = 'not_connected';

      showAddChildForm = true;
    });
  }

  void cancelAddChildForm() {
    childNameController.clear();
    ageController.clear();

    setState(() {
      showAddChildForm = false;
    });
  }

  Future<void> createPairingCode() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final childName = childNameController.text.trim();
    final ageText = ageController.text.trim();
    final age = int.tryParse(ageText);

    if (childName.isEmpty || ageText.isEmpty) {
      showMessage('Please enter the child profile name and age.');
      return;
    }

    if (age == null || age <= 0 || age > 15) {
      showMessage('Please enter a valid child age from 1 to 15.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final parentName = await _getParentName(user);

      final code = generateCode();

      final expiresAt = DateTime.now().add(const Duration(minutes: 30));

      final isNewChild = selectedChildId == null;

      final childRef = isNewChild
          ? FirebaseFirestore.instance.collection('child_profiles').doc()
          : FirebaseFirestore.instance
                .collection('child_profiles')
                .doc(selectedChildId);

      final childData = <String, dynamic>{
        'childId': childRef.id,
        'parentId': user.uid,
        'parentName': parentName,
        'name': childName,
        'age': age,
        'pairingCode': code,
        'pairingStatus': 'waiting',
        'deviceStatus': 'not_connected',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isNewChild) {
        childData['createdAt'] = FieldValue.serverTimestamp();
      }

      await childRef.set(childData, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code)
          .set({
            'pairingCode': code,
            'parentId': user.uid,
            'parentName': parentName,
            'parentEmail': user.email,
            'childId': childRef.id,
            'childName': childName,
            'childAge': age,
            'status': 'active',
            'isPaired': false,
            'deviceName': null,
            'childEmail': null,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(expiresAt),
          });

      if (!mounted) return;

      setState(() {
        selectedChildId = childRef.id;
        selectedChildName = childName;
        selectedChildAge = age;

        selectedChildEmail = null;
        selectedDeviceName = null;
        selectedLastReportDate = null;

        pairingCode = code;

        selectedPairingStatus = 'waiting';
        selectedDeviceStatus = 'not_connected';

        showAddChildForm = false;
      });

      showMessage('Pairing code generated successfully.');
    } catch (e) {
      showMessage('Pairing error: $e');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Future<void> copyPairingCode() async {
    final code = pairingCode;

    if (code == null) {
      showMessage('Generate a pairing code first.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: code));

    showMessage('Pairing code copied.');
  }

  void selectChildProfile(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final ageValue = data['age'];

    final age = ageValue is num ? ageValue.toInt() : 0;

    final name = data['name'] as String? ?? 'Child Profile';

    setState(() {
      selectedChildId = doc.id;
      selectedChildName = name;
      selectedChildAge = age;

      selectedChildEmail = data['childEmail'] as String?;

      selectedDeviceName = data['deviceName'] as String?;

      selectedLastReportDate = data['lastUsageReportDate'] as String?;

      pairingCode = data['pairingCode'] as String?;

      selectedPairingStatus = data['pairingStatus'] as String? ?? 'waiting';

      selectedDeviceStatus = data['deviceStatus'] as String? ?? 'not_connected';

      childNameController.text = name;
      ageController.text = age.toString();

      showAddChildForm = false;
    });
  }

  void openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlertsReportsScreen()),
    );
  }

  void openRules() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RuleSettingsScreen()),
    );
  }

  void handleBottomNavigation(int index) {
    switch (index) {
      case 0:
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        break;

      case 1:
        break;

      case 2:
        openReports();
        break;

      case 3:
        openRules();
        break;
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
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Image.asset(
                'assets/icons/wellscreen_icon.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 11),
            const Text(
              'Child Devices',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reports',
            onPressed: openReports,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        children: [
          const Text(
            'Manage Devices',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'Connect, review, and manage Android devices linked to your child profiles.',
            style: TextStyle(color: grayText, height: 1.4),
          ),

          const SizedBox(height: 22),

          if (user == null)
            const DeviceStatusCard(
              icon: Icons.info_outline_rounded,
              iconColor: Colors.orange,
              title: 'No Parent Account Found',
              subtitle: 'Please log in again before managing child devices.',
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('child_profiles')
                  .where('parentId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const DeviceStatusCard(
                    icon: Icons.hourglass_top_rounded,
                    iconColor: purple,
                    title: 'Loading Child Devices',
                    subtitle:
                        'Preparing child profile and device information...',
                  );
                }

                if (snapshot.hasError) {
                  return DeviceStatusCard(
                    icon: Icons.error_outline_rounded,
                    iconColor: Colors.red,
                    title: 'Unable to Load Child Devices',
                    subtitle: snapshot.error.toString(),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const DeviceStatusCard(
                    icon: Icons.phone_android_rounded,
                    iconColor: purple,
                    title: 'No Child Devices Yet',
                    subtitle:
                        'Add a child device to generate a pairing code and begin monitoring.',
                  );
                }

                final connectedCount = docs.where((doc) {
                  final data = doc.data();

                  final pairingStatus =
                      data['pairingStatus'] as String? ?? 'waiting';

                  final deviceStatus =
                      data['deviceStatus'] as String? ?? 'not_connected';

                  return pairingStatus == 'paired' ||
                      deviceStatus == 'connected';
                }).length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DeviceSummaryCard(
                      totalDevices: docs.length,
                      connectedDevices: connectedCount,
                    ),

                    const SizedBox(height: 18),

                    const Text(
                      'Child Devices',
                      style: TextStyle(
                        color: darkText,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 12),

                    ...docs.map((doc) {
                      final data = doc.data();

                      final name = data['name'] as String? ?? 'Child Profile';

                      final ageValue = data['age'];

                      final age = ageValue is num ? ageValue.toInt() : 0;

                      final pairingStatus =
                          data['pairingStatus'] as String? ?? 'waiting';

                      final deviceStatus =
                          data['deviceStatus'] as String? ?? 'not_connected';

                      final deviceName = data['deviceName'] as String?;

                      final childEmail = data['childEmail'] as String?;

                      final lastReportDate =
                          data['lastUsageReportDate'] as String?;

                      return ChildDeviceCard(
                        name: name,
                        age: age,
                        pairingStatus: pairingStatus,
                        deviceStatus: deviceStatus,
                        deviceName: deviceName,
                        childEmail: childEmail,
                        lastReportDate: lastReportDate,
                        isSelected: selectedChildId == doc.id,
                        onViewDetails: () {
                          selectChildProfile(doc);
                        },
                      );
                    }),
                  ],
                );
              },
            ),

          const SizedBox(height: 16),

          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: openAddChildForm,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Child Device',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),

          if (showAddChildForm) ...[
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: softPurple,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.add_link_rounded, color: purple),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Add Child Device',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: darkText,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Create a child profile and generate a secure 6-digit pairing code for the child phone.',
                    style: TextStyle(color: grayText, height: 1.4),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: childNameController,
                    decoration: InputDecoration(
                      labelText: 'Child Profile Name',
                      prefixIcon: const Icon(Icons.child_care_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Age',
                      helperText: 'WellScreen currently supports ages 1 to 15.',
                      prefixIcon: const Icon(Icons.cake_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: isSaving ? null : createPairingCode,
                      style: FilledButton.styleFrom(backgroundColor: purple),
                      icon: const Icon(Icons.link_rounded),
                      label: Text(
                        isSaving ? 'Generating...' : 'Generate Pairing Code',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: isSaving ? null : cancelAddChildForm,
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (selectedChildId != null && !showAddChildForm) ...[
            const SizedBox(height: 28),

            const Text(
              'Device Details',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: darkText,
              ),
            ),

            const SizedBox(height: 12),

            SelectedDeviceDetailsCard(
              name: selectedChildName ?? 'Child Profile',
              age: selectedChildAge ?? 0,
              pairingStatus: selectedPairingStatus,
              deviceStatus: selectedDeviceStatus,
              childEmail: selectedChildEmail,
              deviceName: selectedDeviceName,
              lastReportDate: selectedLastReportDate,
              onViewLocation: openReports,
              onViewRules: openRules,
            ),

            if (!selectedChildIsPaired) ...[
              const SizedBox(height: 18),

              PairingCodeCard(
                code: pairingCode ?? '------',
                hasCode: pairingCode != null,
                onCopy: copyPairingCode,
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: isSaving ? null : createPairingCode,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    pairingCode == null
                        ? 'Generate Pairing Code'
                        : 'Generate New Pairing Code',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: handleBottomNavigation,
        backgroundColor: Colors.white,
        indicatorColor: softPurple,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.phone_android_outlined),
            selectedIcon: Icon(Icons.phone_android_rounded, color: purple),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class DeviceSummaryCard extends StatelessWidget {
  const DeviceSummaryCard({
    super.key,
    required this.totalDevices,
    required this.connectedDevices,
  });

  final int totalDevices;
  final int connectedDevices;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: softPurple,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 27,
            backgroundColor: Colors.white,
            child: Icon(Icons.devices_rounded, color: purple, size: 30),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Device Overview',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  '$connectedDevices of $totalDevices device${totalDevices == 1 ? '' : 's'} connected',
                  style: const TextStyle(
                    color: grayText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          Text(
            '$connectedDevices/$totalDevices',
            style: const TextStyle(
              color: purple,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class ChildDeviceCard extends StatelessWidget {
  const ChildDeviceCard({
    super.key,
    required this.name,
    required this.age,
    required this.pairingStatus,
    required this.deviceStatus,
    required this.deviceName,
    required this.childEmail,
    required this.lastReportDate,
    required this.isSelected,
    required this.onViewDetails,
  });

  final String name;
  final int age;
  final String pairingStatus;
  final String deviceStatus;
  final String? deviceName;
  final String? childEmail;
  final String? lastReportDate;
  final bool isSelected;
  final VoidCallback onViewDetails;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);

  @override
  Widget build(BuildContext context) {
    final isConnected =
        pairingStatus == 'paired' || deviceStatus == 'connected';

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? purple : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: softPurple,
                  child: Icon(
                    Icons.phone_android_rounded,
                    color: isConnected ? Colors.green : purple,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: darkText,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        'Age $age - ${deviceName ?? 'Android Device'}',
                        style: const TextStyle(color: grayText),
                      ),

                      const SizedBox(height: 6),

                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 9,
                            color: isConnected ? Colors.green : Colors.orange,
                          ),

                          const SizedBox(width: 6),

                          Text(
                            isConnected ? 'Connected' : 'Waiting for Pairing',
                            style: TextStyle(
                              color: isConnected ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                IconButton(
                  tooltip: 'View Details',
                  onPressed: onViewDetails,
                  icon: const Icon(Icons.chevron_right_rounded, color: purple),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SmallDetailRow(
                    label: 'Last Sync',
                    value: lastReportDate ?? 'No report yet',
                  ),
                  SmallDetailRow(
                    label: 'Child Account',
                    value: childEmail ?? 'Not linked yet',
                    isLast: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewDetails,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text(
                  'View Details',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SelectedDeviceDetailsCard extends StatelessWidget {
  const SelectedDeviceDetailsCard({
    super.key,
    required this.name,
    required this.age,
    required this.pairingStatus,
    required this.deviceStatus,
    required this.childEmail,
    required this.deviceName,
    required this.lastReportDate,
    required this.onViewLocation,
    required this.onViewRules,
  });

  final String name;
  final int age;
  final String pairingStatus;
  final String deviceStatus;

  final String? childEmail;
  final String? deviceName;
  final String? lastReportDate;

  final VoidCallback onViewLocation;
  final VoidCallback onViewRules;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);

  @override
  Widget build(BuildContext context) {
    final isConnected =
        pairingStatus == 'paired' || deviceStatus == 'connected';

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: softPurple,
                  child: Icon(
                    Icons.phone_android_rounded,
                    color: isConnected ? Colors.green : purple,
                    size: 31,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: darkText,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        'Age $age - ${deviceName ?? 'Android Device'}',
                        style: const TextStyle(color: grayText),
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
                    color: isConnected
                        ? const Color(0xFFE8F7EE)
                        : const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    isConnected ? 'Connected' : 'Waiting',
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  DetailRow(
                    label: 'Pairing Status',
                    value: formatStatus(pairingStatus),
                  ),
                  DetailRow(
                    label: 'Device Status',
                    value: formatStatus(deviceStatus),
                  ),
                  DetailRow(
                    label: 'Child Email',
                    value: childEmail ?? 'Not linked yet',
                  ),
                  DetailRow(
                    label: 'Device Name',
                    value: deviceName ?? 'Not available',
                  ),
                  DetailRow(
                    label: 'Last Synced Report',
                    value: lastReportDate ?? 'No report yet',
                    isLast: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            if (isConnected)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onViewLocation,
                      icon: const Icon(Icons.location_on_outlined),
                      label: const Text('Location'),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onViewRules,
                      icon: const Icon(Icons.rule_rounded),
                      label: const Text('Rules'),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 12),

            Row(
              children: [
                Icon(
                  isConnected
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  color: isConnected ? Colors.green : Colors.orange,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    isConnected
                        ? 'Device connected successfully.'
                        : 'Waiting for the child device to complete pairing.',
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String formatStatus(String value) {
    return value.replaceAll('_', ' ').toUpperCase();
  }
}

class PairingCodeCard extends StatelessWidget {
  const PairingCodeCard({
    super.key,
    required this.code,
    required this.hasCode,
    required this.onCopy,
  });

  final String code;
  final bool hasCode;
  final VoidCallback onCopy;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color grayText = Color(0xFF4B5563);
  static const Color softPurple = Color(0xFFF4F0FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: softPurple,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const Icon(Icons.link_rounded, color: purple, size: 54),

          const SizedBox(height: 12),

          const Text(
            'Pairing Code',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),

          const SizedBox(height: 6),

          const Text(
            'Enter this code on the child phone to connect it to this profile.',
            textAlign: TextAlign.center,
            style: TextStyle(color: grayText, height: 1.35),
          ),

          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 31,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            hasCode
                ? 'This pairing code expires after 30 minutes.'
                : 'Generate a pairing code for this child profile.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: grayText, height: 1.4),
          ),

          if (hasCode) ...[
            const SizedBox(height: 14),

            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text(
                'Copy Pairing Code',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SmallDetailRow extends StatelessWidget {
  const SmallDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceStatusCard extends StatelessWidget {
  const DeviceStatusCard({
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
      elevation: 2,
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
