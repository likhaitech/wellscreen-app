import 'package:flutter/material.dart';

import 'device_pairing_screen.dart';

class ParentDashboardScreen extends StatelessWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF5B2BBF);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome, Parent',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage child devices, review usage reports, and set healthy screen-time rules.',
              style: TextStyle(
                color: Color(0xFF4B5563),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            Card(
              elevation: 3,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.devices_rounded,
                      color: purple,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Child Devices',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pair a child device using a 6-digit code or QR option.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF4B5563),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DevicePairingScreen(),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: purple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.add_link_rounded),
                        label: const Text(
                          'Add Child Device',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}