import '../models/usage_report.dart';

enum InterventionType {
  none,
  breakReminder,
  appLimit,
  focusMode,
  bedtimeRestriction,
}

class InterventionRecommendation {
  const InterventionRecommendation({
    required this.type,
    required this.title,
    required this.message,
    required this.isUrgent,
  });

  final InterventionType type;
  final String title;
  final String message;
  final bool isUrgent;
}

class InterventionRecommendationService {
  InterventionRecommendation getRecommendation(UsageReport report) {
    switch (report.patternStatus) {
      case UsagePatternStatus.healthy:
        return _getHealthyRecommendation(report);

      case UsagePatternStatus.warning:
        return _getWarningRecommendation(report);

      case UsagePatternStatus.unhealthy:
        return _getUnhealthyRecommendation(report);
    }
  }

  InterventionRecommendation _getHealthyRecommendation(UsageReport report) {
    final topAppName = _getTopAppName(report);

    return InterventionRecommendation(
      type: InterventionType.none,
      title: 'Healthy Usage',
      message: _buildParentGuidedMessage(
        report: report,
        situation:
            'The child’s current screen use appears balanced based on the available usage report.',
        guardianAction:
            'Keep the current rules active and continue checking the usage summary at least once a day.',
        childGuidance:
            'Encourage the child to continue using the device for learning, communication, and healthy entertainment.',
        followUp:
            'No urgent restriction is needed. Review again after the next synced usage report, especially if $topAppName becomes longer than usual.',
      ),
      isUrgent: false,
    );
  }

  InterventionRecommendation _getWarningRecommendation(UsageReport report) {
    if (_hasLateNightUse(report)) {
      return InterventionRecommendation(
        type: InterventionType.bedtimeRestriction,
        title: 'Parent Bedtime Review Recommended',
        message: _buildParentGuidedMessage(
          report: report,
          situation:
              'The report suggests possible late-night or bedtime-related phone use.',
          guardianAction:
              'Review the child’s evening routine and consider turning on scheduled lock sessions during rest hours.',
          childGuidance:
              'Explain that the goal is to protect sleep time, not to punish the child.',
          followUp:
              'Check tomorrow’s report to see if nighttime usage decreases after the rule is applied.',
        ),
        isUrgent: false,
      );
    }

    if (report.unhealthyAppCount > 0 || _hasRiskyAppUse(report)) {
      return InterventionRecommendation(
        type: InterventionType.appLimit,
        title: 'Parent App-Limit Review Recommended',
        message: _buildParentGuidedMessage(
          report: report,
          situation:
              '${_getTopAppName(report)} appears to need closer parent review because one or more apps may be taking too much attention.',
          guardianAction:
              'Consider enabling app blocking, cooldown timer, or a lower daily limit for distracting apps.',
          childGuidance:
              'Talk with the child about which apps are useful and which apps should be limited during study or rest time.',
          followUp:
              'After saving the rule, ask the child device to open Child Home so the latest parent rules can sync locally.',
        ),
        isUrgent: false,
      );
    }

    return InterventionRecommendation(
      type: InterventionType.breakReminder,
      title: 'Parent Break Reminder Recommended',
      message: _buildParentGuidedMessage(
        report: report,
        situation:
            'Screen time is moving close to the warning level, but it does not require strict blocking yet.',
        guardianAction:
            'Encourage short breaks and review whether the daily limit is still appropriate for the child’s age and routine.',
        childGuidance:
            'Suggest a simple break activity such as stretching, drinking water, schoolwork, or outdoor play.',
        followUp:
            'Generate another usage report later to confirm whether screen time returned to a healthier level.',
      ),
      isUrgent: false,
    );
  }

  InterventionRecommendation _getUnhealthyRecommendation(UsageReport report) {
    if (_hasLateNightUse(report)) {
      return InterventionRecommendation(
        type: InterventionType.bedtimeRestriction,
        title: 'Urgent Parent Bedtime Action Recommended',
        message: _buildParentGuidedMessage(
          report: report,
          situation:
              'The report indicates unhealthy usage with possible late-night activity, which may affect rest time.',
          guardianAction:
              'Enable scheduled lock sessions from 10:00 PM to 5:00 AM and keep emergency access available for essential use.',
          childGuidance:
              'Explain the rule calmly and connect it to sleep, school readiness, and healthier daily habits.',
          followUp:
              'Review the next daily report and check whether the risk score improves after the bedtime rule is applied.',
        ),
        isUrgent: true,
      );
    }

    if (report.unhealthyAppCount >= 2 || report.clampedRiskScore >= 70) {
      return InterventionRecommendation(
        type: InterventionType.focusMode,
        title: 'Urgent Parent Focus Mode Recommended',
        message: _buildParentGuidedMessage(
          report: report,
          situation:
              'Several usage signals suggest that the child may need stronger guardian-guided boundaries today.',
          guardianAction:
              'Enable Focus Mode and App Blocking, then keep Cooldown Timer on to reduce repeated attempts to reopen distracting apps.',
          childGuidance:
              'Tell the child when the restriction starts, why it is needed, and what activities are allowed during focus time.',
          followUp:
              'Check the open-attempt count and usage summary after the next sync to see if the rule is effective.',
        ),
        isUrgent: true,
      );
    }

    return InterventionRecommendation(
      type: InterventionType.focusMode,
      title: 'Parent-Guided Restriction Recommended',
      message: _buildParentGuidedMessage(
        report: report,
        situation:
            'The report is currently unhealthy and needs guardian attention before usage becomes harder to manage.',
        guardianAction:
            'Use Focus Mode or temporary app blocking for distracting apps while keeping essential functions available.',
        childGuidance:
            'Discuss one clear screen-time goal with the child, such as finishing schoolwork first before entertainment apps.',
        followUp:
            'Review the risk score and top-used app after the next report to decide whether the restriction can be reduced.',
      ),
      isUrgent: true,
    );
  }

  String _buildParentGuidedMessage({
    required UsageReport report,
    required String situation,
    required String guardianAction,
    required String childGuidance,
    required String followUp,
  }) {
    return 'Usage context: ${_getUsageContext(report)}\n\n'
        'Risk review: ${_getRiskContext(report)}\n\n'
        'Parent review: $situation\n\n'
        'Suggested guardian action: $guardianAction\n\n'
        'Child guidance: $childGuidance\n\n'
        'Follow-up: $followUp';
  }

  String _getUsageContext(UsageReport report) {
    final topUsedApp = report.topUsedApp;

    if (topUsedApp == null) {
      return 'Total screen time is ${report.totalUsageLabel}. No top app was recorded in this report.';
    }

    return 'Total screen time is ${report.totalUsageLabel}. The most used app is ${topUsedApp.displayName} with ${topUsedApp.usageLabel}.';
  }

  String _getRiskContext(UsageReport report) {
    final factors = report.riskFactors;

    if (factors.isEmpty) {
      return 'Risk score is ${report.riskScoreLabel}. No specific risk factors were detected.';
    }

    final visibleFactors = factors.take(3).join(' ');
    return 'Risk score is ${report.riskScoreLabel}. Main factor(s): $visibleFactors';
  }

  String _getTopAppName(UsageReport report) {
    return report.topUsedApp?.displayName ?? 'The most used app';
  }

  bool _hasLateNightUse(UsageReport report) {
    final source = '${report.recommendationMessage} ${report.riskFactorSummary}'
        .toLowerCase();

    return source.contains('late-night') ||
        source.contains('late night') ||
        source.contains('bedtime') ||
        source.contains('10:00 pm') ||
        source.contains('rest hours');
  }

  bool _hasRiskyAppUse(UsageReport report) {
    final source = '${report.recommendationMessage} ${report.riskFactorSummary}'
        .toLowerCase();

    return source.contains('social media') ||
        source.contains('gaming') ||
        source.contains('video') ||
        source.contains('single-app') ||
        source.contains('single app') ||
        source.contains('long session');
  }
}

