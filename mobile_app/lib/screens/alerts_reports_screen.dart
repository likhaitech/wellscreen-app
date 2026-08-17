import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Was previously six fully hardcoded cards ("Exceeded Usage Limit",
/// "Late-Night Usage", "Category Indicator", "Location Update", "Delayed
/// Synchronization", "Recommendation") with generic made-up copy and no
/// data source at all - none of it reflected anything real.
///
/// Now reads child_profiles/{childProfileId}, the same document
/// ParentDashboardScreen/UsageSummaryScreen read from and
/// child_home_screen.dart writes to. Shows real data where it exists
/// (usage pattern + recommendation, GPS location, SMS backup-alert delivery
/// log) and an honest "not implemented yet" note for what doesn't
/// (category-level detection - see BRANCH_REAUDIT).
class AlertsReportsScreen extends StatelessWidget {
  const AlertsReportsScreen({super.key, required this.childProfileId});

  final String childProfileId;

  static const Color purple = Color(0xFF5B2BBF);
  static const Color darkText = Color(0xFF111827);
  static const Color grayText = Color(0xFF4B5563);

  String _formatTimestamp(dynamic value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is int) {
      date = DateTime.fromMillisecondsSinceEpoch(value);
    }

    if (date == null) return 'Not available';

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
          'Alerts and Reports',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: childProfileId.isEmpty
          ? const _EmptyState(message: 'Pair a child device first.')
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('child_profiles')
                  .doc(childProfileId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data?.data() ?? <String, dynamic>{};
                final usageReport = data['latestUsageReport'];
                final location = data['latestLocation'];
                final rawSmsLog = data['smsAlertLog'];

                final smsLog = rawSmsLog is List
                    ? rawSmsLog
                        .whereType<Map>()
                        .map((entry) => Map<String, dynamic>.from(entry))
                        .toList()
                    : <Map<String, dynamic>>[];

                return ListView(
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
                      'Real alerts synced from the paired device - usage '
                      'patterns, location, and SMS backup-alert delivery.',
                      style: TextStyle(color: grayText, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    if (usageReport is Map)
                      _usagePatternCard(Map<String, dynamic>.from(usageReport))
                    else
                      const AlertReportCard(
                        icon: Icons.bar_chart_rounded,
                        iconColor: Colors.orange,
                        title: 'Usage Pattern',
                        subtitle: 'No usage report synced yet from the '
                            'child device.',
                      ),
                    if (location is Map)
                      _locationCard(Map<String, dynamic>.from(location),
                          data['locationUpdatedAt'])
                    else
                      const AlertReportCard(
                        icon: Icons.location_on_rounded,
                        iconColor: Colors.green,
                        title: 'Location Update',
                        subtitle: 'No GPS location shared yet from the '
                            'child device.',
                      ),
                    _smsAlertSection(smsLog),
                    const AlertReportCard(
                      icon: Icons.category_rounded,
                      iconColor: purple,
                      title: 'Category-Level Detection',
                      subtitle:
                          'Not implemented yet - detection is currently '
                          'limited to the risky-keyword list in '
                          'PatternDetectionService, not per-category '
                          'analysis.',
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _usagePatternCard(Map<String, dynamic> report) {
    final status = (report['patternStatus'] ?? 'healthy').toString();
    final recommendation =
        (report['recommendationMessage'] ?? 'No recommendation available.')
            .toString();

    final icon = switch (status) {
      'unhealthy' => Icons.warning_amber_rounded,
      'warning' => Icons.shield_moon_rounded,
      _ => Icons.check_circle_rounded,
    };

    final color = switch (status) {
      'unhealthy' => Colors.redAccent,
      'warning' => Colors.orange,
      _ => Colors.green,
    };

    final title = switch (status) {
      'unhealthy' => 'Unhealthy Usage Pattern',
      'warning' => 'Usage Warning',
      _ => 'Healthy Usage Pattern',
    };

    return AlertReportCard(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: recommendation,
    );
  }

  Widget _locationCard(Map<String, dynamic> location, dynamic updatedAt) {
    final label = location['label'];
    final latitude = location['latitude'];
    final longitude = location['longitude'];

    final subtitle = label != null && label.toString().isNotEmpty
        ? label.toString()
        : (latitude is num && longitude is num)
            ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
            : 'No shared GPS yet';

    return AlertReportCard(
      icon: Icons.location_on_rounded,
      iconColor: Colors.green,
      title: 'Location Update',
      subtitle: '$subtitle · Last synced: ${_formatTimestamp(updatedAt)}',
    );
  }

  /// Real SMS backup-alert delivery log, synced from the child device's
  /// local record of what SmsSentReceiver/SmsDeliveredReceiver actually
  /// observed (see SmsAlertSender.kt) - not a simulated success rate.
  Widget _smsAlertSection(List<Map<String, dynamic>> smsLog) {
    if (smsLog.isEmpty) {
      return const AlertReportCard(
        icon: Icons.sms_rounded,
        iconColor: Colors.indigo,
        title: 'SMS Backup Alerts',
        subtitle: 'No SMS alerts sent yet. These fire automatically when '
            'a restricted app is blocked on the child device (if SMS '
            'permission is granted and a parent phone number is set).',
      );
    }

    final sentOrDelivered = smsLog
        .where((entry) =>
            entry['outcome'] == 'sent' || entry['outcome'] == 'delivered')
        .length;
    final failed = smsLog
        .where((entry) =>
            (entry['outcome'] as String? ?? '').startsWith('failed'))
        .length;

    final recent = smsLog.reversed.take(5).toList();

    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sms_rounded, color: Colors.indigo, size: 30),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'SMS Backup Alerts',
                    style: TextStyle(
                      color: darkText,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$sentOrDelivered sent/delivered, $failed failed, out of '
              '${smsLog.length} attempt${smsLog.length == 1 ? '' : 's'} '
              '(most recent ${smsLog.length > 50 ? 50 : smsLog.length} '
              'kept on device).',
              style: const TextStyle(color: grayText, height: 1.4),
            ),
            const SizedBox(height: 10),
            ...recent.map((entry) {
              final outcome = (entry['outcome'] ?? 'unknown').toString();
              final packageName = (entry['packageName'] ?? '').toString();
              final isSuccess =
                  outcome == 'sent' || outcome == 'delivered';

              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      isSuccess
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: isSuccess ? Colors.green : Colors.redAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$packageName · $outcome · '
                        '${_formatTimestamp(entry['timestampMs'])}',
                        style: const TextStyle(
                          color: grayText,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
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
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AlertsReportsScreen.grayText,
            fontWeight: FontWeight.w600,
          ),
        ),
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
