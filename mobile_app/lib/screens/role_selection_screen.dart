import 'package:flutter/material.dart';
import 'child_home_screen.dart';
import 'parent_dashboard_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Role')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            RoleCard(
              title: 'Parent / Guardian',
              description: 'View usage reports, set limits, and receive alerts.',
              icon: Icons.family_restroom,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ParentDashboardScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            RoleCard(
              title: 'Child',
              description: 'View screen goals, reminders, and focus status.',
              icon: Icons.child_care,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        minVerticalPadding: 20,
        leading: Icon(icon, size: 36, color: const Color(0xFF2563EB)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }
}