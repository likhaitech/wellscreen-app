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

  final TextEditingController childNameController = TextEditingController(
    text: 'Child Profile',
  );
  final TextEditingController ageController = TextEditingController(text: '12');

  String? pairingCode;
  String? selectedChildId;
  bool isSaving = false;

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
      showMessage('Please enter child profile details.');
      return;
    }

    if (age == null || age <= 0 || age > 15) {
      showMessage('Please enter a valid child age from 1 to 15.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final code = generateCode();
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(minutes: 30));

      final childRef = selectedChildId == null
          ? FirebaseFirestore.instance.collection('child_profiles').doc()
          : FirebaseFirestore.instance
                .collection('child_profiles')
                .doc(selectedChildId);

      await childRef.set({
        'childId': childRef.id,
        'parentId': user.uid,
        'name': childName,
        'age': age,
        'pairingCode': code,
        'pairingStatus': 'waiting',
        'deviceStatus': 'not_connected',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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

      setState(() {
        pairingCode = code;
        selectedChildId = childRef.id;
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

  Future<void> selectChildProfile(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    if (data == null) {
      return;
    }

    setState(() {
      selectedChildId = doc.id;
      childNameController.text = data['name'] as String? ?? 'Child Profile';
      ageController.text = (data['age'] as int? ?? 12).toString();
      pairingCode = data['pairingCode'] as String?;
    });

    showMessage('Child profile selected.');
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
    final code = pairingCode ?? '------';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Device Pairing',
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
            'Create or Select Child Profile',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Generate a pairing code to connect the monitored Android device to this parent account.',
            style: TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 24),

          TextField(
            controller: childNameController,
            decoration: InputDecoration(
              labelText: 'Child Profile Name',
              prefixIcon: const Icon(Icons.child_care_rounded),
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
              helperText: 'WellScreen prototype supports children up to 15.',
              prefixIcon: const Icon(Icons.cake_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 24),

          PairingCodeCard(
            code: code,
            hasCode: pairingCode != null,
            onCopy: copyPairingCode,
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: isSaving ? null : createPairingCode,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_link_rounded),
              label: Text(
                isSaving ? 'Generating...' : 'Generate Pairing Code',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Paired Child Devices',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This section shows child profiles created by this parent account and their pairing status.',
            style: TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 14),

          if (user == null)
            const DeviceStatusCard(
              icon: Icons.info_outline_rounded,
              iconColor: Colors.orange,
              title: 'No parent account found',
              subtitle: 'Please log in again to view paired child devices.',
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
                    title: 'Loading child profiles',
                    subtitle: 'Preparing paired device information...',
                  );
                }

                if (snapshot.hasError) {
                  return DeviceStatusCard(
                    icon: Icons.error_outline_rounded,
                    iconColor: Colors.red,
                    title: 'Unable to load child profiles',
                    subtitle: snapshot.error.toString(),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const DeviceStatusCard(
                    icon: Icons.child_care_rounded,
                    iconColor: purple,
                    title: 'No child profile yet',
                    subtitle:
                        'Create a child profile and generate a pairing code first.',
                  );
                }

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data();
                    final name = data['name'] as String? ?? 'Child Profile';
                    final age = data['age'] as int? ?? 0;
                    final status =
                        data['pairingStatus'] as String? ?? 'waiting';
                    final deviceStatus =
                        data['deviceStatus'] as String? ?? 'not_connected';
                    final savedCode = data['pairingCode'] as String?;

                    return ChildProfileCard(
                      name: name,
                      age: age,
                      status: status,
                      deviceStatus: deviceStatus,
                      pairingCode: savedCode,
                      isSelected: selectedChildId == doc.id,
                      onTap: () => selectChildProfile(doc),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _DevicePairingScreenState.softPurple,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const Icon(Icons.qr_code_2_rounded, color: purple, size: 84),
          const SizedBox(height: 14),
          const Text(
            'Pairing Code',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 14),
          Text(
            hasCode
                ? 'Status: Waiting for child device to complete pairing. This code expires after 30 minutes.'
                : 'Generate a code before setting up the child device.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
            label: const Text(
              'Copy Code',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class ChildProfileCard extends StatelessWidget {
  const ChildProfileCard({
    super.key,
    required this.name,
    required this.age,
    required this.status,
    required this.deviceStatus,
    required this.pairingCode,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final int age;
  final String status;
  final String deviceStatus;
  final String? pairingCode;
  final bool isSelected;
  final VoidCallback onTap;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    final isPaired = status == 'paired' || deviceStatus == 'connected';

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isSelected ? purple : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(18),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF4F0FF),
          child: Icon(
            isPaired ? Icons.phone_android_rounded : Icons.link_rounded,
            color: isPaired ? Colors.green : purple,
          ),
        ),
        title: Text(
          '$name • Age $age',
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Pairing: ${_formatStatus(status)}\nDevice: ${_formatStatus(deviceStatus)}\nCode: ${pairingCode ?? 'No active code'}',
            style: const TextStyle(color: grayText, height: 1.4),
          ),
        ),
        trailing: Icon(
          isPaired ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: isPaired ? Colors.green : Colors.orange,
        ),
      ),
    );
  }

  String _formatStatus(String value) {
    return value.replaceAll('_', ' ').toUpperCase();
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
