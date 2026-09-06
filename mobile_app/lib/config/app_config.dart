/// Central place for settings that differ between local development and a
/// real deployment - right now just the backend's base URL.
class AppConfig {
  /// Base URL of the WellScreen FastAPI backend (see backend/).
  ///
  /// For local testing on the Android EMULATOR only, you can run the
  /// backend on your own machine (`uvicorn app.main:app --reload` from
  /// inside backend/) and temporarily set this to 'http://10.0.2.2:8000' -
  /// that special address only works from the emulator, never a real phone.
  ///
  /// For push notifications (and the SMS/admin features that already talk
  /// to this backend) to work on a real device, or for the panel
  /// demo/defense, the backend needs to be deployed somewhere reachable and
  /// this needs to point at that real URL - see backend/DEPLOYMENT.md.
  ///
  /// Deployed to Render's free tier (see backend/DEPLOYMENT.md) - free
  /// instances spin down after 15 minutes idle and take ~1 minute to wake
  /// back up, so hit /health a few minutes before a live demo.
  static const String backendBaseUrl = String.fromEnvironment(
    'WELLSCREEN_BACKEND_URL',
    defaultValue: 'https://wellscreen-app.onrender.com',
  );
}
