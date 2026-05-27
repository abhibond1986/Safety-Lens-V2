# Safety Lens v17 — Deployment Guide

**For:** Abhishek Kumar, AGM, SAIL Safety Organisation  
**Repo:** https://github.com/abhibond1984/Safety-Lens

---

## What's in v17

| Feature | Status |
|---------|--------|
| Official SAIL logo (blue diamond + सेल SAIL) | ✅ In `assets/images/sail_logo.png` |
| Profile: Abhishek Kumar, AGM, SAIL Safety Organisation | ✅ Pre-filled in registration |
| Login + Register toggle screens | ✅ |
| Bold artistic "Safety Lens" branding | ✅ Cyan-blue + amber-red gradient |
| Safety motivational quotes (8 rotating) | ✅ Dashboard |
| Plant-wise stats table (BSP/DSP/RSP/BSL/ISP) | ✅ Dashboard |
| 4-column hazard table (Hazard / Section / Criticality / Recommendation) | ✅ AI Scan |
| Penalty mentions removed | ✅ |
| Full Near Miss form (3 steps, all fields) | ✅ Voice input for location |
| Safety AI chatbot (dedicated tab + FAB on every screen) | ✅ |
| Tabulated Reports with severity badges | ✅ |
| Light/Dark theme toggle | ✅ |
| PDF export | ✅ |
| Real camera/gallery picker | ✅ image_picker package |

---

## Step 1: Add your Gemini API key

Open `lib/services/gemini_vision.dart` line 14 and replace:

```dart
static const String _apiKey = 'YOUR_GEMINI_API_KEY_HERE';
```

with your actual Gemini API key:

```dart
static const String _apiKey = 'AIzaSy...your-key-here...';
```

Get a free key from: https://aistudio.google.com/apikey

---

## Step 2: Upload to GitHub

1. Go to https://github.com/abhibond1984/Safety-Lens
2. If you have existing files there, **delete them first** (or use a new branch)
3. Upload everything in this zip:
   - Drag the entire contents of `safety_lens_clean/` into the GitHub web upload
   - Make sure `.github/workflows/build-apk.yml` is preserved (this builds the APK)
4. Commit the changes

---

## Step 3: GitHub Actions builds the APK

After you push:
1. Go to the **Actions** tab in your repo
2. Wait ~15-20 minutes for the build to complete
3. Click the latest workflow run → scroll to **Artifacts**
4. Download `safety-lens-apk`
5. Extract → install `app-release.apk` on your Android phone

---

## Default login credentials

After installing:
- **Username:** `abhishek.kumar`
- **Password:** `demo`
- Or click **Register** to create a fresh account

---

## File checklist

```
safety_lens_clean/
├── .github/workflows/build-apk.yml   ← Builds APK automatically
├── android/                          ← Android platform code (permissions ready)
├── ios/                              ← iOS platform stubs
├── assets/images/sail_logo.png       ← Official SAIL logo
├── lib/
│   ├── main.dart                     ← App entry + branding
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── login_screen.dart         ← Login + Register toggle
│   │   ├── home_screen.dart          ← Bottom nav + FAB
│   │   ├── dashboard_tab.dart        ← Quote + plant stats
│   │   ├── ai_scan_tab.dart          ← 4-column hazard table
│   │   ├── near_miss_tab.dart        ← Full 3-step form
│   │   ├── chat_tab.dart             ← Safety AI assistant
│   │   └── reports_tab.dart          ← Tabulated list + PDF
│   └── services/
│       ├── local_db.dart             ← User auth + incidents + plant stats
│       ├── local_ai.dart             ← Offline AI fallback + chat KB
│       ├── gemini_vision.dart        ← ⚠️ ADD YOUR API KEY HERE (line 14)
│       └── pdf_export.dart           ← PDF generation
├── pubspec.yaml                      ← Dependencies (all present)
└── DEPLOYMENT.md                     ← This file
```

---

## Important honest notes

### AI image analysis accuracy
- The accuracy of hazard detection depends on **Google Gemini Vision** capabilities
- For best results: clear, well-lit workplace photos
- AI will sometimes miss subtle hazards or misclassify ambiguous scenes
- This is a vision-AI limitation; consider Gemini Pro 2.5 for higher accuracy (~$0.001/image)

### Security caveats (for production)
- Passwords currently stored in plaintext SharedPreferences — fine for demo, **encrypt for production**
- API key is hardcoded — for production, move to environment variable or backend proxy
- No cloud sync — each device has its own local data

### What to verify after install
1. Login screen shows new SAIL logo + "Safety Lens" branding
2. Home screen header has SAIL logo + your name "Abhishek Kumar"
3. Plant-wise stats table shows 5 plants
4. AI Scan → upload photo → see 4-column hazard table
5. Near Miss → all 3 steps visible with voice mic
6. Ask AI tab → chat works with suggested questions
7. Reports → tabulated list with severity badges
8. Purple chat FAB visible on every screen except chat itself

---

## Troubleshooting

**Build fails on GitHub Actions:**
- Check `flutter-version: 3.19.6` in workflow
- Make sure `pubspec.yaml` wasn't modified during upload

**APK installs but crashes on launch:**
- Check Android version is 6.0+ (API 23)
- Grant Camera, Microphone, Storage permissions when prompted

**AI Scan returns empty result:**
- Check you added your Gemini API key in `gemini_vision.dart` line 14
- Check internet connectivity
- Falls back to offline LocalAI if Gemini fails

**Voice input doesn't work:**
- Grant Microphone permission in Android settings
- Ensure Google Speech Services is installed

---

## Support
This app was built iteratively. For changes, modify the relevant `lib/screens/*.dart` file.

**Version:** 1.0.0+17 (May 2026)  
**Built with:** Flutter 3.19, Dart 3.0+
