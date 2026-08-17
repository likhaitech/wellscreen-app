import 'package:connectivity_plus/connectivity_plus.dart';

/// Wraps connectivity_plus (verified current API as of the 7.x series:
/// checkConnectivity()/onConnectivityChanged both deal in a `List` of
/// `ConnectivityResult`, not a single result, since a device can have more
/// than one active connection type at once) so the rest of the app only
/// has to ask "am I online" as a plain bool.
///
/// This exists to fix a real, documented bug class, not just add a
/// nice-to-have: cloud_firestore's set()/update() Futures hang indefinitely
/// when the device is offline, with persistence enabled, and never throw -
/// see firebase/flutterfire#17643. Before this, child_home_screen.dart's
/// syncUsageReport()/shareCurrentLocation() had no way to know they were
/// offline; a sync attempted while offline would spin the loading indicator
/// forever with no error and no automatic retry once connectivity returned.
class SyncStatusService {
  final Connectivity _connectivity = Connectivity();

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _hasRealConnection(results);
  }

  /// Emits true/false only on actual online<->offline transitions (not on
  /// every connectivity type change, e.g. wifi to mobile data while already
  /// online), so listeners can auto-retry a pending sync exactly once per
  /// reconnect instead of repeatedly.
  Stream<bool> get onlineStatusChanges {
    bool? lastStatus;

    return _connectivity.onConnectivityChanged
        .map(_hasRealConnection)
        .where((isOnline) {
      if (isOnline == lastStatus) return false;
      lastStatus = isOnline;
      return true;
    });
  }

  bool _hasRealConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }
}
