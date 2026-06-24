import 'package:flutter/material.dart';

class ParentDashboardScreen extends StatelessWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parent Dashboard')),
      body: const Center(
        child: Text('Usage summary, alerts, and controls will appear here.'),
      ),
    );
  }
}