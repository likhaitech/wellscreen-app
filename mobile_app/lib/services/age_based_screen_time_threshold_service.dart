class AgeBasedScreenTimeThreshold {
  const AgeBasedScreenTimeThreshold({
    required this.childAge,
    required this.ageGroupLabel,
    required this.dailyLimit,
    required this.warningLimit,
    required this.unhealthyLimit,
  });

  final int? childAge;
  final String ageGroupLabel;
  final Duration dailyLimit;
  final Duration warningLimit;
  final Duration unhealthyLimit;

  String get dailyLimitLabel => _formatDuration(dailyLimit);

  String get warningLimitLabel => _formatDuration(warningLimit);

  String get unhealthyLimitLabel => _formatDuration(unhealthyLimit);

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
}

class AgeBasedScreenTimeThresholdService {
  static const Duration defaultDailyLimit = Duration(hours: 3);
  static const Duration defaultWarningLimit = Duration(hours: 3);
  static const Duration defaultUnhealthyLimit = Duration(hours: 5);

  AgeBasedScreenTimeThreshold getThresholdForAge(int? childAge) {
    if (childAge == null || childAge <= 0) {
      return const AgeBasedScreenTimeThreshold(
        childAge: null,
        ageGroupLabel: 'Default age group',
        dailyLimit: defaultDailyLimit,
        warningLimit: defaultWarningLimit,
        unhealthyLimit: defaultUnhealthyLimit,
      );
    }

    if (childAge <= 6) {
      return const AgeBasedScreenTimeThreshold(
        childAge: 6,
        ageGroupLabel: 'Age 6 and below',
        dailyLimit: Duration(hours: 1),
        warningLimit: Duration(hours: 1),
        unhealthyLimit: Duration(hours: 2),
      );
    }

    if (childAge <= 12) {
      return const AgeBasedScreenTimeThreshold(
        childAge: 12,
        ageGroupLabel: 'Age 7 to 12',
        dailyLimit: Duration(hours: 2),
        warningLimit: Duration(hours: 2),
        unhealthyLimit: Duration(hours: 4),
      );
    }

    return const AgeBasedScreenTimeThreshold(
      childAge: 15,
      ageGroupLabel: 'Age 13 to 15',
      dailyLimit: Duration(hours: 3),
      warningLimit: Duration(hours: 3),
      unhealthyLimit: Duration(hours: 5),
    );
  }

  Duration getDailyLimitForAge(int? childAge) {
    return getThresholdForAge(childAge).dailyLimit;
  }

  String getThresholdDescription(int? childAge) {
    final threshold = getThresholdForAge(childAge);

    return '${threshold.ageGroupLabel}: recommended daily limit is ${threshold.dailyLimitLabel}.';
  }
}
