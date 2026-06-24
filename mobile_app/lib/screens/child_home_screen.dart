import 'package:flutter/material.dart';

class ChildHomeScreen extends StatelessWidget {
  const ChildHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Child Home')),
      body: const Center(
        child: Text('Screen goals, reminders, and focus mode will appear here.'),
      ),
    );
  }
}