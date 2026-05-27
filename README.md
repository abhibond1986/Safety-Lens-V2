# Safety Lens

AI-Powered Industrial Safety Management by SAIL (Steel Authority of India Limited)

## Features

- **100% Offline** — No internet, no API keys, no cloud required
- AI Image Analysis (PPE detection, hazard identification)
- Near Miss Reporting with WSA 13 classification
- Safety Rules AI Chat
- Reports & Analytics
- Inspection Management

## Building the APK

### Option 1: GitHub Actions (Easiest)

1. Push this code to a GitHub repository
2. Go to Actions tab
3. Workflow runs automatically
4. Download APK from Artifacts

### Option 2: Local Build

```bash
flutter pub get
flutter build apk --debug
# APK output: build/app/outputs/flutter-apk/app-debug.apk
```

## Login

- Employee ID: `demo`
- Password: `demo`

Or any non-empty credentials work in demo mode.

## Tech Stack

- Flutter 3.22
- Material Design 3
- Local storage via SharedPreferences
- No Firebase, no external APIs
