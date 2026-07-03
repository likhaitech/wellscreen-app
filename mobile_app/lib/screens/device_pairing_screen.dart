import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'login_screen.dart';

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color pageBg = Color(0xFFF3F4F6);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softOrange = Color(0xFFFFF4E5);

  final childNameController = TextEditingController();

  bool isGenerating = false;
  String generatedCode = '';
  String generatedChildName = '';
  DateTime? generatedExpiry;

  @override
  void dispose() {
    childNameController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> childProfilesStream(String uid) {
    return FirebaseFirestore.instance
        .collection('child_profiles')
        .where('parentId', isEqualTo: uid)
        .snapshots();
  }

  Future<String> createUniquePairingCode() async {
    final firestore = FirebaseFirestore.instance;
    final random = Random();

    for (int attempt = 0; attempt < 10; attempt++) {
      final code = (100000 + random.nextInt(900000)).toString();
      final doc = await firestore.collection('pairing_codes').doc(code).get();

      if (!doc.exists) {
        return code;
      }
    }

    throw Exception('Unable to generate unique pairing code. Try again.');
  }

  Future<void> generatePairingCode() async {
    final parentUser = FirebaseAuth.instance.currentUser;

    if (parentUser == null) {
      showMessage('Please log in again.');
      return;
    }

    final childName = childNameController.text.trim();

    if (childName.isEmpty) {
      showMessage('Enter the child name first.');
      return;
    }

    setState(() => isGenerating = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final code = await createUniquePairingCode();
      final expiryDate = DateTime.now().add(const Duration(minutes: 15));

      final childProfileRef = firestore.collection('child_profiles').doc();
      final pairingCodeRef = firestore.collection('pairing_codes').doc(code);

      final batch = firestore.batch();

      batch.set(childProfileRef, {
        'id': childProfileRef.id,
        'parentId': parentUser.uid,
        'name': childName,
        'pairingStatus': 'waiting',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(pairingCodeRef, {
        'code': code,
        'parentId': parentUser.uid,
        'childId': childProfileRef.id,
        'childName': childName,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiryDate),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;

      setState(() {
        generatedCode = code;
        generatedChildName = childName;
        generatedExpiry = expiryDate;
      });

      childNameController.clear();
      showMessage('Pairing code generated.');
    } catch (e) {
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isGenerating = false);
      }
    }
  }

  bool isConnected(Map<String, dynamic> data) {
    final pairingStatus = (data['pairingStatus'] ?? '').toString();
    final childEmail = (data['childEmail'] ?? '').toString();
    final childAccountId = (data['childAccountId'] ?? '').toString();

    return pairingStatus == 'connected' ||
        childEmail.isNotEmpty ||
        childAccountId.isNotEmpty;
  }

  String formatDate(DateTime? date) {
    if (date == null) return 'Not available';

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$month/$day/$year $hour:$minute';
  }

  String formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      return formatDate(value.toDate());
    }

    return 'Not available';
  }

  void copyCode() {
    if (generatedCode.isEmpty) return;

    Clipboard.setData(ClipboardData(text: generatedCode));
    showMessage('Pairing code copied.');
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  @override
  Widget build(BuildContext context) {
    final parentUser = FirebaseAuth.instance.currentUser;

    if (parentUser == null) {
      return Scaffold(
        backgroundColor: pageBg,
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
      appBar: AppBar(
        title: const Text(
          'Device Pairing',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: pageBg,
        foregroundColor: darkText,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: childProfilesStream(parentUser.uid),
        builder: (context, snapshot) {
          final childDocs = snapshot.data?.docs ?? [];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              _headerCard(),
              const SizedBox(height: 18),
              _generateCodeCard(),
              if (generatedCode.isNotEmpty) const SizedBox(height: 18),
              if (generatedCode.isNotEmpty) _generatedCodeCard(),
              const SizedBox(height: 22),
              _childrenSection(childDocs),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [purple, deepPurple],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(26),
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
              'Pair Student Device',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Icon(Icons.link_rounded, color: Colors.white, size: 34),
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
        ),
      ),
    );
  }

  Widget _generateCodeCard() {
    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Pairing Code',
            style: TextStyle(
              color: darkText,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the student name and generate a 6-digit code. The student will enter this code on their device.',
            style: TextStyle(
              color: grayText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: childNameController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Student Name',
              prefixIcon: const Icon(Icons.child_care_rounded, color: purple),
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
              onPressed: isGenerating ? null : generatePairingCode,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: Text(
                isGenerating ? 'Generating...' : 'Generate Pairing Code',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _generatedCodeCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: softPurple,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x225B2BBF)),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white,
            child: Icon(Icons.verified_rounded, color: teal, size: 46),
          ),
          const SizedBox(height: 14),
          const Text(
            'Pairing Code Ready',
            style: TextStyle(
              color: darkText,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            generatedChildName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: grayText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              generatedCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: purple,
                fontSize: 38,
                letterSpacing: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Expires: ${formatDate(generatedExpiry)}',
            style: const TextStyle(
              color: grayText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: copyCode,
              style: OutlinedButton.styleFrom(
                foregroundColor: purple,
                side: const BorderSide(color: purple, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.copy_rounded),
              label: const Text(
                'Copy Code',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _childrenSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> childDocs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Child Devices',
          style: TextStyle(
            color: darkText,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        if (childDocs.isEmpty)
          _emptyChildrenCard()
        else
          ...childDocs.map((doc) => _childDeviceCard(doc.data())),
      ],
    );
  }

  Widget _emptyChildrenCard() {
    return _whiteCard(
      child: const Column(
        children: [
          Icon(Icons.phone_android_rounded, color: purple, size: 58),
          SizedBox(height: 12),
          Text(
            'No child device yet',
            style: TextStyle(
              color: darkText,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Generate a pairing code to connect a student account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: grayText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _childDeviceCard(Map<String, dynamic> data) {
    final name = (data['name'] ?? 'Student Device').toString();
    final email = (data['childEmail'] ?? 'Not connected yet').toString();
    final connected = isConnected(data);
    final connectedAt = formatTimestamp(data['connectedAt']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 29,
            backgroundColor: connected ? softGreen : softOrange,
            child: Icon(
              connected ? Icons.phone_android_rounded : Icons.link_off_rounded,
              color: connected ? teal : Colors.orange,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name’s Phone',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  connected ? email : 'Waiting for student pairing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: grayText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  connected ? 'Connected: $connectedAt' : 'Status: Waiting',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grayText, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: connected ? softGreen : softOrange,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              connected ? 'Online' : 'Waiting',
              style: TextStyle(
                color: connected ? teal : Colors.orange,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
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
