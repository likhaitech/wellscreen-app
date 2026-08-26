/// WellScreen's single source of visual truth.
///
/// WHY THIS EXISTS: before this file, every screen redeclared its own copy
/// of the same ~10 color constants (purple/darkText/grayText/etc.) as local
/// `static const` fields - drift was inevitable (rules_screen.dart had
/// already drifted onto a different background and different
/// blue/red than every other screen). One shared file means changing the
/// brand color, a card radius, or a spacing value happens once, not once
/// per screen, and it's what makes the "seamless, consistent" redesign
/// requested actually possible instead of aspirational.
///
/// Re-themed from the original brand purple (#5B2BBF) to a blue/teal
/// "Trust Blue" palette after a research pass on parental-control apps
/// specifically: blue is the color most consistently associated with
/// trust, calm, and safety across UX color-psychology research, and it's
/// what competitors in this exact category (Google Family Link
/// especially) lean on for that reason - purple reads more as
/// premium/creative, which fits a design tool better than a safety tool a
/// parent needs to feel confident in. Every value below changed together
/// so nothing drifts out of coordination; screens should still only ever
/// reference AppColors, never a new literal Color(0x...).
library;

import 'package:flutter/material.dart';

/// The full color palette. Semantic names (success/warning/danger/info),
/// not just raw brand colors - previously every screen invented its own
/// ad hoc green/orange/red for "healthy/moderate/high risk" style states,
/// which is exactly the kind of thing that drifts. Use these, not a new
/// literal Color(0x...) in a screen file.
class AppColors {
  AppColors._();

  // Brand - "Trust Blue": a confident mid-blue primary (the color most
  // associated with trust/calm/safety in UX research, and the dominant
  // choice among parental-control competitors) plus a teal-green accent
  // that echoes the existing `success` semantic color, so brand and status
  // reinforce each other instead of competing.
  static const Color primary = Color(0xFF2557A7);
  static const Color primaryDark = Color(0xFF17396E);
  static const Color primaryLight = Color(0xFFE6EDF8);
  static const Color accent = Color(0xFF14A38A); // teal-green - used sparingly for AI/ML-specific accents, so "AI-detected" content reads as visually distinct from a plain alert

  // Neutrals
  static const Color background = Color(0xFFF5F7FB);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE3E8F1);
  static const Color textPrimary = Color(0xFF14202E);
  static const Color textSecondary = Color(0xFF5B6B7F);
  static const Color textDisabled = Color(0xFFAAB4C2);

  // Semantic - consistent across every screen; a "High Risk" label means
  // the same red everywhere, not a different red per screen. Unchanged by
  // the re-theme - these were already coordinated with the new primary
  // (info in particular was already almost this exact blue).
  static const Color success = Color(0xFF1E9E6B);
  static const Color successBg = Color(0xFFE3F6EE);
  static const Color warning = Color(0xFFC77A00);
  static const Color warningBg = Color(0xFFFCF0DC);
  static const Color danger = Color(0xFFD1394A);
  static const Color dangerBg = Color(0xFFFBE7E9);
  static const Color info = Color(0xFF2557A7);
  static const Color infoBg = Color(0xFFE4EEF9);

  // Detection-source tags (SiteCategoryService's three mechanisms) - one
  // fixed color per source everywhere it's shown, instead of the ad hoc
  // string suffixes ("(AI-detected)"/"(keyword match)") previously used
  // with no visual distinction at all.
  static const Color sourceLookup = primary;
  static const Color sourceKeyword = warning;
  static const Color sourceMl = accent;
}

/// Spacing scale - use multiples of this instead of literal EdgeInsets
/// numbers, so padding/gaps are consistent instead of "whatever felt
/// right in this one screen" (previous screens mixed 12/14/18/20/22/24
/// with no evident system).
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 40;
}

class AppRadius {
  AppRadius._();
  static const double card = 20;
  static const double button = 16;
  static const double pill = 999;
  static const double sheet = 28;
}

/// The MaterialApp-level theme. Wire this into main.dart's
/// `MaterialApp(theme: AppTheme.light())` instead of the inline ThemeData
/// that was there before.
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: AppColors.textPrimary,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          height: 1.45,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

/// One card shape, used everywhere - replaces the two competing styles
/// found across the app (a custom 26px `_whiteCard()` helper vs. Material
/// `Card` at elevation 2 / radius 18, used inconsistently screen to
/// screen). Every redesigned screen should build sections with this, not
/// a hand-rolled Container.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: card,
    );
  }
}

/// A small colored pill, used for status/severity/source labels
/// ("High Risk", "gambling", "(AI-detected)") - one consistent visual
/// treatment instead of ad hoc Text-with-color scattered through screens.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// A standard section header used at the top of every AppCard - icon,
/// title, optional trailing widget. Kills the copy-pasted Row(Icon +
/// SizedBox + Expanded(Text(...))) block that was hand-rewritten (with
/// small inconsistencies) in nearly every card across the app.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    );
  }
}

/// A single empty/placeholder state - replaces the many hand-written
/// "No X synced yet" AlertReportCard-style widgets that each screen
/// re-implemented slightly differently.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: icon,
            iconColor: AppColors.textDisabled,
            title: title,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
