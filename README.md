# WellScreen

WellScreen is a parental-control and digital-wellbeing system for children's Android phones. A **parent app** and a **child app** (one Flutter codebase) are paired by a code or QR. The child device tracks screen time, enforces restrictions, and shares location; the parent sees live reports and receives alerts. A small **FastAPI backend** sends push notifications and powers an admin console, and two **machine-learning components** score usage risk and flag harmful sites.

Capstone project, BSIT, University of Cebu Lapu-Lapu and Mandaue. Team: Laresma, Jalang, Rosell, Cabalan. Adviser: Ms. Shiela Mae C. Saga.

## What it does

- Account creation, login, and parent-to-child device pairing (manual code or QR).
- Screen-time and per-app usage tracking from real Android usage stats, with a daily limit.
- Per-app restriction and blocking through an Android Accessibility Service, with a parent-approved Emergency Access override.
- Website blocking: when a supported browser shows a domain from the bundled harmful-site dataset (gambling, drugs, adult, dangerous material) or a parent-defined list, the child sees a "Website Blocked" screen.
- GPS location sharing with geofence alerts.
- Push notifications (Firebase Cloud Messaging via the backend) plus SMS backup alerts when a restricted app is blocked.
- Rule-based usage-pattern detection and a Random Forest risk classifier (trained on simulated data, see `ml/README.md`).
- Harmful-site category detection (lookup, keyword, and a TF-IDF classifier).
- PDF usage-report export, offline logging with automatic sync, and an admin console (users, settings, logs).

## Repository layout

| Folder | Contents |
| --- | --- |
| `mobile_app/` | Flutter app (Dart) and the Android native code (Kotlin) for enforcement |
| `backend/` | FastAPI server (push alerts, admin routes) and its pytest suite |
| `ml/` | Training scripts and outputs for the risk classifier and site-category classifier |
| `ml_models/` | Exported model assets |
| `data_cleaned/` | Cleaned site-category dataset |
| `firestore_rules_tests/` | Tests for `firestore.rules`, run against the Firestore emulator |
| `.github/workflows/` | CI: backend tests, Firestore rules tests, Flutter analyze/test and release APK |

## Architecture in short

- **Firebase** (project `wellscreen-58cb7`) provides Auth, Firestore, and Cloud Messaging.
- The **child app** reads the parent's rules from Firestore into local storage. `WellScreenAccessibilityService` (Kotlin) watches the foreground app and browser address bar and opens the block screen when a rule matches.
- The **backend** (`backend/`, deployed on Render's free tier) receives `POST /alerts/notify` from the app and sends the push. Because the free tier sleeps after 15 minutes idle, open `/health` a few minutes before a demo to wake it.

## Run the mobile app

Requirements: Flutter 3.44 or newer (Dart 3.12), Android Studio with an emulator or a physical Android phone.

1. Get `google-services.json` from the Firebase console and place it in `mobile_app/android/app/`. It is git-ignored and is never committed.
2. From `mobile_app/`:

```
flutter pub get
flutter run
```

3. On the child device, enable **Settings > Accessibility > WellScreen**. Blocking does not work until the service is on.

Build a release APK with `flutter build apk --release` (signing is configured through `mobile_app/android/key.properties`, also git-ignored).

## Run the backend

```
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload
```

It needs a Firebase service-account key; see `backend/DEPLOYMENT.md` for the Render setup and the required environment variable. The app points at the deployed URL in `mobile_app/lib/config/app_config.dart` (override with `--dart-define=WELLSCREEN_BACKEND_URL=...`).

## Run the tests

```
cd mobile_app && flutter analyze && flutter test
cd backend && pip install -r requirements-dev.txt && pytest tests/
cd firestore_rules_tests && npm install && npm test
```

The rules tests need the Firebase CLI installed and use `cp` in their `pretest` step, so on Windows run them from Git Bash or WSL. The three CI workflows in `.github/workflows/` run the same suites on every pull request.

## Honest limitations

- The risk classifier is trained on **simulated** data, not real children's behavior; it is a real, evaluated model but not validated in the field.
- Website blocking needs a supported browser (Chrome, Chrome Beta, Firefox, Samsung Internet, Opera, Edge, DuckDuckGo, and the stock Android browser). Other browsers are not detected.
- Push and SMS delivery depend on the backend being reachable and on the SMS permission and a parent phone number being set.
- GPS accuracy and sync success rates are not yet formally measured; they are listed as future technical-evaluation work.
