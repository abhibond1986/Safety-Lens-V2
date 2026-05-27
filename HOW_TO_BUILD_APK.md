# 🎯 How to Build Safety Lens APK — Bulletproof Guide

**For:** Abhishek Kumar  
**Goal:** Get APK installed on your Android phone  
**Time required:** 25-30 minutes  
**Cost:** ₹0 (completely free)

---

## ✅ Before You Start — Checklist

You need:
- [ ] A computer with internet (Windows/Mac/Linux any)
- [ ] A Google account (any Gmail)
- [ ] An Android phone for testing
- [ ] About 30 minutes

You do NOT need:
- ❌ Flutter installed on your computer
- ❌ Android Studio
- ❌ Programming knowledge
- ❌ Paid services

---

## 📋 Method: GitHub Actions (FREE, Cloud-based)

GitHub will build the APK for you on their servers — you just upload the code.

---

### STEP 1 — Create GitHub Account (skip if you have one)

1. Go to https://github.com/signup
2. Sign up with your email (use abhibond1984 username if not taken)
3. Verify your email
4. ✅ Done

---

### STEP 2 — Create a Fresh Repository

> **IMPORTANT:** Start with a clean repo. If you have an old `Safety-Lens` repo from previous attempts, **delete it first** to avoid confusion.

**To delete old repo (if exists):**
1. Go to https://github.com/abhibond1984/Safety-Lens (or whatever your old repo)
2. Click **Settings** (top right of repo page)
3. Scroll to bottom → **Danger Zone**
4. Click **Delete this repository**
5. Type the repo name to confirm

**To create new repo:**
1. Click the **+** icon top-right → **New repository**
2. Repository name: `Safety-Lens`
3. Description: `SAIL Safety Lens — AI-powered industrial safety`
4. Visibility: **Public** (required for free GitHub Actions)
5. ✅ Check **Add a README file**
6. Click **Create repository**

---

### STEP 3 — Upload the Code

**This is where previous attempts failed. Follow exactly:**

1. **Extract the zip first** on your computer
   - Right-click `safety_lens_v17.zip` → Extract All
   - You'll get a folder called `safety_lens_clean`
   - **Open this folder** — you should see `lib`, `android`, `assets`, `pubspec.yaml`, etc.

2. **Go to your GitHub repo** in browser
   - https://github.com/YOUR_USERNAME/Safety-Lens
   - You'll see the README file you created

3. **Click "Add file" → "Upload files"**

4. **Drag the contents of `safety_lens_clean` folder** (NOT the folder itself)
   - Open the `safety_lens_clean` folder on your computer
   - Select ALL items inside (Ctrl+A or Cmd+A)
   - **Drag them onto the GitHub upload area**
   - You should see: `android/`, `ios/`, `lib/`, `assets/`, `pubspec.yaml`, etc. being uploaded
   - Wait for all files to finish uploading (progress bar at top)

5. **At the bottom of the page:**
   - Commit message: `Initial v17 upload`
   - Click **"Commit changes"**

> 🔴 **CRITICAL:** Make sure `.github/workflows/build-apk.yml` is uploaded. This file is hidden because of the dot. To upload hidden files:
> - On Mac: Press `Cmd + Shift + .` to show hidden files
> - On Windows: View → Show → Hidden items

---

### STEP 4 — Verify Files Are All Uploaded

On your repo's main page, you should see this structure:
```
├── .github/
├── android/
├── assets/
├── ios/
├── lib/
├── test/
├── .gitignore
├── DEPLOYMENT.md
├── HOW_TO_BUILD_APK.md  ← this file
├── README.md
├── codemagic.yaml
└── pubspec.yaml
```

**Click on `.github/workflows/` and verify `build-apk.yml` is there.**

If `.github` folder is missing → re-upload it.

---

### STEP 5 — Add Your Gemini API Key (Optional)

If you want AI hazard analysis to work in the APK, add your API key:

1. In your repo, navigate to `lib/services/gemini_vision.dart`
2. Click the **pencil icon** (edit)
3. Find line ~14: `static const String _apiKey = 'YOUR_GEMINI_API_KEY_HERE';`
4. Replace with your key:
   ```
   static const String _apiKey = 'AIzaSy...your_actual_key_here...';
   ```
5. Click **"Commit changes"** at the top right

**Don't have a Gemini key?** Get one free at https://aistudio.google.com/apikey

**Skip this step?** App still works — AI scan will show offline analysis instead.

---

### STEP 6 — Trigger the Build

The build should start **automatically** when you upload files.

1. Click the **"Actions"** tab on your repo (top menu)
2. You should see a workflow run named **"Initial v17 upload"** with a yellow/orange dot (running)
3. Wait **15-20 minutes** for it to complete
4. Once done, you'll see a green ✓ checkmark

**If you see a red ✗ (failed):**
- Click on the failed run
- Click "build" job
- Click the red step to see error
- Share screenshot with me — I'll fix it

**If no workflow appears:**
- Click **"Actions"** tab
- Click **"Build Safety Lens APK"** in the left sidebar
- Click **"Run workflow"** dropdown (right side)
- Click green **"Run workflow"** button
- Wait 15-20 minutes

---

### STEP 7 — Download the APK

1. Once build is green ✓, click on the workflow run
2. Scroll down to **"Artifacts"** section at the bottom
3. Click **"safety-lens-apk"** to download
4. You get a ZIP file → extract it
5. Inside: `app-debug.apk` — this is your installable APK file!

---

### STEP 8 — Install on Your Android Phone

1. **Transfer `app-debug.apk` to your phone:**
   - Email it to yourself
   - Or use Google Drive
   - Or USB cable

2. **On your phone:**
   - Tap the APK file
   - Android will say "For your security, your phone is not allowed to install unknown apps"
   - Tap **Settings** → toggle **Allow from this source** ON
   - Tap back → tap **Install**

3. **Open the app:**
   - Find "Safety Lens" in your app drawer
   - Tap to open

4. **First-time permissions:**
   - Allow Camera
   - Allow Microphone (for voice input)
   - Allow Storage

5. **Login:**
   - Username: `abhishek.kumar`
   - Password: `demo`
   - Or click **Register** to create your own

---

## 🎉 You Should Now See:

✅ Splash screen with SAIL logo and "Safety Lens" branding  
✅ Login screen with Sign In / Register toggle  
✅ Home screen showing "Abhishek Kumar — AGM · SAIL Safety Organisation"  
✅ Plant-wise stats table  
✅ AI Scan with camera/gallery picker  
✅ Near Miss form with voice input mic  
✅ Ask AI chatbot  
✅ Reports tabulated list

---

## 🐛 Troubleshooting

### Build fails with "Plugin not found"
**Cause:** Cached old dependencies  
**Fix:** Go to Actions → Run workflow manually (clean run)

### Build fails with "MainActivity not found"
**Cause:** Missing kotlin file  
**Fix:** Verify `android/app/src/main/kotlin/com/sail/safety/MainActivity.kt` is uploaded

### Build succeeds but APK won't install
**Cause:** Phone storage full, or APK corrupted in transfer  
**Fix:** Free up 100 MB, re-download APK fresh

### App crashes on launch
**Cause:** Old SharedPreferences from previous install  
**Fix:** On phone: Settings → Apps → Safety Lens → Storage → Clear Data

### "Install blocked" error
**Cause:** Play Protect blocking unknown source  
**Fix:** Settings → Security → toggle "Play Protect" temporarily, install, then re-enable

### Camera doesn't open in AI Scan
**Cause:** Camera permission not granted  
**Fix:** Settings → Apps → Safety Lens → Permissions → enable Camera

### Voice input doesn't work
**Cause:** Microphone permission or Google Speech Services missing  
**Fix:**  
1. Settings → Apps → Safety Lens → Permissions → enable Microphone  
2. Install Google app from Play Store if missing

---

## 📞 If You Get Stuck

Share these with me:

1. Screenshot of the failed step
2. Click "View raw logs" on GitHub → copy the last 50 lines
3. Tell me which step number you're at

I'll diagnose and fix.

---

## 🔄 What's Next (After APK Works)

Once you have the APK installed and working:

1. ✅ **Test all features** on real phone (5-10 minutes)
2. ✅ **Show team** for initial feedback
3. → **Then we move to Firebase backend** (cloud sync)

---

**Honest reminder:** This is the **5th time** we're trying to build this APK. The configuration above has been verified clean. If this still fails, the error message in GitHub Actions will tell us EXACTLY what's wrong — share it with me and I'll fix it.
