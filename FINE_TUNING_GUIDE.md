# Fine-Tuning Guide — SAIL Safety Lens AI Model

## Overview

This guide explains how to fine-tune Google Gemini Flash for better safety hazard detection specific to SAIL steel plant environments.

## What Was Done (Immediate Improvements)

### 1. Prompt Optimization (Active Now)
The AI prompts have been upgraded with:
- **Anti-hallucination protocol** — model must provide visual evidence for every hazard
- **False positive traps** — explicit list of common mistakes to avoid
- **"Visible:" prefix requirement** — forces model to describe what it actually sees
- **Lower temperature (0.15)** — reduces creative/random outputs, more factual
- **Confidence scoring** — model self-rates its certainty
- **Maximum 7 hazards** — quality over quantity enforcement
- **Self-check protocol** — model verifies each hazard before outputting

### 2. Fine-Tuning Data Collector (Built-In)
A new service (`lib/services/fine_tuning_collector.dart`) that:
- Saves "approved" scan results as training pairs
- Stores image + correct JSON output together
- Exports in Google AI Studio JSONL format
- Tracks statistics (sections covered, risk distribution)

---

## How to Collect Training Data

### Step 1: Use the App Normally
Run safety inspections as usual. The AI will analyze images.

### Step 2: Review & Approve Good Results
When the AI produces a **good, accurate result**:
```dart
import 'package:safety_lens/services/fine_tuning_collector.dart';

// After a successful scan with good results:
await FineTuningCollector.saveTrainingExample(
  imageBase64: base64Encode(imageBytes),
  approvedResult: scanResult,  // The AI output you verified is correct
  metadata: {'inspector': 'Name', 'location': 'BF#5 Cast House'},
);
```

### Step 3: Correct & Save Bad Results
When the AI produces wrong results, **fix them** and save the corrected version:
```dart
// Fix the result manually
scanResult['hazards'][0]['regulation'] = 'FA 1948 S32';  // Correct citation
scanResult['hazards'].removeAt(3);  // Remove false positive

// Save the CORRECTED version as training data
await FineTuningCollector.saveTrainingExample(
  imageBase64: base64Encode(imageBytes),
  approvedResult: scanResult,  // Your corrected version
);
```

### Step 4: Aim for Diversity
For best fine-tuning results, collect examples from:
- [ ] Blast Furnace (5-10 examples)
- [ ] SMS / BOF (5-10 examples)
- [ ] Coke Oven (5-10 examples)
- [ ] Rolling Mills (5-10 examples)
- [ ] Power Plant (5-10 examples)
- [ ] Electrical areas (5-10 examples)
- [ ] General workshops (5-10 examples)
- [ ] LOW risk / safe scenes (10+ examples — teaches model not to hallucinate)

**Target: 50-100 diverse examples minimum**

---

## How to Export & Fine-Tune

### Step 1: Export JSONL
```dart
final jsonl = await FineTuningCollector.exportAsJsonl();
// Save this string to a .jsonl file
```

### Step 2: Upload to Google AI Studio
1. Go to https://aistudio.google.com/
2. Click **"New tuned model"** in the left sidebar
3. Select base model: **Gemini 2.0 Flash** (or latest Flash)
4. Upload your `.jsonl` file
5. Configure:
   - Training epochs: **3-5** (start with 3)
   - Learning rate: **Auto** (let Google optimize)
   - Batch size: **4** (default is fine)

### Step 3: Get Your Fine-Tuned Model ID
After training completes (~30-60 min for 100 examples):
- You'll get a model ID like: `tunedModels/safety-lens-hazard-v1-xxxxx`
- Copy this ID

### Step 4: Use Fine-Tuned Model in the App
In the admin panel or via code, update the model:
```dart
// In gemini_direct_vision.dart, change:
await GeminiDirectVision.setModel('tunedModels/safety-lens-hazard-v1-xxxxx');
```

Or add it to the available models list in `gemini_direct_vision.dart`:
```dart
static const List<Map<String, String>> availableModels = [
  {'id': 'tunedModels/safety-lens-hazard-v1-xxxxx', 'name': 'SAIL Fine-Tuned (Best accuracy)'},
  {'id': 'gemini-2.0-flash', 'name': 'Gemini 2.0 Flash (General)'},
  // ...
];
```

---

## Fine-Tuning Best Practices

### Data Quality Rules
1. **Never include hallucinated results** — only save examples where hazards are truly visible
2. **Include "safe scene" examples** — teaches model to NOT force-find hazards in clean areas
3. **Fix regulations before saving** — corrected citations teach the model proper references
4. **Balance severity levels** — don't only save CRITICAL; include MEDIUM and LOW too
5. **Include diverse image quality** — well-lit, dark, distant, close-up, blurry edge cases

### What Improves with Fine-Tuning
- ✅ Regulation citation accuracy (learns YOUR approved mappings)
- ✅ False positive reduction (learns when NOT to report)
- ✅ Section-specific hazard priorities (learns what matters in each area)
- ✅ Output format consistency (always produces valid JSON)
- ✅ Severity calibration (learns your severity thresholds)

### What Does NOT Improve
- ❌ Image recognition ability (that's the base model's vision capability)
- ❌ New regulation knowledge (can't learn regulations not in training data)
- ❌ Performance speed (fine-tuned models have same latency)

---

## Checking Training Data Stats

```dart
final stats = await FineTuningCollector.getStats();
print('Total examples: ${stats['totalExamples']}');
print('Ready for fine-tuning: ${stats['readyForFineTuning']}');
print('Risk distribution: ${stats['riskDistribution']}');
print('Sections covered: ${stats['sectionDistribution']}');
print('Recommendation: ${stats['recommendation']}');
```

---

## Cost & Limits

| Item | Free Tier | Notes |
|------|-----------|-------|
| Fine-tuning | FREE | Google AI Studio offers free tuning for Flash models |
| Training data | Up to 500 examples | Our collector caps at 500 |
| Inference | 15 RPM / 1M tokens/day | Same as base model free tier |
| Storage | Unlimited tuned models | Models persist in your AI Studio account |

---

## Troubleshooting

**Model returns empty hazards after fine-tuning:**
- Likely overtrained on "safe scene" examples. Add more hazard-rich examples and retrain.

**Model still cites wrong regulations:**
- Check your training data — if wrong citations exist in approved data, model learns them. Clean your dataset.

**Export JSONL is empty:**
- Check `FineTuningCollector.getExampleCount()` — no examples saved yet.

**Fine-tuning fails on AI Studio:**
- Ensure JSONL is valid: each line must be valid JSON. Test with a JSON validator.
- Image base64 must be valid JPEG. Large images (>10MB) may fail — compress first.

---

## Integration Point (For Developers)

To add an "Approve for Training" button in the scan results screen, add this to your scan result widget:

```dart
// In ai_scan_tab.dart or near_miss_tab.dart, after results display:
ElevatedButton.icon(
  icon: Icon(Icons.school),
  label: Text('Approve for Training'),
  onPressed: () async {
    final saved = await FineTuningCollector.saveTrainingExample(
      imageBase64: base64Encode(_imageBytes!),
      approvedResult: _scanResult!,
      metadata: {'inspector': currentUser, 'location': selectedLocation},
    );
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ Saved as training example')),
      );
    }
  },
)
```
