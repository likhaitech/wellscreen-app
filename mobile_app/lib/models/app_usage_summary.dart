class AppUsageSummary {
  const AppUsageSummary({
    required this.packageName,
    required this.displayName,
    required this.usageDuration,
    this.lastTimeUsed,
});
  final String packageName;
  final String displayName;
  final Duration usageDuration;
  final DateTime? lastTimeUsed;

  String get usageLabel{
    final hours = usageDuration.inHours;
    final minutes = usageDuration.inMinutes.remainder(60);

    if (hours > 0){
      return '${hours}h ${minutes}m';
    }

    if (minutes > 0){
      return '${minutes}m';
    }
    return '${usageDuration.inSeconds}s';
  }

}