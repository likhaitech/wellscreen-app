import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '$hours hour${hours == 1 ? '' : 's'} $minutes minute${minutes == 1 ? '' : 's'}';
  }
  if (minutes > 0) return '$minutes minute${minutes == 1 ? '' : 's'}';
  return '${duration.inSeconds} second${duration.inSeconds == 1 ? '' : 's'}';
}

List<Map<String, dynamic>> _decodeLog(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList();
}

/// One icon per detected category, so a flagged entry reads at a glance
/// instead of every flag looking like the same generic warning triangle.
IconData _categoryIcon(String? category) {
  switch (category) {
    case 'gambling':
      return Icons.casino_rounded;
    case 'drugs':
      return Icons.medication_rounded;
    case 'dangerous_material':
      return Icons.dangerous_rounded;
    case 'adult':
      return Icons.explicit_rounded;
    default:
      return Icons.warning_amber_rounded;
  }
}

/// Human-readable label for the raw category string the classifier stores
/// ('gambling'/'drugs'/'dangerous_material'/'adult'). Guardians see this
/// directly on the browsing activity badge - the raw snake_case value
/// (e.g. "dangerous_material") previously leaked straight into that badge
/// unchanged, which reads as an internal code, not something written for a
/// non-technical parent/guardian to understand at a glance.
String _categoryLabel(String? category) {
  switch (category) {
    case 'gambling':
      return 'Gambling';
    case 'drugs':
      return 'Drugs';
    case 'dangerous_material':
      return 'Dangerous Material';
    case 'adult':
      return 'Adult Content';
    default:
      return 'Flagged';
  }
}

/// A preview-then-expand list, used everywhere a log could grow past a
/// handful of entries (browsing activity, SMS/restriction/push/sync logs).
/// Shows [previewCount] items with a "Show all N" toggle instead of either
/// silently truncating history or dumping a long list into the tab all at
/// once - it still scrolls normally with the rest of the tab (there's no
/// nested scroll view here), it just starts collapsed.
class _ExpandableList extends StatefulWidget {
  const _ExpandableList({
    required this.itemCount,
    required this.itemBuilder,
    this.previewCount = 5,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final int previewCount;

  @override
  State<_ExpandableList> createState() => _ExpandableListState();
}

class _ExpandableListState extends State<_ExpandableList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasMore = widget.itemCount > widget.previewCount;
    final visibleCount =
        _expanded ? widget.itemCount : widget.previewCount.clamp(0, widget.itemCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visibleCount; i++) widget.itemBuilder(context, i),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded
                          ? 'Show less'
                          : 'Show all ${widget.itemCount}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The ONE destination for "what's going on with my child's usage" -
/// everything that used to be split across UsageSummaryScreen, half of
/// AlertsReportsScreen, and (briefly, in an earlier pass of this redesign)
/// a separate bell-icon AlertsScreen now lives here as four selectable
/// tabs: Usage, Browsing, Location, Alerts. Reached from the bottom nav's
/// "Reports" tab, or from the bell icon (which deep-links straight to the
/// Alerts tab via [initialTab] instead of opening a second screen).
///
/// WHY EVERYTHING IS ONE SCREEN NOW, NOT TWO: the previous split (ongoing
/// state on the Reports tab vs discrete event logs on the bell) was a
/// reasonable taxonomy, but a parent looking for "what did the app catch"
/// still had to know which of two icons to tap - the exact kind of
/// discoverability problem this whole redesign started from. One screen
/// with visible, labeled tabs means everything is findable from a single
/// entry point, and switching between categories is one tap instead of a
/// full navigation.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    super.key,
    required this.childProfileId,
    this.initialTab = 0,
  });

  final String childProfileId;

  /// 0 = Usage, 1 = Browsing, 2 = Location, 3 = Alerts. The bell icon in
  /// parent_dashboard_screen.dart passes 3 so it lands directly on Alerts
  /// instead of making the parent re-select it.
  final int initialTab;

  static const List<Tab> _tabs = [
    Tab(text: 'Usage'),
    Tab(text: 'Browsing'),
    Tab(text: 'Location'),
    Tab(text: 'Alerts'),
  ];

  @override
  Widget build(BuildContext context) {
    if (childProfileId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: const _ReportsEmptyState(
          message: 'Pair a child device first to see reports.',
        ),
      );
    }

    return DefaultTabController(
      length: _tabs.length,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: TabBar(
            tabs: _tabs,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('child_profiles')
              .doc(childProfileId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: AppSpacing.md),
                    Text(
                      'Loading reports...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }

            final data = snapshot.data?.data() ?? <String, dynamic>{};

            return TabBarView(
              children: [
                _usageTab(context, data),
                _browsingTab(context, data),
                _locationTab(context, data),
                _alertsTab(context, data),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Usage tab - today's screen time, top apps, detected pattern, AI risk.
  // ---------------------------------------------------------------------

  Widget _usageTab(BuildContext context, Map<String, dynamic> data) {
    final report = data['latestUsageReport'];
    final mlRiskAssessment = data['mlRiskAssessment'];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (report is Map)
          _usageSummarySection(
            context,
            Map<String, dynamic>.from(report),
            data['usageReportUpdatedAt'],
          )
        else
          const AppEmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'Today\'s Usage',
            message: 'No usage data synced yet. Ask your child to open '
                'WellScreen and tap "Sync Usage".',
          ),
        if (report is Map)
          _usagePatternCard(context, Map<String, dynamic>.from(report)),
        if (mlRiskAssessment is Map)
          _mlRiskAssessmentCard(
            context,
            Map<String, dynamic>.from(mlRiskAssessment),
          )
        else
          const AppEmptyState(
            icon: Icons.psychology_alt_rounded,
            title: 'AI Risk Assessment (Proposed Extension)',
            message: 'Not synced yet - runs automatically the next time '
                'usage data is synced.',
          ),
      ],
    );
  }

  Widget _usageSummarySection(
    BuildContext context,
    Map<String, dynamic> report,
    dynamic updatedAt,
  ) {
    final totalMs = report['totalUsageDurationMs'];
    final totalDuration =
        totalMs is num ? Duration(milliseconds: totalMs.toInt()) : Duration.zero;

    final rawApps = report['topApps'];
    final apps = rawApps is List
        ? rawApps
            .whereType<Map>()
            .map((app) => Map<String, dynamic>.from(app))
            .toList()
        : <Map<String, dynamic>>[];
    final topAppNames = apps
        .take(3)
        .map((app) => (app['displayName'] ?? app['packageName'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .join(', ');
    final unhealthyCount = report['unhealthyAppCount'];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.today_rounded,
            iconColor: AppColors.primary,
            title: 'Today\'s Screen Time',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _formatDuration(totalDuration),
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 22, color: AppColors.primary),
          ),
          Text(
            'Last synced ${_formatTimestamp(updatedAt)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const Divider(height: AppSpacing.xl),
          Text('Top Used Applications',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            topAppNames.isEmpty ? 'No app usage recorded today' : topAppNames,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Apps Needing Attention',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${unhealthyCount is num ? unhealthyCount.toInt() : 0} app(s) '
            'flagged for unhealthy usage today.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _usagePatternCard(BuildContext context, Map<String, dynamic> report) {
    final status = (report['patternStatus'] ?? 'healthy').toString();
    final recommendation =
        (report['recommendationMessage'] ?? 'No recommendation available.')
            .toString();

    final (icon, color, bg, title) = switch (status) {
      'unhealthy' => (
          Icons.warning_amber_rounded,
          AppColors.danger,
          AppColors.dangerBg,
          'Unhealthy Usage Pattern',
        ),
      'warning' => (
          Icons.shield_moon_rounded,
          AppColors.warning,
          AppColors.warningBg,
          'Usage Warning',
        ),
      _ => (
          Icons.check_circle_rounded,
          AppColors.success,
          AppColors.successBg,
          'Healthy Usage Pattern',
        ),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: icon,
            iconColor: color,
            title: 'Detected Pattern',
            trailing: AppBadge(label: title, color: color, background: bg),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(recommendation, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _mlRiskAssessmentCard(
    BuildContext context,
    Map<String, dynamic> assessment,
  ) {
    final label = (assessment['label'] ?? 'Unknown').toString();
    final confidence = assessment['confidence'];
    final confidencePercent =
        confidence is num ? (confidence * 100).toStringAsFixed(0) : null;

    final (icon, color, bg) = switch (label) {
      'High Risk' => (
          Icons.warning_amber_rounded,
          AppColors.danger,
          AppColors.dangerBg,
        ),
      'Moderate Risk' => (
          Icons.shield_moon_rounded,
          AppColors.warning,
          AppColors.warningBg,
        ),
      _ => (
          Icons.check_circle_rounded,
          AppColors.success,
          AppColors.successBg,
        ),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.psychology_alt_rounded,
            iconColor: AppColors.accent,
            title: 'AI Risk Assessment (Proposed Extension)',
            trailing: AppBadge(
              label: confidencePercent != null ? '$label $confidencePercent%' : label,
              color: color,
              background: bg,
              icon: icon,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'An experimental feature that estimates today\'s usage risk '
            'from activity patterns. It supplements the usage pattern '
            'summary above - it is not a medical or diagnostic assessment, '
            'and should not be used on its own.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Browsing tab - captured domains and how category detection works.
  // ---------------------------------------------------------------------

  Widget _browsingTab(BuildContext context, Map<String, dynamic> data) {
    final browsingLog = _decodeLog(data['browsingLog']);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _BrowsingActivityCard(log: browsingLog),
        _categoryDetectionInfoCard(context),
      ],
    );
  }

  Widget _categoryDetectionInfoCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.category_rounded,
            iconColor: AppColors.primary,
            title: 'How Category Detection Works',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'WellScreen checks browsing activity three ways, entirely on '
            'the child\'s device: an exact match against a large, curated '
            'list of known harmful sites (gambling, drugs, dangerous '
            'items, and adult content), a keyword check for explicit '
            'content, and an AI model that catches gambling sites not yet '
            'on the list.\n\n'
            'This is detection and after-the-fact alerting, not blocking '
            '- a flagged page will still have loaded on the child\'s '
            'device before you see the alert here, since real-time '
            'blocking isn\'t built yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Location tab.
  // ---------------------------------------------------------------------

  Widget _locationTab(BuildContext context, Map<String, dynamic> data) {
    final location = data['latestLocation'];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (location is Map)
          _locationCard(
            context,
            Map<String, dynamic>.from(location),
            data['locationUpdatedAt'],
          )
        else
          const AppEmptyState(
            icon: Icons.location_on_rounded,
            title: 'Location Update',
            message: 'No GPS location shared yet.',
          ),
      ],
    );
  }

  Widget _locationCard(
    BuildContext context,
    Map<String, dynamic> location,
    dynamic updatedAt,
  ) {
    final label = location['label'];
    final latitude = location['latitude'];
    final longitude = location['longitude'];
    final subtitle = label != null && label.toString().isNotEmpty
        ? label.toString()
        : (latitude is num && longitude is num)
            ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
            : 'No shared GPS yet';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.location_on_rounded,
            iconColor: AppColors.success,
            title: 'Location Update',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            'Last synced: ${_formatTimestamp(updatedAt)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Alerts tab - discrete things that already happened (SMS sent, an app
  // blocked, a push delivered, a sync attempt). Moved here from the bell
  // icon's old standalone AlertsScreen - see this file's class doc comment
  // for why. The bell now just deep-links to this tab via [initialTab].
  // ---------------------------------------------------------------------

  Widget _alertsTab(BuildContext context, Map<String, dynamic> data) {
    final smsLog = _decodeLog(data['smsAlertLog']);
    final restrictionLog = _decodeLog(data['restrictionLog']);
    final pushAlertLog = _decodeLog(data['pushAlertLog']);
    final syncLog = _decodeLog(data['syncLog']);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _smsAlertSection(context, smsLog),
        _logSummarySection(
          context,
          log: restrictionLog,
          icon: Icons.block_rounded,
          iconColor: AppColors.danger,
          title: 'Restriction Enforcement',
          emptyMessage: 'No restricted-app blocks recorded yet on the '
              'child device.',
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
          emptyMessage: 'No push notifications sent yet - these fire when '
              'an unhealthy usage pattern or new location is shared, and '
              'require the backend to be deployed (see '
              'backend/DEPLOYMENT.md).',
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
          emptyMessage: 'No sync attempts recorded yet - this tracks '
              'whether "Sync Usage" actually reached the server, including '
              'automatic retries after being offline.',
          isSuccess: (entry) => entry['outcome'] == 'synced',
          entryLabel: (entry) {
            final trigger = entry['trigger'] == 'auto_reconnect'
                ? 'auto-reconnect'
                : 'manual';
            final recovery = entry['recoveryTimeMs'];
            final recoverySuffix =
                recovery is num ? ' · recovered in ${recovery}ms' : '';
            return '$trigger · '
                '${entry['outcome'] ?? 'unknown'}$recoverySuffix';
          },
        ),
      ],
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
    final reversed = smsLog.reversed.toList();
    bool isSuccess(Map<String, dynamic> entry) {
      final outcome = (entry['outcome'] ?? '').toString();
      return outcome == 'sent' || outcome == 'delivered';
    }

    String entryLabel(Map<String, dynamic> entry) =>
        '${entry['packageName'] ?? ''} · '
        '${entry['outcome'] ?? 'unknown'}';

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
          _ExpandableList(
            itemCount: reversed.length,
            itemBuilder: (context, i) => _entryRow(
              context,
              reversed[i],
              isSuccess: isSuccess(reversed[i]),
              label: entryLabel(reversed[i]),
            ),
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
    final reversed = log.reversed.toList();

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
          _ExpandableList(
            itemCount: reversed.length,
            itemBuilder: (context, i) => _entryRow(
              context,
              reversed[i],
              isSuccess: isSuccess(reversed[i]),
              label: entryLabel(reversed[i]),
              responseTimeMs: reversed[i]['responseTimeMs'],
            ),
          ),
        ],
      ),
    );
  }

  /// One log-entry row, shared by the SMS, restriction, push, and sync
  /// sections above - all render the same shape (success/fail icon + a
  /// one-line label + timestamp), just built from different fields.
  Widget _entryRow(
    BuildContext context,
    Map<String, dynamic> entry, {
    required bool isSuccess,
    required String label,
    dynamic responseTimeMs,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
            color: isSuccess ? AppColors.success : AppColors.danger,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$label · '
              '${_formatTimestamp(entry['timestampMs'])}'
              '${responseTimeMs is num ? ' · ${responseTimeMs}ms' : ''}',
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Real domains captured natively by BrowserUrlExtractor/BrowsingLogger,
/// then classified against the real UT1 dataset by SiteCategoryService in
/// syncUsageReport() - entries with a 'category' key matched the dataset
/// (or the keyword/ML fallback) and triggered a parent alert. Stateful (not
/// a plain method like the rest of this screen) so it can hold its own
/// "All / Flagged only" filter and remember whether the list is expanded
/// without threading that state up into ReportsScreen itself.
class _BrowsingActivityCard extends StatefulWidget {
  const _BrowsingActivityCard({required this.log});

  final List<Map<String, dynamic>> log;

  @override
  State<_BrowsingActivityCard> createState() => _BrowsingActivityCardState();
}

class _BrowsingActivityCardState extends State<_BrowsingActivityCard> {
  bool _flaggedOnly = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;

    if (log.isEmpty) {
      return const AppEmptyState(
        icon: Icons.public_rounded,
        title: 'Recent Browsing Activity',
        message: 'No browser domains captured yet - requires WellScreen\'s '
            'Accessibility permission and one of the supported browsers '
            '(Chrome, Firefox, Samsung Internet, Edge, Opera, DuckDuckGo) '
            'to be used on the child device.',
      );
    }

    final flaggedCount = log.where((e) => e['category'] != null).length;
    final reversed = log.reversed.toList();
    final visible = _flaggedOnly
        ? reversed.where((e) => e['category'] != null).toList()
        : reversed;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.public_rounded,
            iconColor: AppColors.primary,
            title: 'Recent Browsing Activity',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${log.length} domain${log.length == 1 ? '' : 's'} captured. '
            '${flaggedCount > 0 ? '$flaggedCount flagged by category matching.' : 'None matched a harmful category.'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (flaggedCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _filterChip(
                  label: 'All (${log.length})',
                  selected: !_flaggedOnly,
                  onTap: () => setState(() => _flaggedOnly = false),
                ),
                const SizedBox(width: 8),
                _filterChip(
                  label: 'Flagged only ($flaggedCount)',
                  selected: _flaggedOnly,
                  onTap: () => setState(() => _flaggedOnly = true),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (visible.isEmpty)
            const Text(
              'No flagged domains yet.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            _ExpandableList(
              itemCount: visible.length,
              itemBuilder: (context, i) => _entry(context, visible[i]),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, Map<String, dynamic> entry) {
    final category = entry['category'];
    final source = entry['detectionSource'];
    final (sourceLabel, sourceColor) = switch (source) {
      'ml' => ('AI-detected', AppColors.sourceMl),
      'keyword' => ('keyword match', AppColors.sourceKeyword),
      _ => ('exact match', AppColors.sourceLookup),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            category != null ? _categoryIcon(category) : Icons.circle,
            color: category != null ? AppColors.danger : AppColors.primary,
            size: category != null ? 16 : 8,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (entry['domain'] ?? 'unknown domain').toString(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        category != null ? FontWeight.w700 : FontWeight.w500,
                    color: category != null
                        ? AppColors.danger
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  _formatTimestamp(entry['timestampMs']),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (category != null)
            AppBadge(
              label: '${_categoryLabel(category as String?)} · $sourceLabel',
              color: sourceColor,
              background: sourceColor.withValues(alpha: 0.12),
            ),
        ],
      ),
    );
  }
}

class _ReportsEmptyState extends StatelessWidget {
  const _ReportsEmptyState({required this.message});

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
