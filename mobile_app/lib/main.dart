import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const WellScreenApp());
}

class WellScreenApp extends StatelessWidget {
  const WellScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WellScreen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}