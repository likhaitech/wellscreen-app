import 'package:flutter/material.dart';

class AlertsReportsScreen extends StatelessWidget {
  const AlertsReportsScreen({super.key});

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Alerts and Reports',
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
            'System Outputs',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Review alerts, reports, recommendations, location updates, and delayed synchronization events.',
            style: TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.date_range_rounded),
                  label: const Text('Date Filter'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report export prepared for prototype.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Export'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          const AlertReportCard(
            icon: Icons.warning_amber_rounded,
            iconColor: Colors.orange,
            title: 'Exceeded Usage Limit',
            subtitle:
                'The monitored device reached the configured entertainment app limit.',
          ),

          const AlertReportCard(
            icon: Icons.nightlight_round,
            iconColor: Colors.indigo,
            title: 'Late-Night Usage',
            subtitle:
                'Screen activity was detected during the configured rest period.',
          ),

          const AlertReportCard(
            icon: Icons.category_rounded,
            iconColor: purple,
            title: 'Category Indicator',
            subtitle:
                'Supported harmful or restricted category event was flagged for review.',
          ),

          const AlertReportCard(
            icon: Icons.location_on_rounded,
            iconColor: Colors.green,
            title: 'Location Update',
            subtitle:
                'Latest location-related update is available when permission is enabled.',
          ),

          const AlertReportCard(
            icon: Icons.sync_problem_rounded,
            iconColor: Colors.redAccent,
            title: 'Delayed Synchronization',
            subtitle:
                'The child device stored logs locally and will sync when internet is available.',
          ),

          const AlertReportCard(
            icon: Icons.lightbulb_rounded,
            iconColor: purple,
            title: 'Recommendation',
            subtitle:
                'Consider adding a cooldown timer after long continuous sessions.',
          ),
        ],
      ),
    );
  }
}

class AlertReportCard extends StatelessWidget {
  const AlertReportCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

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
        leading: Icon(icon, color: iconColor, size: 34),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            subtitle,
            style: const TextStyle(color: grayText, height: 1.4),
          ),
        ),
      ),
    );
  }
}
