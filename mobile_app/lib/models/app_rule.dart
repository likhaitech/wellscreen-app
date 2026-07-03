import 'dart:convert';

class AppRule {
  final String appName;
  final String packageName;
  final bool monitorEnabled;
  final bool restrictEnabled;

  AppRule({
    required this.appName,
    required this.packageName,
    required this.monitorEnabled,
    required this.restrictEnabled,
  });

  AppRule copyWith({
    String? appName,
    String? packageName,
    bool? monitorEnabled,
    bool? restrictEnabled,
  }) {
    return AppRule(
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      monitorEnabled: monitorEnabled ?? this.monitorEnabled,
      restrictEnabled: restrictEnabled ?? this.restrictEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'appName': appName,
      'packageName': packageName,
      'monitorEnabled': monitorEnabled,
      'restrictEnabled': restrictEnabled,
    };
  }

  factory AppRule.fromMap(Map<String, dynamic> map) {
    return AppRule(
      appName: map['appName']?.toString() ?? '',
      packageName: map['packageName']?.toString() ?? '',
      monitorEnabled: map['monitorEnabled'] == true,
      restrictEnabled: map['restrictEnabled'] == true,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AppRule.fromJson(String source) {
    return AppRule.fromMap(jsonDecode(source));
  }
}