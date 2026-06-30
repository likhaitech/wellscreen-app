import 'dart:math';

import 'package:flutter/material.dart';

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  late String _pairingCode;

  @override
  void initState() {
    super.initState();
    _pairingCode = _generatePairingCode();
  }

  String _generatePairingCode() {
    final random = Random();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  void _generateNewCode() {
    setState(() {
      _pairingCode = _generatePairingCode();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New pairing code generated.'),
      ),
    );
  }

  void _useQrCode() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR code pairing will be connected later.'),
      ),
    );
  }

  void _finishPairing() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Device pairing page is ready.'),
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF5B2BBF);
    const darkText = Color(0xFF111827);

    final codeDigits = _pairingCode.split('');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              color: purple,
              child: const Row(
                children: [
                  Icon(
                    Icons.health_and_safety_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'WellScreen',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Connect to Child',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: darkText,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter this 6 digit code to\nyour child device.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF4B5563),
                            fontSize: 17,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: codeDigits.map((digit) {
                            return Container(
                              width: 48,
                              height: 48,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFF111827),
                                  width: 1.2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                digit,
                                style: const TextStyle(
                                  color: darkText,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _generateNewCode,
                          child: const Text(
                            'Generate new code in 00:44',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _useQrCode,
                          child: const Text(
                            'Use QR Code',
                            style: TextStyle(
                              color: purple,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: _finishPairing,
                            style: FilledButton.styleFrom(
                              backgroundColor: purple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          height: 190,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1ECFF),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.phonelink_lock_rounded,
                                color: purple,
                                size: 72,
                              ),
                              SizedBox(height: 14),
                              Text(
                                'Secure child-device pairing',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: darkText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Use the code or QR option to connect\nthe child device safely.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}