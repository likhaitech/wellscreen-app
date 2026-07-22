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
    bool smsBackupAlerts = false,
    String guardianPhoneNumber = '',
  }) async {
    await _channel.invokeMethod<void>('saveRestrictionRules', {
      'limitMinutes': limitMinutes,
      'appBlocking': appBlocking,
      'focusMode': focusMode,
      'cooldownTimer': cooldownTimer,
      'scheduledLock': scheduledLock,
      'categoryRestriction': categoryRestriction,
      'emergencyAccess': emergencyAccess,
      'smsBackupAlerts': smsBackupAlerts,
      'guardianPhoneNumber': guardianPhoneNumber,
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

  Future<void> saveSmsBackupAlertSettings({
    required bool enabled,
    required String guardianPhoneNumber,
  }) async {
    await _channel.invokeMethod<void>('saveSmsBackupAlertSettings', {
      'smsBackupAlertsEnabled': enabled,
      'guardianPhoneNumber': guardianPhoneNumber,
    });
  }

  Future<bool> isSmsPermissionGranted() async {
    final result = await _channel.invokeMethod<bool>('isSmsPermissionGranted');
    return result ?? false;
  }

  Future<void> requestSmsPermission() async {
    await _channel.invokeMethod<void>('requestSmsPermission');
  }
}
