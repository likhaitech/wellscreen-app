# WellScreen mobile app

Flutter app for both the parent and the child side of WellScreen, plus the Android code (Kotlin) that enforces app and website blocking on the child's phone.

For what the project is and how to run, test and build it, see the [main README](../README.md).

Quick start:

```
flutter pub get
flutter run
```

You need `android/app/google-services.json` from the Firebase console first (it is git-ignored). Turn on Settings > Accessibility > WellScreen on the child device or blocking will not work.

Where things are:

- `lib/screens/` - parent and child screens
- `lib/services/` - usage tracking, rules sync, alerts, reports, ML scoring
- `lib/config/app_config.dart` - backend URL
- `android/app/src/main/kotlin/com/wellscreen/app/` - accessibility service, block screens, website blocker, SMS alerts
- `assets/` - the trained risk model and the harmful-site data bundled into the app
- `test/` - unit and widget tests
