import 'dart:convert';

import 'package:flutter/material.dart';

/// Renders the icon retrieved from the CHILD's actual installed package.
/// No hardcoded social-media/game icon mapping is necessary.
class AppUsageIcon extends StatelessWidget {
  const AppUsageIcon({
    super.key,
    required this.encoded,
    this.fallback = Icons.apps_rounded,
    this.fallbackColor = const Color(0xFF4876B8),
    this.size = 48,
  });

  final String? encoded;
  final IconData fallback;
  final Color fallbackColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final encodedIcon = encoded;
    Widget child = Icon(fallback, color: Colors.white, size: size * 0.58);
    if (encodedIcon != null && encodedIcon.isNotEmpty) {
      try {
        final bytes = base64Decode(encodedIcon);
        child = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            fallback,
            color: Colors.white,
            size: size * 0.58,
          ),
        );
      } on FormatException {
        // Old reports or malformed icon data: show a neutral fallback.
      }
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fallbackColor,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Center(child: child),
    );
  }
}
