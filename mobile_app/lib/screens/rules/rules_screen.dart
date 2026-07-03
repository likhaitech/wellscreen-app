import 'package:flutter/material.dart';

import '../../models/app_rule.dart';
import '../../models/installed_app_info.dart';
import '../../services/android_app_service.dart';
import '../../services/app_rules_service.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final AndroidAppService _androidAppService = AndroidAppService();
  final AppRulesService _rulesService = AppRulesService();

  bool _loading = true;
  bool _saving = false;

  String _searchText = '';

  List<InstalledAppInfo> _installedApps = [];
  Map<String, AppRule> _rulesByPackage = {};

  @override
  void initState() {
    super.initState();
    _loadAppsAndRules();
  }

  Future<void> _loadAppsAndRules() async {
    setState(() {
      _loading = true;
    });

    final apps = await _androidAppService.getInstalledApps();
    final rules = await _rulesService.getRules();

    setState(() {
      _installedApps = apps;
      _rulesByPackage = {
        for (final rule in rules) rule.packageName: rule,
      };
      _loading = false;
    });
  }

  Future<void> _saveAllRules() async {
    setState(() {
      _saving = true;
    });

    final rules = _rulesByPackage.values
        .where((rule) => rule.monitorEnabled || rule.restrictEnabled)
        .toList();

    await _rulesService.saveRules(rules);

    setState(() {
      _saving = false;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rules saved successfully.'),
      ),
    );
  }

  void _updateMonitor(InstalledAppInfo app, bool value) {
    final existing = _rulesByPackage[app.packageName];

    final updated = AppRule(
      appName: app.appName,
      packageName: app.packageName,
      monitorEnabled: value,
      restrictEnabled: existing?.restrictEnabled ?? false,
    );

    setState(() {
      if (!updated.monitorEnabled && !updated.restrictEnabled) {
        _rulesByPackage.remove(app.packageName);
      } else {
        _rulesByPackage[app.packageName] = updated;
      }
    });
  }

  void _updateRestrict(InstalledAppInfo app, bool value) {
    final existing = _rulesByPackage[app.packageName];

    final updated = AppRule(
      appName: app.appName,
      packageName: app.packageName,
      monitorEnabled: existing?.monitorEnabled ?? true,
      restrictEnabled: value,
    );

    setState(() {
      if (!updated.monitorEnabled && !updated.restrictEnabled) {
        _rulesByPackage.remove(app.packageName);
      } else {
        _rulesByPackage[app.packageName] = updated;
      }
    });
  }

  Future<void> _clearRules() async {
    await _rulesService.clearRules();

    setState(() {
      _rulesByPackage.clear();
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All rules cleared.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monitoredRules = _rulesByPackage.values
        .where((rule) => rule.monitorEnabled)
        .toList()
      ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    final restrictedRules = _rulesByPackage.values
        .where((rule) => rule.restrictEnabled)
        .toList()
      ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    final filteredApps = _installedApps.where((app) {
      final query = _searchText.toLowerCase().trim();

      if (query.isEmpty) {
        return true;
      }

      return app.appName.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FB),
      appBar: AppBar(
        title: const Text('Rules'),
        backgroundColor: const Color(0xFFF8F4FB),
        surfaceTintColor: const Color(0xFFF8F4FB),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadAppsAndRules,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: _saving ? null : _saveAllRules,
            child: _saving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Text(
              'SAVE',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _PermissionCard(
            monitoredCount: monitoredRules.length,
            restrictedCount: restrictedRules.length,
            onOpenAccessibility:
            _androidAppService.openAccessibilitySettings,
            onOpenUsageAccess:
            _androidAppService.openUsageAccessSettings,
            onClearRules: _clearRules,
          ),
          _ActiveRulesCard(
            monitoredRules: monitoredRules,
            restrictedRules: restrictedRules,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TextField(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search apps',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchText = value;
                });
              },
            ),
          ),
          Expanded(
            child: filteredApps.isEmpty
                ? const Center(
              child: Text('No apps found.'),
            )
                : ListView.separated(
              padding: const EdgeInsets.only(bottom: 18),
              itemCount: filteredApps.length,
              separatorBuilder: (context, index) =>
              const Divider(height: 1),
              itemBuilder: (context, index) {
                final app = filteredApps[index];
                final rule = _rulesByPackage[app.packageName];

                return _AppRuleRow(
                  app: app,
                  monitorEnabled: rule?.monitorEnabled ?? false,
                  restrictEnabled: rule?.restrictEnabled ?? false,
                  onMonitorChanged: (value) {
                    _updateMonitor(app, value);
                  },
                  onRestrictChanged: (value) {
                    _updateRestrict(app, value);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final int monitoredCount;
  final int restrictedCount;
  final VoidCallback onOpenAccessibility;
  final VoidCallback onOpenUsageAccess;
  final VoidCallback onClearRules;

  const _PermissionCard({
    required this.monitoredCount,
    required this.restrictedCount,
    required this.onOpenAccessibility,
    required this.onOpenUsageAccess,
    required this.onClearRules,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF6EFFA),
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'App Rules Control',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CountBadge(
                    label: 'Monitored',
                    count: monitoredCount,
                    icon: Icons.visibility_rounded,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountBadge(
                    label: 'Restricted',
                    count: restrictedCount,
                    icon: Icons.block_rounded,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'For demo: enable WellScreen in Accessibility Settings. This allows the child device to detect restricted apps when opened.',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onOpenAccessibility,
                    child: const Text(
                      'Accessibility',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onOpenUsageAccess,
                    child: const Text(
                      'Usage Access',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onClearRules,
                icon: const Icon(Icons.delete_outline),
                label: const Text(
                  'Clear rules',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _CountBadge({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '$count $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveRulesCard extends StatelessWidget {
  final List<AppRule> monitoredRules;
  final List<AppRule> restrictedRules;

  const _ActiveRulesCard({
    required this.monitoredRules,
    required this.restrictedRules,
  });

  @override
  Widget build(BuildContext context) {
    final hasRules = monitoredRules.isNotEmpty || restrictedRules.isNotEmpty;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ExpansionTile(
        initiallyExpanded: hasRules,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: const Icon(
          Icons.rule_folder_rounded,
          color: Color(0xFF5B2BBF),
        ),
        title: const Text(
          'Active App Rules',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        subtitle: Text(
          hasRules
              ? 'View monitored and restricted apps'
              : 'No apps selected yet',
          style: const TextStyle(color: Color(0xFF4B5563)),
        ),
        children: [
          if (!hasRules)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Turn on Monitor or Restrict below to add app rules.',
                style: TextStyle(color: Color(0xFF4B5563)),
              ),
            ),
          if (monitoredRules.isNotEmpty) ...[
            _RuleGroup(
              title: 'Monitored Apps',
              icon: Icons.visibility_rounded,
              color: Color(0xFF2563EB),
              rules: monitoredRules,
            ),
            const SizedBox(height: 12),
          ],
          if (restrictedRules.isNotEmpty)
            _RuleGroup(
              title: 'Restricted Apps',
              icon: Icons.block_rounded,
              color: Color(0xFFDC2626),
              rules: restrictedRules,
            ),
        ],
      ),
    );
  }
}

class _RuleGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<AppRule> rules;

  const _RuleGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.rules,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: rules.map((rule) {
            return Chip(
              avatar: CircleAvatar(
                backgroundColor: color,
                child: Text(
                  rule.appName.isNotEmpty ? rule.appName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              label: Text(
                rule.appName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
              backgroundColor: color.withValues(alpha: 0.08),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _AppRuleRow extends StatelessWidget {
  final InstalledAppInfo app;
  final bool monitorEnabled;
  final bool restrictEnabled;
  final ValueChanged<bool> onMonitorChanged;
  final ValueChanged<bool> onRestrictChanged;

  const _AppRuleRow({
    required this.app,
    required this.monitorEnabled,
    required this.restrictEnabled,
    required this.onMonitorChanged,
    required this.onRestrictChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE9D5FF),
            child: Text(
              app.appName.isNotEmpty ? app.appName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Color(0xFF5B2BBF),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CompactRuleSwitch(
            label: 'Monitor',
            value: monitorEnabled,
            onChanged: onMonitorChanged,
          ),
          const SizedBox(width: 6),
          _CompactRuleSwitch(
            label: 'Restrict',
            value: restrictEnabled,
            onChanged: onRestrictChanged,
          ),
        ],
      ),
    );
  }
}

class _CompactRuleSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactRuleSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 2),
          Transform.scale(
            scale: 0.72,
            child: Switch(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
