import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  String selectedPairingStatus = 'waiting';
  String selectedDeviceStatus = 'not_connected';

  bool isSaving = false;
  bool showAddChildForm = false;

  bool get selectedChildIsPaired =>
      selectedPairingStatus == 'paired' ||
      selectedDeviceStatus == 'connected';

  @override
  void dispose() {
    childNameController.dispose();
    ageController.dispose();
    super.dispose();
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
      final code = generateCode();
      final expiresAt = DateTime.now().add(
        const Duration(minutes: 30),
      );

      final isNewChild = selectedChildId == null;

      final childRef = isNewChild
          ? FirebaseFirestore.instance.collection('child_profiles').doc()
          : FirebaseFirestore.instance
                .collection('child_profiles')
                .doc(selectedChildId);

      final childData = <String, dynamic>{
        'childId': childRef.id,
        'parentId': user.uid,
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

      await childRef.set(
        childData,
        SetOptions(merge: true),
      );

      await FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code)
          .set({
            'pairingCode': code,
            'parentId': user.uid,
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

    await Clipboard.setData(
      ClipboardData(text: code),
    );

    showMessage('Pairing code copied.');
  }

  void selectChildProfile(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    if (data == null) {
      return;
    }

    final name = data['name'] as String? ?? 'Child Profile';
    final age = data['age'] as int? ?? 0;

    setState(() {
      selectedChildId = doc.id;
      selectedChildName = name;
      selectedChildAge = age;

      pairingCode = data['pairingCode'] as String?;

      selectedPairingStatus =
          data['pairingStatus'] as String? ?? 'waiting';

      selectedDeviceStatus =
          data['deviceStatus'] as String? ?? 'not_connected';

      childNameController.text = name;
      ageController.text = age.toString();

      showAddChildForm = false;
    });
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Device Pairing',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Child Devices',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Manage child profiles and connect Android devices to your WellScreen account.',
            style: TextStyle(
              color: grayText,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          if (user == null)
            const DeviceStatusCard(
              icon: Icons.info_outline_rounded,
              iconColor: Colors.orange,
              title: 'No parent account found',
              subtitle:
                  'Please log in again before managing child devices.',
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('child_profiles')
                  .where(
                    'parentId',
                    isEqualTo: user.uid,
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const DeviceStatusCard(
                    icon: Icons.hourglass_top_rounded,
                    iconColor: purple,
                    title: 'Loading child devices',
                    subtitle:
                        'Preparing child profile and device information...',
                  );
                }

                if (snapshot.hasError) {
                  return DeviceStatusCard(
                    icon: Icons.error_outline_rounded,
                    iconColor: Colors.red,
                    title: 'Unable to load child devices',
                    subtitle: snapshot.error.toString(),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const DeviceStatusCard(
                    icon: Icons.phone_android_rounded,
                    iconColor: purple,
                    title: 'No child devices yet',
                    subtitle:
                        'Add a child device to generate a pairing code.',
                  );
                }

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data();

                    final name =
                        data['name'] as String? ?? 'Child Profile';

                    final age = data['age'] as int? ?? 0;

                    final pairingStatus =
                        data['pairingStatus'] as String? ??
                        'waiting';

                    final deviceStatus =
                        data['deviceStatus'] as String? ??
                        'not_connected';

                    return ChildDeviceCard(
                      name: name,
                      age: age,
                      pairingStatus: pairingStatus,
                      deviceStatus: deviceStatus,
                      isSelected:
                          selectedChildId == doc.id,
                      onViewDetails: () {
                        selectChildProfile(doc);
                      },
                    );
                  }).toList(),
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
              icon: const Icon(
                Icons.add_rounded,
              ),
              label: const Text(
                'Add Child Device',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
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
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Child Device',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: darkText,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Create a child profile first. WellScreen will generate a 6-digit pairing code for the child device.',
                    style: TextStyle(
                      color: grayText,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: childNameController,
                    decoration: InputDecoration(
                      labelText: 'Child Profile Name',
                      prefixIcon: const Icon(
                        Icons.child_care_rounded,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: ageController,
                    keyboardType:
                        TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Age',
                      helperText:
                          'WellScreen currently supports ages 1 to 15.',
                      prefixIcon: const Icon(
                        Icons.cake_rounded,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed:
                          isSaving
                              ? null
                              : createPairingCode,
                      style: FilledButton.styleFrom(
                        backgroundColor: purple,
                      ),
                      icon: const Icon(
                        Icons.link_rounded,
                      ),
                      label: Text(
                        isSaving
                            ? 'Generating...'
                            : 'Generate Pairing Code',
                        style: const TextStyle(
                          fontWeight:
                              FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed:
                          isSaving
                              ? null
                              : cancelAddChildForm,
                      child: const Text(
                        'Cancel',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (selectedChildId != null &&
              !showAddChildForm) ...[
            const SizedBox(height: 30),

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
              name:
                  selectedChildName ??
                  'Child Profile',
              age: selectedChildAge ?? 0,
              pairingStatus:
                  selectedPairingStatus,
              deviceStatus:
                  selectedDeviceStatus,
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
                  onPressed:
                      isSaving
                          ? null
                          : createPairingCode,
                  icon: const Icon(
                    Icons.refresh_rounded,
                  ),
                  label: Text(
                    pairingCode == null
                        ? 'Generate Pairing Code'
                        : 'Generate New Pairing Code',
                    style: const TextStyle(
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
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
    required this.isSelected,
    required this.onViewDetails,
  });

  final String name;
  final int age;
  final String pairingStatus;
  final String deviceStatus;
  final bool isSelected;
  final VoidCallback onViewDetails;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    final isConnected =
        pairingStatus == 'paired' ||
        deviceStatus == 'connected';

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(18),
        side: BorderSide(
          color:
              isSelected
                  ? purple
                  : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor:
                  const Color(0xFFF4F0FF),
              child: Icon(
                Icons.phone_android_rounded,
                color:
                    isConnected
                        ? Colors.green
                        : purple,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: darkText,
                      fontWeight:
                          FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    'Age $age',
                    style: const TextStyle(
                      color: grayText,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color:
                            isConnected
                                ? Colors.green
                                : Colors.orange,
                      ),

                      const SizedBox(width: 6),

                      Text(
                        isConnected
                            ? 'Connected'
                            : 'Waiting for Pairing',
                        style: TextStyle(
                          color:
                              isConnected
                                  ? Colors.green
                                  : Colors.orange,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            TextButton(
              onPressed: onViewDetails,
              child: const Text(
                'View Details',
                style: TextStyle(
                  color: purple,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SelectedDeviceDetailsCard
    extends StatelessWidget {
  const SelectedDeviceDetailsCard({
    super.key,
    required this.name,
    required this.age,
    required this.pairingStatus,
    required this.deviceStatus,
  });

  final String name;
  final int age;
  final String pairingStatus;
  final String deviceStatus;

  static const Color darkText =
      Color(0xFF111827);
  static const Color grayText =
      Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    final isConnected =
        pairingStatus == 'paired' ||
        deviceStatus == 'connected';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              color: darkText,
              fontWeight:
                  FontWeight.w900,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Age: $age',
            style: const TextStyle(
              color: grayText,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Pairing Status: ${formatStatus(pairingStatus)}',
            style: const TextStyle(
              color: grayText,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Device Status: ${formatStatus(deviceStatus)}',
            style: const TextStyle(
              color: grayText,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Icon(
                isConnected
                    ? Icons.check_circle_rounded
                    : Icons.schedule_rounded,
                color:
                    isConnected
                        ? Colors.green
                        : Colors.orange,
              ),

              const SizedBox(width: 8),

              Text(
                isConnected
                    ? 'Device connected successfully'
                    : 'Waiting for child device',
                style: TextStyle(
                  color:
                      isConnected
                          ? Colors.green
                          : Colors.orange,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String formatStatus(String value) {
    return value
        .replaceAll('_', ' ')
        .toUpperCase();
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

  static const Color purple =
      Color(0xFF5B2BBF);
  static const Color grayText =
      Color(0xFF4B5563);
  static const Color softPurple =
      Color(0xFFF4F0FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: softPurple,
        borderRadius:
            BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.link_rounded,
            color: purple,
            size: 60,
          ),

          const SizedBox(height: 12),

          const Text(
            'Pairing Code',
            style: TextStyle(
              fontWeight:
                  FontWeight.w900,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 10),

          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(
                  vertical: 18,
                ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(14),
              border: Border.all(
                color: Colors.black12,
              ),
            ),
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 31,
                fontWeight:
                    FontWeight.w900,
                letterSpacing: 8,
              ),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            hasCode
                ? 'Enter this code on the child device. The code expires after 30 minutes.'
                : 'Generate a pairing code for this child profile.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: grayText,
              height: 1.4,
            ),
          ),

          if (hasCode) ...[
            const SizedBox(height: 14),

            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(
                Icons.copy_rounded,
              ),
              label: const Text(
                'Copy Code',
                style: TextStyle(
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ),
          ],
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

  static const Color darkText =
      Color(0xFF111827);
  static const Color grayText =
      Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin:
          const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.all(18),
        leading: Icon(
          icon,
          color: iconColor,
          size: 34,
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: darkText,
            fontWeight:
                FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding:
              const EdgeInsets.only(top: 6),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: grayText,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}