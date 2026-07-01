import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  final childNameController = TextEditingController(text: 'Child Profile');
  final ageController = TextEditingController(text: '12');

  String? pairingCode;
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

    if (childName.isEmpty || ageText.isEmpty) {
      showMessage('Please enter child profile details.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final code = generateCode();

      final childRef = FirebaseFirestore.instance
          .collection('child_profiles')
          .doc();

      await childRef.set({
        'childId': childRef.id,
        'parentId': user.uid,
        'name': childName,
        'age': int.tryParse(ageText) ?? 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code)
          .set({
            'pairingCode': code,
            'parentId': user.uid,
            'childId': childRef.id,
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(
              DateTime.now().add(const Duration(minutes: 30)),
            ),
          });

      setState(() => pairingCode = code);

      showMessage('Pairing code generated successfully.');
    } catch (e) {
      showMessage('Pairing error: $e');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
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
            'Generate a pairing code or QR option to connect the monitored Android device to this parent account.',
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
              prefixIcon: const Icon(Icons.cake_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F0FF),
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
                  pairingCode == null
                      ? 'Generate a code before setting up the child device.'
                      : 'Status: Waiting for child device to complete pairing.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: grayText, height: 1.4),
                ),
              ],
            ),
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
        ],
      ),
    );
  }
}
