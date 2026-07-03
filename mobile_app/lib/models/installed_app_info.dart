class InstalledAppInfo {
  final String appName;
  final String packageName;

  InstalledAppInfo({
    required this.appName,
    required this.packageName,
  });

  factory InstalledAppInfo.fromMap(Map<dynamic, dynamic> map) {
    return InstalledAppInfo(
      appName: map['appName']?.toString() ?? '',
      packageName: map['packageName']?.toString() ?? '',
    );
  }
}