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

  List<Map<String, dynamic>> _decodeLog(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];

    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
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

                final smsLog = _decodeLog(data['smsAlertLog']);
                final restrictionLog = _decodeLog(data['restrictionLog']);
                final pushAlertLog = _decodeLog(data['pushAlertLog']);
                final syncLog = _decodeLog(data['syncLog']);
                final browsingLog = _decodeLog(data['browsingLog']);
                final mlRiskAssessment = data['mlRiskAssessment'];

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
                    if (mlRiskAssessment is Map)
                      _mlRiskAssessmentCard(
                        Map<String, dynamic>.from(mlRiskAssessment),
                      )
                    else
                      const AlertReportCard(
                        icon: Icons.psychology_alt_rounded,
                        iconColor: Colors.deepPurple,
                        title: 'AI Risk Assessment (Proposed Extension)',
                        subtitle: 'Not synced yet - runs automatically the '
                            'next time usage data is synced from the '
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
                    _logSummarySection(
                      log: restrictionLog,
                      icon: Icons.block_rounded,
                      iconColor: Colors.deepOrange,
                      title: 'Restriction Enforcement',
                      emptySubtitle: 'No restricted-app blocks recorded '
                          'yet on the child device.',
                      isSuccess: (entry) => entry['outcome'] == 'blocked',
                      entryLabel: (entry) =>
                          '${entry['packageName'] ?? 'unknown app'} · '
                          '${entry['outcome'] ?? 'unknown'}',
                    ),
                    _logSummarySection(
                      log: pushAlertLog,
                      icon: Icons.notifications_active_rounded,
                      iconColor: Colors.blueAccent,
                      title: 'Push Notification Delivery',
                      emptySubtitle: 'No push notifications sent yet - '
                          'these fire when an unhealthy usage pattern or '
                          'new location is shared, and require the backend '
                          'to be deployed (see backend/DEPLOYMENT.md).',
                      isSuccess: (entry) => entry['outcome'] == 'sent',
                      entryLabel: (entry) =>
                          '${entry['alertType'] ?? 'alert'} · '
                          '${entry['outcome'] ?? 'unknown'}',
                    ),
                    _logSummarySection(
                      log: syncLog,
                      icon: Icons.sync_rounded,
                      iconColor: Colors.teal,
                      title: 'Synchronization Status',
                      emptySubtitle: 'No sync attempts recorded yet - this '
                          'tracks whether "Sync Usage" actually reached the '
                          'server, including automatic retries after being '
                          'offline.',
                      isSuccess: (entry) => entry['outcome'] == 'synced',
                      entryLabel: (entry) {
                        final trigger = entry['trigger'] == 'auto_reconnect'
                            ? 'auto-reconnect'
                            : 'manual';
                        final recovery = entry['recoveryTimeMs'];
                        final recoverySuffix = recovery is num
                            ? ' · recovered in ${recovery}ms'
                            : '';
                        return '$trigger · '
                            '${entry['outcome'] ?? 'unknown'}$recoverySuffix';
                      },
                    ),
                    _browsingActivitySection(browsingLog),
                    const AlertReportCard(
                      icon: Icons.category_rounded,
                      iconColor: purple,
                      title: 'Category-Level Detection',
                      subtitle:
                          'Live now: captured domains are matched on-device '
                          '(SiteCategoryService) against the real, cleaned '
                          'UT1 dataset in data_cleaned/site_categories/ - a '
                          'match (gambling, drugs, or dangerous_material) '
                          'shows a category tag in Recent Browsing Activity '
                          'above and sends the parent a push alert. This is '
                          'detection and after-the-fact alerting, not '
                          'blocking - the page still loads, since real-time '
                          'prevention would need this same check running '
                          'natively before the page renders, which isn\'t '
                          'built yet. No self-harm category exists in the '
                          'source data (see ml/site_category/README.md); '
                          'PatternDetectionService\'s risky-keyword list is '
                          'still the only thing covering that.',
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

  /// Real output from MlRiskClassifierService - a trained, evaluated
  /// Random Forest (see ml/train_model.py, ml/output/evaluation_report.txt)
  /// run on-device against today's real usage data. Labeled "Proposed
  /// Extension" and explicitly noted as simulated-data-trained, per the
  /// manuscript's own instruction not to present it as more validated than
  /// it is (Ch. 3: "should not be presented as fully trained unless the
  /// researchers already have the dataset, training results, and
  /// evaluation outputs" - it does have those now, just not from real
  /// child usage data). This supplements the rule-based Usage Pattern card
  /// above; it doesn't replace it.
  Widget _mlRiskAssessmentCard(Map<String, dynamic> assessment) {
    final label = (assessment['label'] ?? 'Unknown').toString();
    final confidence = assessment['confidence'];
    final confidencePercent =
        confidence is num ? (confidence * 100).toStringAsFixed(0) : null;

    final icon = switch (label) {
      'High Risk' => Icons.warning_amber_rounded,
      'Moderate Risk' => Icons.shield_moon_rounded,
      _ => Icons.check_circle_rounded,
    };

    final color = switch (label) {
      'High Risk' => Colors.redAccent,
      'Moderate Risk' => Colors.orange,
      _ => Colors.green,
    };

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
                Icon(icon, color: color, size: 30),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'AI Risk Assessment (Proposed Extension)',
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
              confidencePercent != null
                  ? '$label ($confidencePercent% confidence)'
                  : label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Random Forest classifier, trained and evaluated on '
              'simulated usage data (no real dataset exists yet - see '
              'ml/README.md). Supplements the rule-based Usage Pattern '
              'above; not a medical or diagnostic assessment.',
              style: TextStyle(color: grayText, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
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

  /// Generic outcome-log card shared by the restriction-enforcement and
  /// push-notification-delivery sections below (both are the same shape as
  /// the SMS log above: a list of {outcome, responseTimeMs, timestampMs,
  /// ...} entries recorded natively/client-side at the moment each attempt
  /// happened, not simulated). Shows a real success/failure count and, when
  /// present, the average response time across recorded attempts - this is
  /// the "response time" panel criterion, measured per subsystem (blocking,
  /// SMS, push) rather than one single end-to-end timer, since those are
  /// genuinely different operations with different real latencies.
  Widget _logSummarySection({
    required List<Map<String, dynamic>> log,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String emptySubtitle,
    required bool Function(Map<String, dynamic> entry) isSuccess,
    required String Function(Map<String, dynamic> entry) entryLabel,
  }) {
    if (log.isEmpty) {
      return AlertReportCard(
        icon: icon,
        iconColor: iconColor,
        title: title,
        subtitle: emptySubtitle,
      );
    }

    final successCount = log.where(isSuccess).length;
    final failedCount = log.length - successCount;

    final responseTimes = log
        .map((entry) => entry['responseTimeMs'])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final avgResponseMs = responseTimes.isEmpty
        ? null
        : (responseTimes.reduce((a, b) => a + b) / responseTimes.length)
            .round();

    final recent = log.reversed.take(5).toList();

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
                Icon(icon, color: iconColor, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
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
              '$successCount succeeded, $failedCount failed, out of '
              '${log.length} attempt${log.length == 1 ? '' : 's'}'
              '${avgResponseMs != null ? ' · avg response time ${avgResponseMs}ms' : ''}.',
              style: const TextStyle(color: grayText, height: 1.4),
            ),
            const SizedBox(height: 10),
            ...recent.map((entry) {
              final success = isSuccess(entry);
              final responseTimeMs = entry['responseTimeMs'];

              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      success
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: success ? Colors.green : Colors.redAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${entryLabel(entry)} · '
                        '${_formatTimestamp(entry['timestampMs'])}'
                        '${responseTimeMs is num ? ' · ${responseTimeMs}ms' : ''}',
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

  /// Real domains captured natively by BrowserUrlExtractor/BrowsingLogger
  /// (see WellScreenAccessibilityService.kt) whenever a supported browser
  /// is used on the child device, then classified against the real UT1
  /// dataset by SiteCategoryService in syncUsageReport() - entries with a
  /// 'category' key matched the dataset and triggered a parent alert.
  /// Deliberately NOT built on _logSummarySection above - that widget's
  /// "N succeeded, N failed" framing is for pass/fail attempt logs
  /// (blocking, SMS, sync); a captured domain isn't a success or a
  /// failure, it's just a fact, so reusing that wording here would be
  /// misleading rather than honest.
  Widget _browsingActivitySection(List<Map<String, dynamic>> log) {
    if (log.isEmpty) {
      return const AlertReportCard(
        icon: Icons.public_rounded,
        iconColor: Colors.indigo,
        title: 'Recent Browsing Activity',
        subtitle: 'No browser domains captured yet - requires '
            'WellScreen\'s Accessibility permission and one of the '
            'supported browsers (Chrome, Firefox, Samsung Internet, Edge, '
            'Opera, DuckDuckGo) to be used on the child device.',
      );
    }

    final recent = log.reversed.take(5).toList();

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
            const Row(
              children: [
                Icon(Icons.public_rounded, color: Colors.indigo, size: 30),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recent Browsing Activity',
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
            Builder(
              builder: (context) {
                final flaggedCount =
                    log.where((e) => e['category'] != null).length;
                final flaggedSuffix = flaggedCount > 0
                    ? ' $flaggedCount flagged by category matching.'
                    : ' None matched a harmful category.';
                return Text(
                  '${log.length} domain${log.length == 1 ? '' : 's'} '
                  'captured.$flaggedSuffix',
                  style: const TextStyle(color: grayText, height: 1.4),
                );
              },
            ),
            const SizedBox(height: 10),
            ...recent.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      entry['category'] != null
                          ? Icons.warning_amber_rounded
                          : Icons.circle,
                      color: entry['category'] != null
                          ? Colors.redAccent
                          : Colors.indigo,
                      size: entry['category'] != null ? 14 : 8,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${entry['domain'] ?? 'unknown domain'}'
                        '${entry['category'] != null ? ' · ${entry['category']}' : ''} · '
                        '${_formatTimestamp(entry['timestampMs'])}',
                        style: TextStyle(
                          color: entry['category'] != null
                              ? Colors.redAccent
                              : grayText,
                          fontSize: 12,
                          fontWeight: entry['category'] != null
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
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
