import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The bell icon's ONE destination - a log of discrete things that already
/// happened (an SMS sent, a restricted app blocked, a push notification
/// delivered, a sync attempt made or retried). Deliberately does NOT
/// contain ongoing state like today's screen time or the detected usage
/// pattern - that's ReportsScreen (the bottom nav's "Reports" tab).
///
/// This split is the direct fix for the confusion this redesign grew out
/// of: previously a single AlertsReportsScreen mixed both kinds of content
/// together, and it was only reachable through an icon-only bell button
/// with no visible label - easy to miss, easy to confuse with the
/// separately-existing "Reports" tab that led somewhere else entirely.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.childProfileId});

  final String childProfileId;

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
      appBar: AppBar(title: const Text('Alerts')),
      body: childProfileId.isEmpty
          ? const _AlertsEmptyState(
              message: 'Pair a child device first to see alerts.',
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

                final data = snapshot.data?.data() ?? <String, dynamic>{};
                final smsLog = _decodeLog(data['smsAlertLog']);
                final restrictionLog = _decodeLog(data['restrictionLog']);
                final pushAlertLog = _decodeLog(data['pushAlertLog']);
                final syncLog = _decodeLog(data['syncLog']);

                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(
                      'Alerts',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'A log of things that already happened on the paired '
                      'device - SMS alerts, blocked apps, delivered push '
                      'notifications, and sync attempts.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _smsAlertSection(context, smsLog),
                    _logSummarySection(
                      context,
                      log: restrictionLog,
                      icon: Icons.block_rounded,
                      iconColor: AppColors.danger,
                      title: 'Restriction Enforcement',
                      emptyMessage: 'No restricted-app blocks recorded yet '
                          'on the child device.',
                      isSuccess: (entry) => entry['outcome'] == 'blocked',
                      entryLabel: (entry) =>
                          '${entry['packageName'] ?? 'unknown app'} · '
                          '${entry['outcome'] ?? 'unknown'}',
                    ),
                    _logSummarySection(
                      context,
                      log: pushAlertLog,
                      icon: Icons.notifications_active_rounded,
                      iconColor: AppColors.info,
                      title: 'Push Notification Delivery',
                      emptyMessage: 'No push notifications sent yet - these '
                          'fire when an unhealthy usage pattern or new '
                          'location is shared, and require the backend to '
                          'be deployed (see backend/DEPLOYMENT.md).',
                      isSuccess: (entry) => entry['outcome'] == 'sent',
                      entryLabel: (entry) =>
                          '${entry['alertType'] ?? 'alert'} · '
                          '${entry['outcome'] ?? 'unknown'}',
                    ),
                    _logSummarySection(
                      context,
                      log: syncLog,
                      icon: Icons.sync_rounded,
                      iconColor: AppColors.accent,
                      title: 'Synchronization Status',
                      emptyMessage: 'No sync attempts recorded yet - this '
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
                  ],
                );
              },
            ),
    );
  }

  /// Real SMS backup-alert delivery log, synced from the child device's
  /// local record of what SmsSentReceiver/SmsDeliveredReceiver actually
  /// observed (see SmsAlertSender.kt) - not a simulated success rate.
  Widget _smsAlertSection(
    BuildContext context,
    List<Map<String, dynamic>> smsLog,
  ) {
    if (smsLog.isEmpty) {
      return const AppEmptyState(
        icon: Icons.sms_rounded,
        title: 'SMS Backup Alerts',
        message: 'No SMS alerts sent yet. These fire automatically when a '
            'restricted app is blocked on the child device (if SMS '
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            icon: Icons.sms_rounded,
            iconColor: AppColors.primary,
            title: 'SMS Backup Alerts',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$sentOrDelivered sent/delivered, $failed failed, out of '
            '${smsLog.length} attempt${smsLog.length == 1 ? '' : 's'} '
            '(most recent ${smsLog.length > 50 ? 50 : smsLog.length} kept '
            'on device).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._entryRows(
            context,
            recent,
            isSuccess: (entry) {
              final outcome = (entry['outcome'] ?? '').toString();
              return outcome == 'sent' || outcome == 'delivered';
            },
            entryLabel: (entry) =>
                '${entry['packageName'] ?? ''} · '
                '${entry['outcome'] ?? 'unknown'}',
          ),
        ],
      ),
    );
  }

  /// Generic outcome-log card shared by restriction-enforcement,
  /// push-notification-delivery, and sync sections (all the same shape: a
  /// list of {outcome, responseTimeMs, timestampMs, ...} entries recorded
  /// natively/client-side at the moment each attempt happened, not
  /// simulated).
  Widget _logSummarySection(
    BuildContext context, {
    required List<Map<String, dynamic>> log,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String emptyMessage,
    required bool Function(Map<String, dynamic> entry) isSuccess,
    required String Function(Map<String, dynamic> entry) entryLabel,
  }) {
    if (log.isEmpty) {
      return AppEmptyState(icon: icon, title: title, message: emptyMessage);
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(icon: icon, iconColor: iconColor, title: title),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$successCount succeeded, $failedCount failed, out of '
            '${log.length} attempt${log.length == 1 ? '' : 's'}'
            '${avgResponseMs != null ? ' · avg response time ${avgResponseMs}ms' : ''}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._entryRows(
            context,
            recent,
            isSuccess: isSuccess,
            entryLabel: entryLabel,
            responseTimeMs: true,
          ),
        ],
      ),
    );
  }

  List<Widget> _entryRows(
    BuildContext context,
    List<Map<String, dynamic>> entries, {
    required bool Function(Map<String, dynamic> entry) isSuccess,
    required String Function(Map<String, dynamic> entry) entryLabel,
    bool responseTimeMs = false,
  }) {
    return entries.map((entry) {
      final success = isSuccess(entry);
      final responseTime = responseTimeMs ? entry['responseTimeMs'] : null;

      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.error_rounded,
              color: success ? AppColors.success : AppColors.danger,
              size: 16,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${entryLabel(entry)} · '
                '${_formatTimestamp(entry['timestampMs'])}'
                '${responseTime is num ? ' · ${responseTime}ms' : ''}',
                style: Theme.of(context).textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

class _AlertsEmptyState extends StatelessWidget {
  const _AlertsEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none_rounded,
                color: AppColors.textDisabled, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
