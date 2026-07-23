# Modern UI Enhancements - Hover Cards & Bottom Navigation

This guide shows you how to use the new hover card effects and modern bottom navigation bar in your Safety Lens V2 app.

## 📦 What's New

### 1. Hover Cards (`hover_card.dart`)
Beautiful hover animations for all your cards with multiple effects:
- **Scale** - Grows slightly on hover
- **Elevation** - Increases shadow depth
- **Glow** - Adds colored glow effect
- **Lift** - Combined scale + elevation
- **Tilt** - 3D tilt effect (desktop)

### 2. Modern Bottom Navigation (`modern_bottom_nav.dart`)
5 stunning navigation bar styles:
- **Floating** - Elevated pill-style with rounded corners
- **Glass** - Glassmorphic with frosted blur effect
- **Minimal** - Clean, subtle animations
- **Bubble** - Playful growing bubbles
- **Morphing** - Flowing indicator between items

---

## 🚀 Quick Start

### Step 1: Add New Files

Three new files have been created:
- `lib/widgets/hover_card.dart` - Hover card widget
- `lib/widgets/modern_bottom_nav.dart` - Modern navigation bar
- `lib/screens/home_screen_modern.dart` - Updated home screen

### Step 2: Choose Your Navigation Style

Open `lib/screens/home_screen_modern.dart` and change line 30:

```dart
// Choose your preferred style:
final BottomNavStyle _navStyle = BottomNavStyle.floating;  // Default
// final BottomNavStyle _navStyle = BottomNavStyle.glass;   // Frosted glass
// final BottomNavStyle _navStyle = BottomNavStyle.minimal; // Minimalist
// final BottomNavStyle _navStyle = BottomNavStyle.bubble;  // Playful
// final BottomNavStyle _navStyle = BottomNavStyle.morphing; // Flowing
```

### Step 3: Replace Home Screen

**Option A: Backup and Replace**
```bash
# Backup original
mv lib/screens/home_screen.dart lib/screens/home_screen_original.dart
# Use new version
mv lib/screens/home_screen_modern.dart lib/screens/home_screen.dart
```

**Option B: Manual Update**

Copy the `ModernBottomNav` widget usage from `home_screen_modern.dart` lines 90-124 into your existing `home_screen.dart`, replacing the old `_bottomNav()` method.

---

## 📖 Using Hover Cards

### Basic Usage

Replace regular `Container` widgets with `HoverCard`:

**Before:**
```dart
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text('Hello'),
)
```

**After:**
```dart
HoverCard(
  padding: EdgeInsets.all(16),
  color: Colors.white,
  borderRadius: BorderRadius.circular(12),
  onTap: () => print('Tapped!'),
  child: Text('Hello'),
)
```

### Hover Effects

Choose which effects to apply:

```dart
// Scale only
HoverCard(
  effects: {HoverEffect.scale},
  child: myWidget,
)

// Scale + Elevation
HoverCard(
  effects: {HoverEffect.scale, HoverEffect.elevation},
  child: myWidget,
)

// Lift + Glow (recommended for stats)
HoverCard(
  effects: {HoverEffect.lift, HoverEffect.glow},
  glowColor: Colors.blue,
  child: myWidget,
)
```

### Pre-configured Card Types

Use these for common scenarios:

#### 1. Stats Cards (Dashboard KPIs)
```dart
HoverStatCard(
  glowColor: AppColors.accent,
  onTap: () => showDetails(),
  child: Column(
    children: [
      Text('42', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
      Text('Total Incidents'),
    ],
  ),
)
```

#### 2. Action Buttons
```dart
HoverActionCard(
  onTap: () => startAIScan(),
  child: Row(
    children: [
      Icon(Icons.document_scanner_rounded),
      SizedBox(width: 8),
      Text('AI Scan'),
    ],
  ),
)
```

#### 3. List Items
```dart
HoverListCard(
  onTap: () => openIncident(incident),
  margin: EdgeInsets.only(bottom: 8),
  child: Row(
    children: [
      CircleAvatar(child: Icon(Icons.warning)),
      SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(incident.title),
            Text(incident.date),
          ],
        ),
      ),
    ],
  ),
)
```

---

## 🎨 Practical Examples

### Example 1: Update Dashboard Stats

**File:** `lib/screens/dashboard_tab.dart`

Find the `_statCard()` method (around line 711) and wrap with HoverCard:

```dart
Widget _statCard({
  required String label,
  required String value,
  required IconData icon,
  required Color color,
  VoidCallback? onTap,
  SL? sl,
}) {
  sl ??= SL.of(context);
  
  return HoverStatCard(  // ← Add this
    onTap: onTap,
    glowColor: color,
    child: Container(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 12, color: sl.text4),
            ],
          ),
          const SizedBox(height: 12),
          Text(value,
              style: TextStyle(
                  color: sl.text1,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: sl.text3,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );  // ← Close HoverStatCard
}
```

### Example 2: Update Quick Action Buttons

**File:** `lib/screens/dashboard_tab.dart`

Find the `_actionBtn()` method (around line 737) and wrap with HoverActionCard:

```dart
Widget _actionBtn(IconData icon, String label, Color color,
    SL sl, VoidCallback onTap) =>
  Expanded(
    child: HoverActionCard(  // ← Add this
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      color: color.withOpacity(0.1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 5),
          Flexible(
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );
```

### Example 3: Update Incident Cards

**File:** `lib/screens/analytics/incident_log_tab.dart`

Find the `_incidentCard()` method (around line 420) and wrap the outer Padding with HoverListCard:

```dart
Widget _incidentCard(SL sl, Map<String, dynamic> inc) {
  // ... existing variables ...
  
  return HoverListCard(  // ← Add this (replaces Padding)
    margin: const EdgeInsets.only(bottom: 8),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncidentDetailScreen(
            incident: inc, onStatusChanged: _load),
      ),
    ),
    border: Border(
      left: BorderSide(color: sevColor, width: 3),
      top: BorderSide(color: sl.glassBorder),
      right: BorderSide(color: sl.glassBorder),
      bottom: BorderSide(color: sl.glassBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ... rest of card content ...
      ],
    ),
  );
}
```

### Example 4: Update Plant Cards

**File:** `lib/screens/dashboard_tab.dart`

Find the `_plantRow()` method (around line 576) and wrap with HoverListCard:

```dart
Widget _plantRow(String code, String name, Map<String, int> s, bool isMy, SL sl) {
  final total = s['total'] ?? 0;
  final open = s['open'] ?? 0;
  final critical = s['critical'] ?? 0;
  final scans = s['scans'] ?? 0;

  return HoverListCard(  // ← Add this
    onTap: () => _showPlantSheet(code, name, s, sl),
    margin: EdgeInsets.zero,
    color: isMy ? AppColors.accent.withOpacity(0.06) : Colors.transparent,
    hoverColor: isMy 
        ? AppColors.accent.withOpacity(0.12) 
        : sl.glassColor.withOpacity(0.5),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(
      children: [
        // ... existing row content ...
      ],
    ),
  );
}
```

---

## 🎯 Best Practices

### When to Use Each Effect

| Effect | Best For | Example |
|--------|----------|---------|
| `scale` | Buttons, clickable items | Action buttons |
| `elevation` | Cards, list items | Incident cards |
| `glow` | Important stats, highlights | KPI cards |
| `lift` | Stats that need emphasis | Dashboard metrics |
| `tilt` | Desktop-only interactive cards | Feature cards |

### Performance Tips

1. **Don't overuse** - Apply hover effects to important interactive elements only
2. **Keep animations short** - 150-300ms is ideal
3. **Group similar items** - Use the same effect for similar card types
4. **Test on mobile** - Hover effects still work (via tap) but are less prominent

### Color Recommendations

```dart
// For glow effects, use brand colors
glowColor: AppColors.accent    // Primary actions
glowColor: AppColors.green     // Success/completed
glowColor: AppColors.red       // Critical/urgent
glowColor: AppColors.amber     // Warnings

// For hover background changes
hoverColor: color.withOpacity(0.5)  // Subtle highlight
```

---

## 🎭 Navigation Bar Showcase

### Floating Style (Default)
```dart
BottomNavStyle.floating
```
✨ Modern, elevated pill design  
✨ Perfect for: Modern, professional apps  
✨ Best with: Light or dark themes

### Glass Style
```dart
BottomNavStyle.glass
```
✨ Frosted glass with blur  
✨ Perfect for: Premium, sophisticated look  
✨ Best with: Gradient backgrounds

### Minimal Style
```dart
BottomNavStyle.minimal
```
✨ Clean, subtle animations  
✨ Perfect for: Content-focused apps  
✨ Best with: Any theme

### Bubble Style
```dart
BottomNavStyle.bubble
```
✨ Playful growing bubbles  
✨ Perfect for: Fun, engaging apps  
✨ Best with: Bright, colorful themes

### Morphing Style
```dart
BottomNavStyle.morphing
```
✨ Flowing indicator animation  
✨ Perfect for: Smooth, fluid feel  
✨ Best with: Modern, animated apps

---

## 🔧 Customization

### Change Navigation Colors

```dart
ModernBottomNav(
  currentIndex: _tabIndex,
  onTap: _changeTab,
  style: BottomNavStyle.floating,
  isDark: isDark,
  
  // Customize colors
  selectedColor: Colors.blue,          // Active item color
  unselectedColor: Colors.grey,        // Inactive item color
  backgroundColor: Colors.white,       // Nav bar background
  
  items: [...],
)
```

### Add Badges

```dart
BottomNavItem(
  icon: Icons.notifications_outlined,
  activeIcon: Icons.notifications_rounded,
  label: 'Alerts',
  badgeCount: 5,              // Show badge with number
  badgeColor: Colors.red,     // Badge color
)
```

### Disable Labels

```dart
ModernBottomNav(
  showLabels: false,  // Icons only
  items: [...],
)
```

### Custom Hover Duration

```dart
HoverCard(
  duration: Duration(milliseconds: 150),  // Faster
  curve: Curves.easeInOut,                // Smoother
  child: myWidget,
)
```

---

## 🐛 Troubleshooting

### Issue: Hover doesn't work on mobile
**Solution:** Hover effects still work on mobile via tap gestures. The animations trigger on press.

### Issue: Cards overlap when hovering
**Solution:** Add sufficient margin between cards:
```dart
HoverCard(
  margin: EdgeInsets.all(8),  // Add spacing
  child: myWidget,
)
```

### Issue: Navigation bar covers content
**Solution:** Make sure `extendBody: true` is set in Scaffold:
```dart
Scaffold(
  extendBody: true,  // Important!
  bottomNavigationBar: ModernBottomNav(...),
)
```

### Issue: Animations feel laggy
**Solution:** Reduce animation duration or simplify effects:
```dart
HoverCard(
  duration: Duration(milliseconds: 150),  // Faster
  effects: {HoverEffect.scale},           // Single effect
  child: myWidget,
)
```

---

## 📱 Preview All Styles

Want to see all navigation styles? Create a test screen:

```dart
class NavStylePreview extends StatefulWidget {
  @override
  State<NavStylePreview> createState() => _NavStylePreviewState();
}

class _NavStylePreviewState extends State<NavStylePreview> {
  int _index = 0;
  BottomNavStyle _style = BottomNavStyle.floating;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nav Style: ${_style.toString().split('.').last}'),
        actions: [
          PopupMenuButton<BottomNavStyle>(
            onSelected: (style) => setState(() => _style = style),
            itemBuilder: (_) => [
              PopupMenuItem(value: BottomNavStyle.floating, child: Text('Floating')),
              PopupMenuItem(value: BottomNavStyle.glass, child: Text('Glass')),
              PopupMenuItem(value: BottomNavStyle.minimal, child: Text('Minimal')),
              PopupMenuItem(value: BottomNavStyle.bubble, child: Text('Bubble')),
              PopupMenuItem(value: BottomNavStyle.morphing, child: Text('Morphing')),
            ],
          ),
        ],
      ),
      body: Center(child: Text('Try different styles from the menu!')),
      bottomNavigationBar: ModernBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        style: _style,
        items: const [
          BottomNavItem(icon: Icons.home, label: 'Home'),
          BottomNavItem(icon: Icons.search, label: 'Search'),
          BottomNavItem(icon: Icons.add, label: 'Add', badgeCount: 3),
          BottomNavItem(icon: Icons.person, label: 'Profile'),
        ],
      ),
    );
  }
}
```

---

## 🎉 Summary

You now have:
- ✅ Beautiful hover effects for all cards
- ✅ 5 modern navigation bar styles
- ✅ Pre-configured card variants
- ✅ Smooth, performant animations
- ✅ Full customization options

Start by updating your dashboard stats with `HoverStatCard`, then gradually enhance other cards throughout your app!

---

## 📚 Additional Resources

- Flutter Animation Docs: https://docs.flutter.dev/development/ui/animations
- Material Design Motion: https://m3.material.io/styles/motion

**Questions?** Check the code comments in `hover_card.dart` and `modern_bottom_nav.dart` for more details!
