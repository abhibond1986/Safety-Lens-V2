# 🌐 How to Deploy Safety Lens as a Web App (PWA)

**For:** Abhishek Kumar  
**Goal:** Get Safety Lens running on your iPhone (or any device) — completely FREE  
**Time required:** 20-30 minutes  
**Cost:** ₹0 forever  
**Devices supported:** iPhone, Android, iPad, any browser

---

## 🎯 What You Get

Once deployed, you'll have:
- ✅ A **public URL** like `https://abhibond1984.github.io/Safety-Lens/`
- ✅ Works in **iPhone Safari**
- ✅ Works in **Android Chrome**
- ✅ Can be **"Added to Home Screen"** — looks like a native app
- ✅ **No App Store / Play Store** needed
- ✅ **Auto-updates** — push code, everyone sees latest version
- ✅ **No paid Apple Developer account** needed
- ✅ **No paid Google Play account** needed

## ⚠️ Limitations (Honest)

What works:
- ✅ Camera (takes photos with browser camera API)
- ✅ Gallery (file picker)
- ✅ Login/Register
- ✅ AI hazard analysis (with Gemini API key)
- ✅ Near Miss reporting (full form)
- ✅ Safety AI chatbot
- ✅ Reports tabulated list

What doesn't work on web:
- ❌ **Voice input on iPhone** (Apple Safari restriction — type instead)
- ❌ **Push notifications on iPhone** (Apple restriction — Android works)
- ❌ **PDF export from web** (use mobile app version for PDF)
- ❌ **Full offline mode** (needs internet to load first time)

---

## 📋 Step-by-Step Deployment

### STEP 1 — Create GitHub Account (skip if you have one)

Already have one? Skip to Step 2.

1. Go to https://github.com/signup
2. Sign up with email
3. Verify email
4. ✅ Done

---

### STEP 2 — Create Fresh Repository

If you have an old `Safety-Lens` repo, **delete it first** (Settings → Danger Zone → Delete).

**Create new:**
1. Click **+** icon top-right → **New repository**
2. Repository name: `Safety-Lens` (exactly this name — important for URL)
3. Description: `SAIL Safety Lens — AI-powered industrial safety`
4. Visibility: **Public** (required for free GitHub Pages)
5. ✅ Check **Add a README file**
6. Click **Create repository**

---

### STEP 3 — Enable GitHub Pages

This is what makes your app accessible via a URL.

1. In your new repo, click **Settings** (top menu)
2. In left sidebar, click **Pages**
3. Under "Source", select **GitHub Actions**
4. ✅ Done (no save button needed)

---

### STEP 4 — Upload the Code

1. **Extract `safety_lens_v17.zip`** on your computer
   - You'll get a folder called `safety_lens_clean`

2. **Go to your repo** on GitHub

3. **Click "Add file" → "Upload files"**

4. **Drag the contents** of `safety_lens_clean` folder (NOT the folder itself)
   - Open folder, select all files with Ctrl+A (Cmd+A on Mac)
   - Drag to GitHub
   - Wait for upload (progress bar at top)

> 🔴 **IMPORTANT:** Hidden `.github` folder must upload too.  
> Mac: Press `Cmd + Shift + .` to show hidden files  
> Windows: View → Show → Hidden items

5. **At the bottom:**
   - Commit message: `Initial v17 web deployment`
   - Click **"Commit changes"**

---

### STEP 5 — Add Your Gemini API Key (Optional but Recommended)

Without API key, AI analysis shows demo data. With key, real Gemini analysis works.

1. Get free key: https://aistudio.google.com/apikey
2. In your repo, navigate to `lib/services/gemini_vision.dart`
3. Click pencil icon (edit)
4. Line 14: Replace `'YOUR_GEMINI_API_KEY_HERE'` with `'AIzaSy...your-key...'`
5. Click **Commit changes** at top right

---

### STEP 6 — Build Triggers Automatically

When you commit, GitHub Actions automatically:
1. Builds the web app (~5-8 minutes)
2. Deploys to GitHub Pages (~1 minute)

**Watch progress:**
1. Click **Actions** tab in your repo
2. You'll see a workflow run with yellow dot (running)
3. Wait for green ✓ (both "build" and "deploy" jobs complete)

**If you see red ✗ (failed):**
- Click failed run → "build" job → red step
- Share screenshot with me
- I'll diagnose

---

### STEP 7 — Find Your URL

Once deployment finishes (green ✓):

1. Go to repo → **Settings** → **Pages**
2. You'll see at top:
   > **Your site is live at:**  
   > `https://abhibond1984.github.io/Safety-Lens/`

Open this URL in any browser — you should see Safety Lens load!

---

### STEP 8 — Install on iPhone (Add to Home Screen)

This is the magic — your web app becomes a native-looking app:

**On your iPhone:**
1. Open Safari (must be Safari, not Chrome)
2. Go to your URL: `https://abhibond1984.github.io/Safety-Lens/`
3. Wait for app to load
4. Tap the **Share icon** (square with arrow) at bottom
5. Scroll down → tap **"Add to Home Screen"**
6. Edit name: "Safety Lens" → tap **Add**

Now you'll have a **Safety Lens icon** on your home screen with the SAIL logo. Tap it — looks exactly like a native app, no browser bar!

**On Android:**
1. Open Chrome
2. Go to your URL
3. Chrome will show a banner: "Add Safety Lens to Home screen?" → tap Add
4. If no banner: tap ⋮ menu → "Install app" → Install

---

## 🎉 You're Done!

Your free Safety Lens app is now:
- ✅ Live on the internet
- ✅ Installed on your iPhone home screen
- ✅ Costs ₹0 forever
- ✅ Auto-updates when you push code changes

**Login:**
- Username: `abhishek.kumar`
- Password: `demo`
- Or click Register to create your own

---

## 🐛 Troubleshooting

### Build fails on GitHub Actions
**Cause:** Sometimes Flutter web has Pages permission issues  
**Fix:**
1. Go to repo → Settings → Pages → Source: GitHub Actions
2. Settings → Actions → General → Workflow permissions → "Read and write permissions" → Save
3. Re-run workflow: Actions tab → click failed run → "Re-run all jobs"

### URL shows 404 Page Not Found
**Cause:** GitHub Pages not yet propagated, or wrong URL  
**Fix:**
- Wait 5 more minutes
- Make sure URL has trailing slash: `.../Safety-Lens/` (not `.../Safety-Lens`)

### App loads but blank screen
**Cause:** Base path mismatch  
**Fix:** Verify your repo name is exactly `Safety-Lens` (case-sensitive)

### Camera doesn't work in Safari
**Cause:** Safari needs HTTPS (GitHub Pages auto-provides this — should work)  
**Fix:** Make sure URL starts with `https://`

### "Add to Home Screen" not visible
**Cause:** Using Chrome on iPhone instead of Safari  
**Fix:** Switch to Safari — only Safari supports PWA on iOS

### Voice input doesn't work on iPhone
**Cause:** Apple Safari doesn't support Web Speech API  
**Fix:** This is expected. Type the location instead. Voice works on Android.

### Slow loading first time
**Cause:** Initial download of ~3 MB Flutter web framework  
**Fix:** This only happens first visit — subsequent loads are instant (cached)

---

## 🔄 Sharing the App

To share with other SAIL safety officers:

1. Send them the URL: `https://abhibond1984.github.io/Safety-Lens/`
2. They open in Safari/Chrome
3. Tap "Add to Home Screen"
4. Done — they have the app too

**For pilot:** Send URL via WhatsApp to 5-10 officers, they install in 30 seconds.

---

## ⏭️ Next Steps

Once web app is working on your phone:

1. **Test all features** (10 min)
2. **Share with 2-3 colleagues** for early feedback
3. **Setup Firebase backend** (so reports sync across devices)
4. **Build admin web dashboard** (for SAIL leadership view)

Tell me when you've completed Step 8 — I'll guide you through Firebase next.

---

## 💡 Honest Disclosure

This is a **Progressive Web App (PWA)** — not a native iOS app. Differences:

| Feature | Native iOS app | PWA (this approach) |
|---------|---------------|---------------------|
| Cost | ₹8,900/year minimum | ₹0 forever |
| App Store listing | Required + reviews | Not needed |
| Install path | App Store | "Add to Home Screen" |
| Looks like native | Yes | Yes (almost identical) |
| Updates | Manual via App Store | Auto on next open |
| Camera | Yes | Yes |
| Notifications | Yes | Android: Yes, iPhone: No |
| Background sync | Yes | Limited |
| File system access | Yes | Limited |

**For SAIL safety officer use case:** PWA does 95% of what you need at 0% of the cost.

If pilot is successful and SAIL approves budget, we can later build native iOS app with paid developer account.
