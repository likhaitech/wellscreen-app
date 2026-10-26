import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Returns the selected daily allowance in minutes, or null if dismissed.
/// This widget does not save a rule or enforce an app restriction by itself.
Future<int?> showSetAppTimeLimitDialog({
  required BuildContext context,
  required String appName,
  required int usageTodayMs,
  int? initialLimitMinutes,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _SetAppTimeLimitSheet(
      appName: appName,
      usageTodayMs: usageTodayMs,
      initialLimitMinutes: initialLimitMinutes,
    ),
  );
}

class _SetAppTimeLimitSheet extends StatefulWidget {
  const _SetAppTimeLimitSheet({
    required this.appName,
    required this.usageTodayMs,
    required this.initialLimitMinutes,
  });

  final String appName;
  final int usageTodayMs;
  final int? initialLimitMinutes;

  @override
  State<_SetAppTimeLimitSheet> createState() => _SetAppTimeLimitSheetState();
}

class _SetAppTimeLimitSheetState extends State<_SetAppTimeLimitSheet> {
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialLimitMinutes ?? 60).clamp(1, 1440).toInt();
    _hoursController = TextEditingController(text: '${initial ~/ 60}');
    _minutesController = TextEditingController(text: '${initial % 60}');
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  int? get _selectedMinutes {
    final hours = int.tryParse(_hoursController.text.trim());
    final minutes = int.tryParse(_minutesController.text.trim());
    if (hours == null || minutes == null || hours < 0 || minutes < 0 ||
        minutes > 59) {
      return null;
    }
    final total = hours * 60 + minutes;
    return total >= 1 && total <= 1440 ? total : null;
  }

  void _setPreset(int minutes) {
    _hoursController.text = '${minutes ~/ 60}';
    _minutesController.text = '${minutes % 60}';
    setState(() => _error = null);
  }

  void _save() {
    final minutes = _selectedMinutes;
    if (minutes == null) {
      setState(() => _error =
          'Enter a limit between 1 minute and 24 hours (0–59 minutes per hour).');
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  String _durationText(int minutes) {
    if (minutes <= 0) return '0m';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '${rest}m';
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedMinutes;
    final usedMs = widget.usageTodayMs < 0 ? 0 : widget.usageTodayMs;
    final usedMinutes = Duration(milliseconds: usedMs).inMinutes;
    final int? remaining = selected == null
        ? null
        : (selected - usedMinutes).clamp(0, 1440).toInt();
    final double ratio = selected == null
        ? 0.0
        : (usedMs / (selected * 60000)).clamp(0.0, 1.0).toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          6,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Set Time Limit',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    )),
                const SizedBox(height: 4),
                Text('${widget.appName} · Daily allowance',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 20),
                const Text('Quick options',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [30, 60, 120, 180].map((minutes) {
                    return ChoiceChip(
                      label: Text(_durationText(minutes)),
                      selected: selected == minutes,
                      selectedColor: AppColors.primaryLight,
                      labelStyle: TextStyle(
                        color: selected == minutes
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => _setPreset(minutes),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                const Text('Custom time limit',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hoursController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Hours',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _minutesController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Minutes',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Used today',
                              style: TextStyle(color: AppColors.textSecondary)),
                          Text(_durationText(usedMinutes),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Remaining allowance',
                              style: TextStyle(color: AppColors.textSecondary)),
                          Text(remaining == null ? '—' : _durationText(remaining),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          color: AppColors.primary,
                          backgroundColor: AppColors.track,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Save Limit'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
