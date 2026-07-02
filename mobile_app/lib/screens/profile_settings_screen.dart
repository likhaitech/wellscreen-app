import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color deepPurple = Color(0xFF3F1E8A);
  static const Color teal = Color(0xFF57C49B);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);
  static const Color pageBg = Color(0xFFF3F4F6);
  static const Color softPurple = Color(0xFFF4F0FF);
  static const Color softGreen = Color(0xFFEAFBF0);
  static const Color softOrange = Color(0xFFFFF4E5);
  static const Color softRed = Color(0xFFFFEFEF);
  static const Color softBlue = Color(0xFFEFF6FF);

  final fullNameController = TextEditingController();
  final profilePhotoUrlController = TextEditingController();
  final phoneNumberController = TextEditingController();
  final extraDetailController = TextEditingController();

  bool isSaving = false;

  @override
  void dispose() {
    fullNameController.dispose();
    profilePhotoUrlController.dispose();
    phoneNumberController.dispose();
    extraDetailController.dispose();
    super.dispose();
  }

  Future<void> saveProfileDetails(String role) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final fullName = fullNameController.text.trim();
    final photoUrl = profilePhotoUrlController.text.trim();
    final phoneNumber = phoneNumberController.text.trim();
    final extraDetail = extraDetailController.text.trim();

    if (fullName.isEmpty) {
      showMessage('Full name is required.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);

      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        final oldData = snapshot.data() ?? <String, dynamic>{};

        transaction.set(userRef, {
          ...oldData,
          'uid': user.uid,
          'email': user.email,
          'fullName': fullName,
          'profilePhotoUrl': photoUrl,
          'phoneNumber': phoneNumber,
          if (role == 'child') 'gradeSection': extraDetail,
          if (role != 'child') 'relationship': extraDetail,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      await user.updateDisplayName(fullName);
      await user.updatePhotoURL(photoUrl.isEmpty ? null : photoUrl);

      if (!mounted) return;

      Navigator.pop(context);
      showMessage('Profile details updated successfully.');
    } catch (e) {
      showMessage('Failed to update profile: $e');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
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

  void showEditProfileSheet(Map<String, dynamic> data, String role) {
    fullNameController.text =
        (data['fullName'] ??
                FirebaseAuth.instance.currentUser?.displayName ??
                '')
            .toString();

    profilePhotoUrlController.text =
        (data['profilePhotoUrl'] ??
                FirebaseAuth.instance.currentUser?.photoURL ??
                '')
            .toString();

    phoneNumberController.text = (data['phoneNumber'] ?? '').toString();

    extraDetailController.text = role == 'child'
        ? (data['gradeSection'] ?? '').toString()
        : (data['relationship'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Edit Profile',
                    style: TextStyle(
                      color: darkText,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Update your account details. Changes are saved to Firestore using a transaction.',
                    style: TextStyle(
                      color: grayText,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _textField(
                    controller: fullNameController,
                    label: 'Full Name',
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: profilePhotoUrlController,
                    label: 'Profile Photo URL',
                    icon: Icons.image_rounded,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: phoneNumberController,
                    label: 'Phone Number',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: extraDetailController,
                    label: role == 'child'
                        ? 'Grade / Section'
                        : 'Relationship to Child',
                    icon: role == 'child'
                        ? Icons.school_rounded
                        : Icons.family_restroom_rounded,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isSaving
                          ? null
                          : () => saveProfileDetails(role),
                      style: FilledButton.styleFrom(
                        backgroundColor: purple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.save_rounded),
                      label: Text(
                        isSaving ? 'Saving...' : 'Save Profile',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: purple),
        filled: true,
        fillColor: pageBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: purple, width: 2),
        ),
      ),
    );
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

    if (user == null) {
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
          'Profile Settings',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: pageBg,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? <String, dynamic>{};

          final fullName =
              (data['fullName'] ?? user.displayName ?? 'WellScreen User')
                  .toString();

          final email = (data['email'] ?? user.email ?? '').toString();

          final role = (data['role'] ?? 'user').toString();

          final photoUrl = (data['profilePhotoUrl'] ?? user.photoURL ?? '')
              .toString();

          final phoneNumber = (data['phoneNumber'] ?? 'Not added').toString();

          final extraDetail = role == 'child'
              ? (data['gradeSection'] ?? 'Not added').toString()
              : (data['relationship'] ?? 'Not added').toString();

          final roleLabel = role == 'parent'
              ? 'Parent / Guardian'
              : role == 'child'
              ? 'Student Account'
              : 'User Account';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _profileHeader(
                fullName: fullName,
                email: email,
                roleLabel: roleLabel,
                role: role,
                photoUrl: photoUrl,
                onEdit: () => showEditProfileSheet(data, role),
              ),
              const SizedBox(height: 20),
              _settingsSection(
                title: 'Account Details',
                children: [
                  _settingsTile(
                    icon: Icons.edit_rounded,
                    iconColor: purple,
                    backgroundColor: softPurple,
                    title: 'Edit Profile',
                    subtitle:
                        'Change name, photo URL, phone number, and details.',
                    onTap: () => showEditProfileSheet(data, role),
                  ),
                  _settingsTile(
                    icon: Icons.photo_camera_rounded,
                    iconColor: teal,
                    backgroundColor: softGreen,
                    title: 'Change Profile Picture',
                    subtitle: photoUrl.isEmpty
                        ? 'No profile photo added yet.'
                        : 'Profile photo URL is saved.',
                    onTap: () => showEditProfileSheet(data, role),
                  ),
                  _settingsTile(
                    icon: Icons.phone_rounded,
                    iconColor: Colors.orange,
                    backgroundColor: softOrange,
                    title: 'Phone Number',
                    subtitle: phoneNumber,
                    onTap: () => showEditProfileSheet(data, role),
                  ),
                  _settingsTile(
                    icon: role == 'child'
                        ? Icons.school_rounded
                        : Icons.family_restroom_rounded,
                    iconColor: purple,
                    backgroundColor: softBlue,
                    title: role == 'child'
                        ? 'Grade / Section'
                        : 'Relationship to Child',
                    subtitle: extraDetail,
                    onTap: () => showEditProfileSheet(data, role),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _settingsSection(
                title: 'Privacy and System',
                children: [
                  _settingsTile(
                    icon: Icons.privacy_tip_rounded,
                    iconColor: teal,
                    backgroundColor: softGreen,
                    title: 'Privacy Boundary',
                    subtitle:
                        'WellScreen does not read messages, passwords, calls, photos, or sensitive files.',
                    onTap: () {},
                  ),
                  _settingsTile(
                    icon: Icons.logout_rounded,
                    iconColor: Colors.redAccent,
                    backgroundColor: softRed,
                    title: 'Logout',
                    subtitle: 'Sign out from this WellScreen account.',
                    onTap: logout,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _profileHeader({
    required String fullName,
    required String email,
    required String roleLabel,
    required String role,
    required String photoUrl,
    required VoidCallback onEdit,
  }) {
    final isChild = role == 'child';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isChild
              ? const [purple, deepPurple]
              : const [purple, deepPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x225B2BBF),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              _profileImage(photoUrl, isChild),
              Positioned(
                right: 0,
                bottom: 2,
                child: InkWell(
                  onTap: onEdit,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: teal,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE9DDFF),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              roleLabel,
              style: const TextStyle(
                color: purple,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileImage(String photoUrl, bool isChild) {
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 48,
        backgroundColor: Colors.white,
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                isChild
                    ? Icons.child_care_rounded
                    : Icons.family_restroom_rounded,
                color: purple,
                size: 54,
              );
            },
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 48,
      backgroundColor: Colors.white,
      child: Icon(
        isChild ? Icons.child_care_rounded : Icons.family_restroom_rounded,
        color: purple,
        size: 54,
      ),
    );
  }

  Widget _settingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: darkText,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: backgroundColor,
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: grayText,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
