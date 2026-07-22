import 'package:flutter/services.dart';

class NativeRestrictionRulesService {
  const NativeRestrictionRulesService();

  static const MethodChannel _channel = MethodChannel(
    'com.wellscreen.app/restriction_rules',
  );

  Future<void> saveRules({
    required int limitMinutes,
    required bool appBlocking,
    required bool focusMode,
    required bool cooldownTimer,
    required bool scheduledLock,
    required bool categoryRestriction,
    required bool emergencyAccess,
  }) async {
    await _channel.invokeMethod<void>('saveRestrictionRules', {
      'limitMinutes': limitMinutes,
      'appBlocking': appBlocking,
      'focusMode': focusMode,
      'cooldownTimer': cooldownTimer,
      'scheduledLock': scheduledLock,
      'categoryRestriction': categoryRestriction,
      'emergencyAccess': emergencyAccess,
    });
  }

  Future<void> saveEmergencyAccessState({
    required bool isApproved,
    required DateTime? approvedUntil,
  }) async {
    await _channel.invokeMethod<void>('saveEmergencyAccessState', {
      'emergencyAccessApproved': isApproved,
      'emergencyAccessApprovedUntilMillis':
          approvedUntil?.millisecondsSinceEpoch ?? 0,
    });
  }
}
