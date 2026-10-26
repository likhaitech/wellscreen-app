/// A guardian's daily per-app allowance for a single paired child profile.
/// This is distinct from AppRule.restrictEnabled (a permanent restriction).
class AppTimeLimit {
  const AppTimeLimit({
    required this.packageName,
    required this.appName,
    required this.limitMinutes,
  });

  final String packageName;
  final String appName;
  final int limitMinutes;

  int get limitMilliseconds => limitMinutes * 60 * 1000;

  /// Non-negative remaining allowance; never turn a missing reading into
  /// fabricated usage in callers. Provide actual observed milliseconds.
  int remainingMilliseconds(int usedMilliseconds) {
    final safeUsed = usedMilliseconds < 0 ? 0 : usedMilliseconds;
    final remaining = limitMilliseconds - safeUsed;
    return remaining > 0 ? remaining : 0;
  }

  bool limitReached(int usedMilliseconds) =>
      usedMilliseconds >= limitMilliseconds;

  Map<String, dynamic> toMap() => {
    'packageName': packageName,
    'appName': appName,
    'limitMinutes': limitMinutes,
  };

  factory AppTimeLimit.fromMap(Map<String, dynamic> map) {
    final rawMinutes = map['limitMinutes'];
    final minutes = rawMinutes is num ? rawMinutes.toInt() : 0;
    if (minutes < 1 || minutes > 1440) {
      throw const FormatException('Invalid daily app limit');
    }
    final package = (map['packageName'] ?? '').toString().trim();
    if (package.isEmpty) {
      throw const FormatException('Missing Android package name');
    }
    return AppTimeLimit(
      packageName: package,
      appName: (map['appName'] ?? package).toString(),
      limitMinutes: minutes,
    );
  }
}
