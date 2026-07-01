import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RuleSettingsScreen extends StatefulWidget {
  const RuleSettingsScreen({super.key});

  @override
  State<RuleSettingsScreen> createState() => _RuleSettingsScreenState();
}

class _RuleSettingsScreenState extends State<RuleSettingsScreen> {
  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  final limitController = TextEditingController(text: '120');

  bool appBlocking = true;
  bool focusMode = true;
  bool cooldownTimer = true;
  bool scheduledLock = false;
  bool categoryRestriction = true;
  bool emergencyAccess = true;

  bool isSaving = false;

  @override
  void dispose() {
    limitController.dispose();
    super.dispose();
  }

  Future<void> saveRules() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    setState(() => isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('restriction_settings').add({
        'parentId': user.uid,
        'limitMinutes': int.tryParse(limitController.text.trim()) ?? 120,
        'appBlocking': appBlocking,
        'focusMode': focusMode,
        'cooldownTimer': cooldownTimer,
        'scheduledLock': scheduledLock,
        'categoryRestriction': categoryRestriction,
        'emergencyAccess': emergencyAccess,
        'createdAt': FieldValue.serverTimestamp(),
      });

      showMessage('Rules saved and applied successfully.');
    } catch (e) {
      showMessage('Rule saving error: $e');
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Rule Settings',
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
            'Configure Restrictions',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Set app limits, focus mode, cooldown timers, scheduled locks, harmful category restrictions, and emergency access.',
            style: TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 24),

          TextField(
            controller: limitController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Daily Usage Limit in Minutes',
              prefixIcon: const Icon(Icons.timer_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),

          const SizedBox(height: 16),

          RuleSwitch(
            title: 'App Blocking',
            subtitle: 'Block selected apps after limits are reached.',
            value: appBlocking,
            onChanged: (value) => setState(() => appBlocking = value),
          ),

          RuleSwitch(
            title: 'Focus Mode',
            subtitle: 'Limit distracting apps during study or rest time.',
            value: focusMode,
            onChanged: (value) => setState(() => focusMode = value),
          ),

          RuleSwitch(
            title: 'Cooldown Timer',
            subtitle: 'Add a break after long continuous usage.',
            value: cooldownTimer,
            onChanged: (value) => setState(() => cooldownTimer = value),
          ),

          RuleSwitch(
            title: 'Scheduled Lock Session',
            subtitle: 'Apply restrictions during selected schedules.',
            value: scheduledLock,
            onChanged: (value) => setState(() => scheduledLock = value),
          ),

          RuleSwitch(
            title: 'Harmful Category Restriction',
            subtitle: 'Restrict supported harmful website or category events.',
            value: categoryRestriction,
            onChanged: (value) => setState(() => categoryRestriction = value),
          ),

          RuleSwitch(
            title: 'Emergency Access',
            subtitle: 'Allow selected essential functions during restrictions.',
            value: emergencyAccess,
            onChanged: (value) => setState(() => emergencyAccess = value),
          ),

          const SizedBox(height: 22),

          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: isSaving ? null : saveRules,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.save_rounded),
              label: Text(
                isSaving ? 'Saving...' : 'Save and Apply Rules',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RuleSwitch extends StatelessWidget {
  const RuleSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SwitchListTile(
        activeThumbColor: purple,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: grayText, height: 1.35),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
