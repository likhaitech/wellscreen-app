import 'app_usage_summary.dart';
import 'usage_report.dart';

class UsagePeriodChartPoint {
  const UsagePeriodChartPoint({
    required this.label,
    required this.date,
    required this.usageDuration,
    required this.patternStatus,
  });

  final String label;
  final DateTime date;
  final Duration usageDuration;
  final UsagePatternStatus patternStatus;

  double get usageHours {
    return usageDuration.inMinutes / 60;
  }

  String get usageLabel {
    return UsagePeriodSummary.formatDuration(usageDuration);
  }
}

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
    this.chartPoints = const [],
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
  final List<UsagePeriodChartPoint> chartPoints;

  bool get hasReports => reportCount > 0;

  bool get hasChartPoints {
    return chartPoints.any((point) => point.usageDuration > Duration.zero);
  }

  String get totalUsageLabel => formatDuration(totalUsageDuration);

  String get averageDailyUsageLabel => formatDuration(averageDailyUsageDuration);

  String get statusLabel {
    if (!hasReports || patternStatus == null) {
      return 'No Report';
    }

    return patternStatus!.label;
  }

  String get dateRangeLabel {
    return '${formatDate(startDate)} to ${formatDate(endDate)}';
  }

  double get maxChartHours {
    if (chartPoints.isEmpty) {
      return 1;
    }

    final maxValue = chartPoints
        .map((point) => point.usageHours)
        .fold<double>(0, (current, value) => value > current ? value : current);

    if (maxValue <= 0) {
      return 1;
    }

    if (maxValue < 1) {
      return 1;
    }

    return maxValue.ceilToDouble();
  }

  String get chartInsightMessage {
    if (!hasReports) {
      return 'No synced daily report is available for this period yet.';
    }

    final activeDays = chartPoints
        .where((point) => point.usageDuration > Duration.zero)
        .length;

    if (activeDays == 0) {
      return 'No chartable usage activity was found for this period.';
    }

    final highestPoint = chartPoints.reduce((current, next) {
      return next.usageDuration > current.usageDuration ? next : current;
    });

    return 'Chart insight: $activeDays day(s) have synced usage data. Highest recorded day is ${highestPoint.label} with ${highestPoint.usageLabel}.';
  }

  static String formatDuration(Duration duration) {
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

  static String formatDate(DateTime dateTime) {
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
