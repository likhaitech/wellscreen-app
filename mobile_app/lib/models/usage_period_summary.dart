import 'app_usage_summary.dart';
import 'usage_report.dart';

class UsagePeriodSummary {
  const UsagePeriodSummary({
    required this.title,
    required this.childLabel,
    required this.startDate,
    required this.endDate,
    required this.reportCount,
    required this.totalUsageDuration,
    required this.averageDailyUsageDuration,
    required this.topUsedApp,
    required this.patternStatus,
    required this.unhealthyReportCount,
    required this.warningReportCount,
    required this.recommendationMessage,
  });

  final String title;
  final String childLabel;
  final DateTime startDate;
  final DateTime endDate;
  final int reportCount;
  final Duration totalUsageDuration;
  final Duration averageDailyUsageDuration;
  final AppUsageSummary? topUsedApp;
  final UsagePatternStatus? patternStatus;
  final int unhealthyReportCount;
  final int warningReportCount;
  final String recommendationMessage;

  bool get hasReports => reportCount > 0;

  String get totalUsageLabel => _formatDuration(totalUsageDuration);

  String get averageDailyUsageLabel => _formatDuration(averageDailyUsageDuration);

  String get statusLabel {
    if (!hasReports || patternStatus == null) {
      return 'No Report';
    }

    return patternStatus!.label;
  }

  String get dateRangeLabel {
    return '${_formatDate(startDate)} to ${_formatDate(endDate)}';
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return '${minutes}m';
    }

    return '${duration.inSeconds}s';
  }

  static String _formatDate(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}

class UsagePeriodSummaryBundle {
  const UsagePeriodSummaryBundle({
    required this.weeklySummary,
    required this.monthlySummary,
  });

  final UsagePeriodSummary weeklySummary;
  final UsagePeriodSummary monthlySummary;
}