import 'package:flutter/material.dart';

class UsageSummaryScreen extends StatelessWidget {
  const UsageSummaryScreen({super.key});

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Usage Summary',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Text(
            'Daily and Weekly Usage',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Review screen time, app usage, detected patterns, and supported category-related events.',
            style: TextStyle(color: grayText, height: 1.4),
          ),
          SizedBox(height: 24),

          SummaryCard(
            icon: Icons.today_rounded,
            title: 'Today’s Screen Time',
            value: '4 hours 20 minutes',
            description:
                'Current monitored usage for the selected child profile.',
          ),

          SummaryCard(
            icon: Icons.bar_chart_rounded,
            title: 'Weekly Average',
            value: '3 hours 45 minutes',
            description: 'Average screen time across the current week.',
          ),

          SummaryCard(
            icon: Icons.apps_rounded,
            title: 'Top Used Applications',
            value: 'YouTube, TikTok, Mobile Legends',
            description:
                'Apps with the highest usage duration and access frequency.',
          ),

          SummaryCard(
            icon: Icons.nightlight_round,
            title: 'Detected Pattern',
            value: 'Late-night usage detected',
            description:
                'The system flagged usage after the recommended rest period.',
          ),

          SummaryCard(
            icon: Icons.category_rounded,
            title: 'Category Event',
            value: 'Entertainment category reached limit',
            description: 'Category-related event available for parent review.',
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String value;
  final String description;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: Icon(icon, color: purple, size: 34),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$value\n$description',
            style: const TextStyle(color: grayText, height: 1.4),
          ),
        ),
      ),
    );
  }
}
