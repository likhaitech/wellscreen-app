import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Was previously a 100% hardcoded/static screen (fixed sample text like
/// "4 hours 20 minutes", "YouTube, TikTok, Mobile Legends") with zero
/// service or model imports - none of it reflected real device usage.
///
/// Now reads child_profiles/{childProfileId}.latestUsageReport, the same
/// document ParentDashboardScreen's Top Apps / Screen Time / Usage Pattern
/// cards read from, and the same field child_home_screen.dart's
/// syncUsageReport() writes to. If the child hasn't synced yet, this shows
/// an honest "no data yet" state rather than a placeholder number.
class UsageSummaryScreen extends StatelessWidget {
  const UsageSummaryScreen({super.key, required this.childProfileId});

  final String childProfileId;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) return '$hours hour${hours == 1 ? '' : 's'} $minutes minute${minutes == 1 ? '' : 's'}';
    if (minutes > 0) return '$minutes minute${minutes == 1 ? '' : 's'}';
    return '${duration.inSeconds} second${duration.inSeconds == 1 ? '' : 's'}';
  }

  String _formatUpdatedAt(dynamic updatedAt) {
    if (updatedAt is! Timestamp) return 'Not synced yet';

    final date = updatedAt.toDate();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$month/$day $hour:$minute';
  }

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
      body: childProfileId.isEmpty
          ? const _EmptyState(
              message: 'Pair a child device first to see usage data.',
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('child_profiles')
                  .doc(childProfileId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data?.data();
                final report = data?['latestUsageReport'];

                if (report is! Map) {
                  return const _EmptyState(
                    message:
                        'No usage data synced yet. Ask your child to open '
                        'WellScreen and tap "Sync Usage" on their device.',
                  );
                }

                final reportMap = Map<String, dynamic>.from(report);
                final totalMs = reportMap['totalUsageDurationMs'];
                final totalDuration = totalMs is num
                    ? Duration(milliseconds: totalMs.toInt())
                    : Duration.zero;

                final rawApps = reportMap['topApps'];
                final apps = rawApps is List
                    ? rawApps
                        .whereType<Map>()
                        .map((app) => Map<String, dynamic>.from(app))
                        .toList()
                    : <Map<String, dynamic>>[];

                final topAppNames = apps
                    .take(3)
                    .map((app) =>
                        (app['displayName'] ?? app['packageName'] ?? '')
                            .toString())
                    .where((name) => name.isNotEmpty)
                    .join(', ');

                final patternStatus =
                    (reportMap['patternStatus'] ?? 'healthy').toString();
                final recommendation =
                    (reportMap['recommendationMessage'] ?? '').toString();
                final unhealthyCount = reportMap['unhealthyAppCount'];

                final statusLabel = switch (patternStatus) {
                  'unhealthy' => 'Unhealthy',
                  'warning' => 'Warning',
                  _ => 'Healthy',
                };

                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      'Daily Usage',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: darkText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Last synced from the paired device: '
                      '${_formatUpdatedAt(data?['usageReportUpdatedAt'])}',
                      style: const TextStyle(color: grayText, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    SummaryCard(
                      icon: Icons.today_rounded,
                      title: 'Today\'s Screen Time',
                      value: _formatDuration(totalDuration),
                      description:
                          'Total monitored usage today, read from the '
                          'device\'s Android usage stats.',
                    ),
                    SummaryCard(
                      icon: Icons.apps_rounded,
                      title: 'Top Used Applications',
                      value: topAppNames.isEmpty
                          ? 'No app usage recorded today'
                          : topAppNames,
                      description:
                          'Apps with the highest usage duration today, '
                          'ranked by time on screen.',
                    ),
                    SummaryCard(
                      icon: Icons.insights_rounded,
                      title: 'Detected Pattern',
                      value: statusLabel,
                      description: recommendation.isEmpty
                          ? 'No recommendation available.'
                          : recommendation,
                    ),
                    SummaryCard(
                      icon: Icons.category_rounded,
                      title: 'Apps Needing Attention',
                      value: unhealthyCount is num
                          ? '${unhealthyCount.toInt()}'
                          : '0',
                      description:
                          'Number of risky/high-usage apps flagged by the '
                          'on-device rule-based detector today.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Weekly averages and category-level events aren\'t '
                      'implemented yet - only today\'s synced report is '
                      'shown here.',
                      style: TextStyle(color: grayText, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded,
                color: UsageSummaryScreen.grayText, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: UsageSummaryScreen.grayText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
