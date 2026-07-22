import '../models/usage_report.dart';
import 'intervention_recommendation_service.dart';
import 'usage_dashboard_service.dart';

class UsageDashboardViewModel {
  const UsageDashboardViewModel({
    required this.statusLabel,
    required this.totalUsageLabel,
    required this.topUsedAppLabel,
    required this.unhealthyAppCountLabel,
    required this.recommendationMessage,
    required this.interventionTitle,
    required this.interventionMessage,
    required this.isUsingCachedData,
    required this.hasUsagePermission,
    required this.errorMessage,
    this.riskScoreLabel = '0/100 - Healthy Risk',
    this.riskFactorSummary = 'No risk factors were detected in this report.',
  });

  final String statusLabel;
  final String totalUsageLabel;
  final String topUsedAppLabel;
  final String unhealthyAppCountLabel;
  final String recommendationMessage;
  final String interventionTitle;
  final String interventionMessage;
  final bool isUsingCachedData;
  final bool hasUsagePermission;
  final String? errorMessage;
  final String riskScoreLabel;
  final String riskFactorSummary;
}

class UsageDashboardViewModelService {
  UsageDashboardViewModel buildViewModel(UsageDashboardResult result) {
    final report = result.report;
    final intervention = result.interventionRecommendation;

    return UsageDashboardViewModel(
      statusLabel: _getStatusLabel(report),
      totalUsageLabel: _getTotalUsageLabel(report),
      topUsedAppLabel: _getTopUsedAppLabel(report),
      unhealthyAppCountLabel: _getUnhealthyAppCountLabel(report),
      recommendationMessage:
          report?.recommendationMessage ?? 'No usage report available yet.',
      interventionTitle: _getInterventionTitle(intervention),
      interventionMessage: _getInterventionMessage(intervention),
      isUsingCachedData: result.isUsingCachedData,
      hasUsagePermission: result.hasUsagePermission,
      errorMessage: result.errorMessage,
      riskScoreLabel: _getRiskScoreLabel(report),
      riskFactorSummary: _getRiskFactorSummary(report),
    );
  }

  String _getStatusLabel(UsageReport? report) {
    if (report == null) {
      return 'No Report';
    }

    return report.patternStatus.label;
  }

  String _getTotalUsageLabel(UsageReport? report) {
    if (report == null) {
      return '0s';
    }

    return report.totalUsageLabel;
  }

  String _getTopUsedAppLabel(UsageReport? report) {
    final topUsedApp = report?.topUsedApp;

    if (topUsedApp == null) {
      return 'No app usage recorded';
    }

    return '${topUsedApp.displayName} • ${topUsedApp.usageLabel}';
  }

  String _getUnhealthyAppCountLabel(UsageReport? report) {
    if (report == null) {
      return '0 apps need attention';
    }

    if (report.unhealthyAppCount == 1) {
      return '1 app needs attention';
    }

    return '${report.unhealthyAppCount} apps need attention';
  }

  String _getRiskScoreLabel(UsageReport? report) {
    if (report == null) {
      return '0/100 - No Report';
    }

    return '${report.riskScoreLabel} - ${report.riskLevelLabel}';
  }

  String _getRiskFactorSummary(UsageReport? report) {
    if (report == null) {
      return 'Generate a usage report first to calculate the point-based risk score.';
    }

    return report.riskFactorSummary;
  }

  String _getInterventionTitle(InterventionRecommendation? intervention) {
    return intervention?.title ?? 'No Intervention Available';
  }

  String _getInterventionMessage(InterventionRecommendation? intervention) {
    return intervention?.message ??
        'Generate a usage report first to receive a recommendation.';
  }
}
