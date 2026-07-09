#!/usr/bin/env node
/**
 * build-preview.js
 * ────────────────
 * Reads the Flutter/Dart source files and auto-generates preview/index.html
 * reflecting the current state of:
 *   - AppColors (design tokens) from lib/main.dart
 *   - Navigation items from lib/screens/home_screen.dart
 *   - Safety quotes from lib/screens/home_tab.dart
 *   - Form fields & categories from lib/screens/near_miss_tab.dart
 *   - Chat system prompt & suggestions from lib/screens/chat_tab.dart
 *   - Report sub-tabs from lib/screens/reports_tab.dart
 *   - SAIL plants list from lib/screens/login_screen.dart
 *
 * Usage:
 *   node preview/build-preview.js          (one-shot rebuild)
 *   node preview/build-preview.js --watch  (live file watcher)
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(__dirname, 'index.html');

// ─── HELPERS ──────────────────────────────────────────────────

function readFile(rel) {
  const full = path.join(ROOT, rel);
  try { return fs.readFileSync(full, 'utf8'); } catch { return ''; }
}

function dartColorToCSS(hex8) {
  // Dart Color(0xFFRRGGBB) → #RRGGBB
  if (!hex8) return '#000000';
  const clean = hex8.replace(/0x/i, '').replace(/^FF/i, '');
  return '#' + clean.padStart(6, '0');
}

function extractColors(src) {
  const colors = {};
  const re = /static\s+const\s+(\w+)\s*=\s*Color\(0x([0-9A-Fa-f]+)\)/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    colors[m[1]] = dartColorToCSS(m[2]);
  }
  return colors;
}

function extractNavItems(src) {
  const items = [];
  // Match: _NavItem(Icons.xxx_outlined, Icons.xxx_rounded, 'Label'),
  const re = /_NavItem\(\s*Icons\.(\w+),\s*Icons\.(\w+),\s*'([^']+)'\)/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    // Convert flutter icon name to Material Icons name
    const iconName = m[1].replace('_outlined', '').replace('_rounded', '').replace(/_/g, '_');
    const activeIcon = m[2].replace('_outlined', '').replace('_rounded', '').replace(/_/g, '_');
    items.push({ icon: iconName, activeIcon, label: m[3] });
  }
  return items.length ? items : [
    { icon: 'home', activeIcon: 'home', label: 'Home' },
    { icon: 'document_scanner', activeIcon: 'document_scanner', label: 'AI Scan' },
    { icon: 'warning_amber', activeIcon: 'warning_amber', label: 'Near Miss' },
    { icon: 'chat_bubble', activeIcon: 'chat_bubble', label: 'Ask AI' },
    { icon: 'bar_chart', activeIcon: 'bar_chart', label: 'Reports' },
  ];
}

function extractQuotes(src) {
  const quotes = [];
  // Match single-quoted strings within _safetyQuotes list
  const blockMatch = src.match(/_safetyQuotes\s*=\s*\[([\s\S]*?)\];/);
  if (blockMatch) {
    const re = /'((?:[^'\\]|\\.)*)'/g;
    let m;
    while ((m = re.exec(blockMatch[1])) !== null) {
      quotes.push(m[1].replace(/\\'/g, "'"));
    }
  }
  return quotes.length ? quotes : ["Safety isn't expensive, it's priceless."];
}

function extractPlants(src) {
  const plants = [];
  // Match plant strings in _sailPlants list
  const blockMatch = src.match(/_sailPlants\s*=\s*\[([\s\S]*?)\];/);
  if (blockMatch) {
    const re = /'((?:[^'\\]|\\.)*)'/g;
    let m;
    while ((m = re.exec(blockMatch[1])) !== null) {
      if (m[1] !== 'Others') plants.push(m[1].replace(/\\'/g, "'"));
    }
  }
  return plants.length ? plants : ['BSP — Bhilai Steel Plant', 'DSP — Durgapur Steel Plant'];
}

function extractReportTabs(src) {
  // Look for TabController length
  const lenMatch = src.match(/TabController\(\s*length:\s*(\d+)/);
  const count = lenMatch ? parseInt(lenMatch[1]) : 4;
  // Try to find tab labels from imports or widget references
  const tabs = [];
  if (src.includes('overview_tab')) tabs.push('Overview');
  if (src.includes('incident_log_tab')) tabs.push('Incidents');
  if (src.includes('data_analysis_tab')) tabs.push('Analysis');
  if (src.includes('plant_wise_tab')) tabs.push('Plant-wise');
  while (tabs.length < count) tabs.push(`Tab ${tabs.length + 1}`);
  return tabs;
}

function extractChatSuggestions(src) {
  // Try to find suggestion chip text - look for common patterns
  const suggestions = [];
  // Look for quoted strings that look like safety topics in suggestion chips area
  const chipMatch = src.match(/suggestion[Cc]hips?|_suggestions\s*=\s*\[([\s\S]*?)\]/);
  // Fallback: extract from known patterns
  if (src.includes('PPE')) suggestions.push('PPE in BF area');
  if (src.includes('SG/01')) suggestions.push('SG/01 Rules');
  if (src.includes('Hot work') || src.includes('hot work')) suggestions.push('Hot Work Permit');
  if (src.includes('Crane') || src.includes('crane')) suggestions.push('Crane Safety');
  if (src.includes('Gas') || src.includes('gas')) suggestions.push('Gas Testing');
  if (src.includes('Confined') || src.includes('confined')) suggestions.push('Confined Space');
  return suggestions.length ? suggestions : ['PPE Requirements', 'Safety Rules', 'Work Permit'];
}

function extractNearMissCategories(src) {
  const cats = [];
  // Look for DropdownMenuItem or category-related strings
  const blockMatch = src.match(/categor(?:y|ies)[\s\S]{0,500}?\[([\s\S]*?)\]/i);
  if (blockMatch) {
    const re = /'((?:[^'\\]|\\.)*)'/g;
    let m;
    while ((m = re.exec(blockMatch[1])) !== null) {
      cats.push(m[1]);
    }
  }
  // Fallback: scan for known categories
  if (!cats.length) {
    const patterns = ['Slip/Trip/Fall', 'Electrical', 'Fire', 'Chemical', 'Crane', 'Vehicle', 'PPE'];
    patterns.forEach(p => { if (src.includes(p)) cats.push(p); });
  }
  return cats.length ? cats : ['Electrical', 'Fire', 'Chemical', 'Crane', 'PPE', 'Other'];
}

function flutterIconToMaterial(name) {
  // Convert Flutter icon constant names to Material Icon ligature names
  return name
    .replace(/_outlined$/, '')
    .replace(/_rounded$/, '')
    .replace(/_sharp$/, '')
    .replace(/^Icons\./, '');
}

// ─── MAIN BUILD ───────────────────────────────────────────────

function build() {
  console.log(`[build-preview] Rebuilding at ${new Date().toLocaleTimeString()}...`);

  // Read source files
  const mainSrc = readFile('lib/main.dart');
  const homeSrc = readFile('lib/screens/home_screen.dart');
  const homeTabSrc = readFile('lib/screens/home_tab.dart');
  const loginSrc = readFile('lib/screens/login_screen.dart');
  const nearMissSrc = readFile('lib/screens/near_miss_tab.dart');
  const chatSrc = readFile('lib/screens/chat_tab.dart');
  const reportsSrc = readFile('lib/screens/reports_tab.dart');
  const aiScanSrc = readFile('lib/screens/ai_scan_tab.dart');

  // Extract data
  const colors = extractColors(mainSrc);
  const navItems = extractNavItems(homeSrc);
  const quotes = extractQuotes(homeTabSrc);
  const plants = extractPlants(loginSrc);
  const reportTabs = extractReportTabs(reportsSrc);
  const chatSuggestions = extractChatSuggestions(chatSrc);
  const nearMissCategories = extractNearMissCategories(nearMissSrc);

  // Determine step count from AI scan (step chips)
  const stepMatch = aiScanSrc.match(/currentStep.*?[<>=]+\s*(\d+)/g);
  const aiScanSteps = aiScanSrc.includes('step') ? 5 : 5; // default 5

  // Build color CSS variables
  const c = {
    accent: colors.accent || '#7C4DFF',
    accentDark: colors.accentDark || '#6534E0',
    accentGlow: colors.accentGlow || '#9B6BFF',
    cyan: colors.cyan || '#00BCD4',
    purple: colors.purple || '#E040FB',
    pink: colors.pink || '#FF4081',
    crit: colors.crit || '#FF1744',
    red: colors.red || '#FF5252',
    amber: colors.amber || '#FFAB00',
    green: colors.green || '#00E676',
    darkBg: colors.darkBg || '#0F0C29',
    darkBg2: colors.darkBg2 || '#1A1735',
    darkCard: colors.darkCard || '#1E1B3A',
    darkCard2: colors.darkCard2 || '#272450',
    darkCard3: colors.darkCard3 || '#302B63',
    darkBorder: colors.darkBorder || '#3D3870',
    lightBg: colors.lightBg || '#F8F8F8',
    lightBg2: colors.lightBg2 || '#EFEFEF',
    lightCard: colors.lightCard || '#FFFFFF',
    lightCard2: colors.lightCard2 || '#F3F3F3',
    lightBorder: colors.lightBorder || '#E0E0E0',
  };

  // Generate HTML
  const html = generateHTML(c, navItems, quotes, plants, reportTabs, chatSuggestions, nearMissCategories, aiScanSteps);

  fs.writeFileSync(OUT, html, 'utf8');
  console.log(`[build-preview] Written: ${OUT}`);
  console.log(`[build-preview]   Colors: ${Object.keys(colors).length} tokens extracted`);
  console.log(`[build-preview]   Nav: ${navItems.length} items`);
  console.log(`[build-preview]   Quotes: ${quotes.length}`);
  console.log(`[build-preview]   Plants: ${plants.length}`);
  console.log(`[build-preview]   Report tabs: ${reportTabs.join(', ')}`);
}

function generateHTML(c, navItems, quotes, plants, reportTabs, chatSuggestions, nearMissCategories, aiScanSteps) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Safety Lens V2 — Live Preview</title>
<link rel="icon" href="../web/favicon.png" type="image/png">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<link href="https://fonts.googleapis.com/icon?family=Material+Icons+Round" rel="stylesheet">
<!-- AUTO-GENERATED by build-preview.js — Do not edit manually -->
<!-- Last built: ${new Date().toISOString()} -->
<style>
:root {
  --accent: ${c.accent};
  --accent-dark: ${c.accentDark};
  --accent-glow: ${c.accentGlow};
  --cyan: ${c.cyan};
  --purple: ${c.purple};
  --pink: ${c.pink};
  --crit: ${c.crit};
  --red: ${c.red};
  --amber: ${c.amber};
  --green: ${c.green};
}
[data-theme="dark"] {
  --bg: ${c.darkBg};
  --bg2: ${c.darkBg2};
  --card: ${c.darkCard};
  --card2: ${c.darkCard2};
  --card3: ${c.darkCard3};
  --border: ${c.darkBorder};
  --text1: #F1F5F9;
  --text2: #CBD5E1;
  --text3: #94A3B8;
  --text4: #64748B;
  --glass-bg: rgba(255,255,255,0.06);
  --glass-border: rgba(255,255,255,0.12);
  --nav-bg: rgba(30,27,58,0.95);
}
[data-theme="light"] {
  --bg: ${c.lightBg};
  --bg2: ${c.lightBg2};
  --card: ${c.lightCard};
  --card2: ${c.lightCard2};
  --card3: #ECEBFF;
  --border: ${c.lightBorder};
  --text1: #111111;
  --text2: #333333;
  --text3: #555555;
  --text4: #777777;
  --glass-bg: rgba(255,255,255,0.55);
  --glass-border: rgba(255,255,255,0.6);
  --nav-bg: rgba(255,255,255,0.92);
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  background: var(--bg); color: var(--text1); min-height: 100vh; overflow: hidden;
}
.app-container {
  max-width: 430px; margin: 0 auto; height: 100vh; display: flex; flex-direction: column;
  background: linear-gradient(135deg, var(--bg), var(--card3), var(--bg2));
  position: relative; overflow: hidden;
}
.app-bar {
  display: flex; align-items: center; padding: 12px 16px;
  backdrop-filter: blur(16px); background: var(--glass-bg);
  border-bottom: 1px solid var(--glass-border); z-index: 10;
}
.app-bar .title { font-size: 16px; font-weight: 700; color: var(--text1); flex: 1; }
.app-bar .actions { display: flex; gap: 8px; align-items: center; }
.app-bar .icon-btn {
  width: 34px; height: 34px; border-radius: 10px;
  display: flex; align-items: center; justify-content: center;
  background: var(--glass-bg); border: 1px solid var(--glass-border);
  cursor: pointer; color: var(--text2); transition: all 0.2s;
}
.app-bar .icon-btn:hover { background: var(--accent); color: #fff; }
.tab-content {
  flex: 1; overflow-y: auto; padding: 16px; padding-bottom: 80px;
}
.tab-content::-webkit-scrollbar { width: 4px; }
.tab-content::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }
.bottom-nav {
  position: absolute; bottom: 0; left: 0; right: 0; height: 64px;
  backdrop-filter: blur(16px); background: var(--nav-bg);
  border-top: 0.5px solid var(--glass-border); display: flex; align-items: center; z-index: 10;
}
.nav-item {
  flex: 1; display: flex; flex-direction: column; align-items: center;
  cursor: pointer; padding: 6px 0; transition: all 0.2s;
}
.nav-item .nav-icon {
  width: 32px; height: 24px; display: flex; align-items: center; justify-content: center;
  border-radius: 20px; transition: all 0.2s; font-size: 20px;
}
.nav-item.active .nav-icon { background: rgba(124,77,255,0.15); color: var(--accent); }
.nav-item:not(.active) .nav-icon { color: var(--text4); }
.nav-item .nav-label { font-size: 10px; margin-top: 2px; font-weight: 500; color: var(--text4); }
.nav-item.active .nav-label { color: var(--accent); font-weight: 700; }
.glass-card {
  background: var(--glass-bg); backdrop-filter: blur(12px);
  border: 1px solid var(--glass-border); border-radius: 16px; padding: 16px; margin-bottom: 12px;
}
.quote-bar {
  background: linear-gradient(135deg, #FF8F00, #E65100, #B71C1C);
  border-radius: 12px; padding: 12px 16px; margin-bottom: 14px;
  box-shadow: 0 4px 20px rgba(183,28,28,0.3);
}
.quote-bar p { color: #fff; font-size: 12px; font-weight: 500; text-shadow: 0 1px 3px rgba(0,0,0,0.3); line-height: 1.4; }
.stats-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 14px; }
.stat-card {
  background: rgba(30,27,58,0.7); border: 1px solid var(--border);
  border-radius: 14px; padding: 14px; position: relative; overflow: hidden;
}
[data-theme="light"] .stat-card { background: rgba(255,255,255,0.8); }
.stat-card .stat-value { font-size: 28px; font-weight: 800; line-height: 1; }
.stat-card .stat-label { font-size: 11px; color: var(--text3); margin-top: 4px; font-weight: 500; }
.stat-card .stat-icon { position: absolute; top: 12px; right: 12px; font-size: 18px; opacity: 0.6; }
.quick-actions { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 10px; margin-bottom: 14px; }
.action-btn {
  background: var(--card); border: 1px solid var(--border); border-radius: 14px;
  padding: 14px 8px; text-align: center; cursor: pointer; transition: all 0.2s;
}
.action-btn:hover { transform: translateY(-2px); border-color: var(--accent); }
.action-btn .action-icon { font-size: 24px; margin-bottom: 6px; }
.action-btn .action-label { font-size: 10px; color: var(--text2); font-weight: 600; }
.chart-card {
  background: rgba(30,27,58,0.7); border: 1px solid var(--border);
  border-radius: 16px; padding: 16px; margin-bottom: 14px;
}
[data-theme="light"] .chart-card { background: rgba(255,255,255,0.8); }
.chart-title { font-size: 13px; font-weight: 700; margin-bottom: 12px; display: flex; align-items: center; gap: 6px; }
.bar-chart { display: flex; align-items: flex-end; height: 90px; gap: 6px; padding-bottom: 20px; }
.bar { flex: 1; border-radius: 4px; transition: height 0.6s ease; position: relative; }
.bar-label { position: absolute; bottom: -18px; left: 50%; transform: translateX(-50%); font-size: 9px; color: var(--text4); white-space: nowrap; }
.scan-zone {
  border: 2px dashed var(--border); border-radius: 20px; padding: 40px 20px;
  text-align: center; cursor: pointer; transition: all 0.3s; margin-bottom: 16px;
}
.scan-zone:hover { border-color: var(--accent); background: rgba(124,77,255,0.05); }
.scan-zone p { color: var(--text3); font-size: 13px; }
.step-chips { display: flex; gap: 8px; margin-bottom: 16px; overflow-x: auto; padding-bottom: 4px; }
.step-chip {
  min-width: 36px; height: 36px; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 12px; font-weight: 700; border: 2px solid var(--border); color: var(--text3); flex-shrink: 0;
}
.step-chip.active { border-color: var(--accent); background: var(--accent); color: #fff; }
.step-chip.done { border-color: var(--green); background: var(--green); color: #000; }
.form-group { margin-bottom: 14px; }
.form-group label { font-size: 12px; color: var(--text3); font-weight: 600; margin-bottom: 6px; display: block; }
.form-input {
  width: 100%; padding: 12px 14px; background: var(--card2);
  border: 1px solid var(--border); border-radius: 12px; color: var(--text1);
  font-size: 14px; font-family: inherit; outline: none; transition: border-color 0.2s;
}
.form-input:focus { border-color: var(--accent); }
.form-input::placeholder { color: var(--text4); }
textarea.form-input { min-height: 80px; resize: vertical; }
select.form-input { appearance: none; cursor: pointer; }
.submit-btn {
  width: 100%; padding: 14px;
  background: linear-gradient(135deg, var(--accent), var(--accent-dark));
  color: #fff; border: none; border-radius: 14px; font-size: 14px;
  font-weight: 700; cursor: pointer; transition: all 0.2s; font-family: inherit;
}
.submit-btn:hover { transform: translateY(-1px); box-shadow: 0 6px 20px rgba(124,77,255,0.4); }
.chat-bubble { max-width: 80%; padding: 12px 16px; border-radius: 16px; margin-bottom: 10px; font-size: 13px; line-height: 1.5; }
.chat-bubble.bot { background: var(--card2); border: 1px solid var(--border); border-bottom-left-radius: 4px; color: var(--text1); }
.chat-bubble.user { background: linear-gradient(135deg, var(--accent), var(--accent-dark)); color: #fff; margin-left: auto; border-bottom-right-radius: 4px; }
.chat-input-bar {
  display: flex; gap: 8px; padding: 12px; background: var(--glass-bg);
  border-top: 1px solid var(--glass-border); backdrop-filter: blur(12px);
  position: absolute; bottom: 64px; left: 0; right: 0;
}
.chat-input {
  flex: 1; padding: 10px 14px; background: var(--card2); border: 1px solid var(--border);
  border-radius: 24px; color: var(--text1); font-size: 13px; outline: none; font-family: inherit;
}
.chat-send {
  width: 40px; height: 40px; border-radius: 50%; background: var(--accent);
  border: none; color: #fff; cursor: pointer; display: flex; align-items: center; justify-content: center;
}
.suggestion-chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
.suggestion-chip {
  padding: 8px 14px; background: var(--card); border: 1px solid var(--border);
  border-radius: 20px; font-size: 11px; color: var(--text2); cursor: pointer; transition: all 0.2s;
}
.suggestion-chip:hover { border-color: var(--accent); color: var(--accent); }
.report-tabs {
  display: flex; gap: 4px; margin-bottom: 16px; background: var(--card);
  border-radius: 12px; padding: 4px; border: 1px solid var(--border);
}
.report-tab {
  flex: 1; padding: 8px 4px; text-align: center; font-size: 11px; font-weight: 600;
  border-radius: 8px; cursor: pointer; color: var(--text3); transition: all 0.2s;
}
.report-tab.active { background: var(--accent); color: #fff; }
.incident-card {
  background: var(--card); border: 1px solid var(--border);
  border-radius: 14px; padding: 14px; margin-bottom: 10px; transition: all 0.2s;
}
.incident-card:hover { border-color: var(--accent); }
.incident-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
.severity-badge { padding: 3px 8px; border-radius: 6px; font-size: 10px; font-weight: 700; text-transform: uppercase; }
.severity-critical { background: rgba(255,23,68,0.15); color: var(--crit); }
.severity-high { background: rgba(255,82,82,0.15); color: var(--red); }
.severity-medium { background: rgba(255,171,0,0.15); color: var(--amber); }
.severity-low { background: rgba(0,230,118,0.15); color: var(--green); }
.score-ring { width: 100px; height: 100px; position: relative; margin: 0 auto 12px; }
.score-ring svg { width: 100%; height: 100%; transform: rotate(-90deg); }
.score-ring .score-value { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); font-size: 24px; font-weight: 800; color: var(--text1); }
.admin-pill {
  display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px;
  background: rgba(124,77,255,0.15); border: 1px solid var(--accent);
  border-radius: 20px; font-size: 10px; font-weight: 700; color: var(--accent); cursor: pointer;
}
.theme-toggle { position: fixed; top: 12px; right: 12px; z-index: 100; display: flex; gap: 6px; }
.theme-toggle button {
  padding: 6px 12px; border-radius: 8px; border: 1px solid var(--border);
  background: var(--card); color: var(--text2); font-size: 11px; font-weight: 600; cursor: pointer; font-family: inherit;
}
.theme-toggle button.active { background: var(--accent); color: #fff; border-color: var(--accent); }
.h-bar-row { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; }
.h-bar-label { width: 80px; font-size: 11px; color: var(--text2); flex-shrink: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.h-bar-track { flex: 1; height: 10px; background: var(--border); border-radius: 5px; overflow: hidden; }
.h-bar-fill { height: 100%; border-radius: 5px; transition: width 0.6s ease; }
.h-bar-count { font-size: 10px; color: var(--text3); font-weight: 700; width: 20px; text-align: right; }
.wsa-chart { margin-top: 10px; }
.wsa-row { display: flex; align-items: center; gap: 6px; margin-bottom: 6px; }
.wsa-label { width: 60px; font-size: 9px; color: var(--text3); text-align: right; }
.wsa-bar-bg { flex: 1; height: 8px; background: var(--border); border-radius: 4px; overflow: hidden; }
.wsa-bar-fill { height: 100%; border-radius: 4px; }
.wsa-value { width: 24px; font-size: 9px; color: var(--text2); font-weight: 700; }
.location-badge {
  display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px;
  background: rgba(0,188,212,0.1); border-radius: 8px; font-size: 10px; color: var(--cyan);
}
.build-info {
  position: fixed; bottom: 4px; left: 4px; font-size: 9px; color: var(--text4);
  opacity: 0.5; z-index: 1000; pointer-events: none;
}
@media (min-width: 500px) {
  .app-container { border-left: 1px solid var(--border); border-right: 1px solid var(--border); }
  body { background: #0a0820; }
  [data-theme="light"] body { background: #e8e8e8; }
}
@keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
.tab-content > * { animation: fadeIn 0.3s ease; }
</style>
</head>
<body data-theme="dark">
<div class="build-info">Auto-built: ${new Date().toLocaleString()}</div>
<div class="theme-toggle">
  <button class="active" onclick="setTheme('dark')">Dark</button>
  <button onclick="setTheme('light')">Light</button>
</div>
<div class="app-container">
  <div class="app-bar">
    <div class="title" id="app-bar-title">Safety Lens</div>
    <div class="actions">
      <div class="admin-pill"><span class="material-icons-round" style="font-size:12px">shield</span> Admin</div>
      <div class="icon-btn" onclick="toggleTheme()"><span class="material-icons-round" style="font-size:18px">dark_mode</span></div>
      <div class="icon-btn"><span style="font-size:12px;font-weight:700">HI</span></div>
    </div>
  </div>
  <div class="tab-content" id="tab-content"></div>
  <div class="bottom-nav">
    ${navItems.map((item, i) => `
    <div class="nav-item${i===0?' active':''}" onclick="switchTab(${i})">
      <div class="nav-icon"><span class="material-icons-round">${item.icon}</span></div>
      <div class="nav-label">${item.label}</div>
    </div>`).join('')}
  </div>
</div>
<script>
// ═══ AUTO-GENERATED DATA FROM DART SOURCE ═══
const NAV_ITEMS = ${JSON.stringify(navItems)};
const QUOTES = ${JSON.stringify(quotes)};
const PLANTS = ${JSON.stringify(plants)};
const REPORT_TABS = ${JSON.stringify(reportTabs)};
const CHAT_SUGGESTIONS = ${JSON.stringify(chatSuggestions)};
const NEAR_MISS_CATEGORIES = ${JSON.stringify(nearMissCategories)};
const AI_SCAN_STEPS = ${aiScanSteps};

// ═══ STATE ═══
let currentTab = 0;
let isDark = true;
let activeReportTab = 0;

const sampleIncidents = [
  { id: 'INC-001', title: 'Crane wire fraying near SMS-II', severity: 'Critical', status: 'OPEN', plant: 'BSP', date: '2026-07-07' },
  { id: 'INC-002', title: 'Gas leak detected in Coke Oven Battery #4', severity: 'High', status: 'INVESTIGATING', plant: 'DSP', date: '2026-07-06' },
  { id: 'INC-003', title: 'Missing guard rail at sinter plant walkway', severity: 'Medium', status: 'ACTION TAKEN', plant: 'RSP', date: '2026-07-05' },
  { id: 'INC-004', title: 'Electrical panel exposed wiring in BF control room', severity: 'High', status: 'OPEN', plant: 'BSP', date: '2026-07-04' },
  { id: 'INC-005', title: 'Slip hazard near cooling bed', severity: 'Low', status: 'CLOSED', plant: 'BSL', date: '2026-07-02' },
  { id: 'INC-006', title: 'PPE non-compliance in hot strip mill', severity: 'Medium', status: 'CLOSED', plant: 'ISP', date: '2026-06-30' },
];

function getTodayQuote() {
  const day = Math.floor((Date.now() - new Date(2026,0,1)) / 86400000);
  return QUOTES[Math.abs(day) % QUOTES.length];
}

// ═══ THEME ═══
function setTheme(t) {
  isDark = t === 'dark';
  document.body.setAttribute('data-theme', t);
  document.querySelectorAll('.theme-toggle button').forEach((b, i) =>
    b.classList.toggle('active', (i===0&&isDark)||(i===1&&!isDark)));
}
function toggleTheme() { setTheme(isDark ? 'light' : 'dark'); }

// ═══ TABS ═══
function switchTab(idx) {
  currentTab = idx;
  document.querySelectorAll('.nav-item').forEach((el, i) => el.classList.toggle('active', i === idx));
  document.getElementById('app-bar-title').textContent = NAV_ITEMS[idx]?.label || 'Safety Lens';
  renderTab();
}
function renderTab() {
  const el = document.getElementById('tab-content');
  switch(currentTab) {
    case 0: el.innerHTML = renderHome(); break;
    case 1: el.innerHTML = renderAIScan(); break;
    case 2: el.innerHTML = renderNearMiss(); break;
    case 3: el.innerHTML = renderChat(); break;
    case 4: el.innerHTML = renderReports(); break;
    default: el.innerHTML = '<div class="glass-card"><p>Tab not implemented in preview</p></div>';
  }
}

// ═══ HOME ═══
function renderHome() {
  const total = sampleIncidents.length;
  const open = sampleIncidents.filter(i => ['OPEN','INVESTIGATING','ACTION TAKEN'].includes(i.status)).length;
  const closed = total - open;
  const critical = sampleIncidents.filter(i => i.severity === 'Critical').length;
  const safetyScore = Math.round(100 - (critical/total)*60 - (open/total)*25);
  const weekData = [1, 0, 2, 1, 3, 1, 2];
  const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  const maxVal = Math.max(...weekData);
  const plants = {};
  sampleIncidents.forEach(i => { plants[i.plant] = (plants[i.plant]||0)+1; });
  const plantEntries = Object.entries(plants).sort((a,b)=>b[1]-a[1]);
  const plantMax = plantEntries[0]?.[1] || 1;
  const pColors = ['${c.crit}','${c.red}','${c.amber}','${c.cyan}','${c.green}'];

  return \`
    <div class="quote-bar"><p>"\${getTodayQuote()}"</p></div>
    <div class="glass-card" style="text-align:center">
      <div class="score-ring">
        <svg viewBox="0 0 100 100">
          <circle cx="50" cy="50" r="42" fill="none" stroke="var(--border)" stroke-width="8"/>
          <circle cx="50" cy="50" r="42" fill="none" stroke="\${safetyScore>70?'${c.green}':safetyScore>40?'${c.amber}':'${c.crit}'}"
            stroke-width="8" stroke-linecap="round" stroke-dasharray="\${safetyScore*2.64} 264"/>
        </svg>
        <div class="score-value">\${safetyScore}</div>
      </div>
      <div style="font-size:12px;color:var(--text3);font-weight:600">Safety Score</div>
    </div>
    <div class="stats-grid">
      <div class="stat-card"><span class="stat-icon material-icons-round" style="color:var(--cyan)">assignment</span><div class="stat-value" style="color:var(--cyan)">\${total}</div><div class="stat-label">Total Incidents</div></div>
      <div class="stat-card"><span class="stat-icon material-icons-round" style="color:var(--amber)">pending_actions</span><div class="stat-value" style="color:var(--amber)">\${open}</div><div class="stat-label">Open Cases</div></div>
      <div class="stat-card"><span class="stat-icon material-icons-round" style="color:var(--green)">check_circle</span><div class="stat-value" style="color:var(--green)">\${closed}</div><div class="stat-label">Resolved</div></div>
      <div class="stat-card"><span class="stat-icon material-icons-round" style="color:var(--crit)">local_fire_department</span><div class="stat-value" style="color:var(--crit)">\${critical}</div><div class="stat-label">Critical</div></div>
    </div>
    <div class="quick-actions">
      <div class="action-btn" onclick="switchTab(1)"><div class="action-icon" style="color:var(--accent)"><span class="material-icons-round">photo_camera</span></div><div class="action-label">AI Scan</div></div>
      <div class="action-btn" onclick="switchTab(2)"><div class="action-icon" style="color:var(--amber)"><span class="material-icons-round">report_problem</span></div><div class="action-label">Near Miss</div></div>
      <div class="action-btn" onclick="switchTab(4)"><div class="action-icon" style="color:var(--cyan)"><span class="material-icons-round">analytics</span></div><div class="action-label">Reports</div></div>
    </div>
    <div class="chart-card">
      <div class="chart-title"><span class="material-icons-round" style="color:var(--accent);font-size:16px">trending_up</span> Weekly Trend <span style="margin-left:auto;font-size:10px;color:var(--text4)">\${weekData.reduce((a,b)=>a+b,0)} this week</span></div>
      <div class="bar-chart">\${weekData.map((v,i) => {
        const h = maxVal===0?4:(v/maxVal)*70+4; const isToday = i===6;
        return '<div class="bar" style="height:'+h+'px;background:'+(isToday?'var(--accent)':'var(--cyan)')+';opacity:'+(isToday?1:0.6)+'">'
          +(v>0?'<span style="position:absolute;top:-16px;left:50%;transform:translateX(-50%);font-size:9px;color:var(--text3);font-weight:700">'+v+'</span>':'')
          +'<span class="bar-label" style="'+(isToday?'color:var(--accent);font-weight:800':'')+'">'+days[i]+'</span></div>';
      }).join('')}</div>
    </div>
    <div class="chart-card">
      <div class="chart-title"><span class="material-icons-round" style="color:var(--accent);font-size:16px">factory</span> Incidents by Plant</div>
      \${plantEntries.map(([plant,count],i) => '<div class="h-bar-row"><div class="h-bar-label">'+plant+'</div><div class="h-bar-track"><div class="h-bar-fill" style="width:'+(count/plantMax*100)+'%;background:'+pColors[i%5]+'"></div></div><div class="h-bar-count">'+count+'</div></div>').join('')}
    </div>
    <div class="chart-card">
      <div class="chart-title"><span class="material-icons-round" style="color:var(--accent);font-size:16px">assessment</span> WSA-13 Compliance</div>
      <div class="wsa-chart">\${['Housekeep','PPE','Electrical','Fire','Guard','Chemical'].map((item,i) => {
        const val = [85,92,78,88,71,95][i];
        const color = val>85?'${c.green}':val>75?'${c.amber}':'${c.red}';
        return '<div class="wsa-row"><div class="wsa-label">'+item+'</div><div class="wsa-bar-bg"><div class="wsa-bar-fill" style="width:'+val+'%;background:'+color+'"></div></div><div class="wsa-value">'+val+'%</div></div>';
      }).join('')}</div>
    </div>\`;
}

// ═══ AI SCAN ═══
function renderAIScan() {
  return \`
    <div class="step-chips">\${Array.from({length:AI_SCAN_STEPS},(_,i)=>'<div class="step-chip'+(i===0?' active':'')+'">'\+(i+1)+'</div>').join('')}</div>
    <div class="scan-zone" onclick="document.getElementById('file-input').click()">
      <span class="material-icons-round" style="font-size:48px;color:var(--accent)">add_a_photo</span>
      <p><strong>Tap to capture or upload</strong></p>
      <p style="font-size:11px;margin-top:4px;color:var(--text4)">AI will detect safety hazards automatically</p>
    </div>
    <input type="file" id="file-input" accept="image/*" style="display:none" onchange="handleScanUpload(this)">
    <div id="scan-preview"></div>
    <div class="glass-card" style="display:flex;align-items:center;gap:10px">
      <span class="material-icons-round" style="color:var(--cyan)">my_location</span>
      <div><div style="font-size:12px;font-weight:600">GPS Geo-tagging</div><div style="font-size:10px;color:var(--text4)">Location captured with photo</div></div>
      <div class="location-badge" style="margin-left:auto"><span class="material-icons-round" style="font-size:12px">gps_fixed</span> Ready</div>
    </div>
    <div class="glass-card">
      <div style="font-size:12px;font-weight:600;margin-bottom:8px;display:flex;align-items:center;gap:6px">
        <span class="material-icons-round" style="font-size:14px;color:var(--accent)">info</span> How AI Scan Works
      </div>
      <ol style="font-size:11px;color:var(--text3);padding-left:16px;line-height:1.8">
        <li>Capture/upload a workplace photo</li><li>AI analyzes for safety hazards</li><li>Review & edit AI findings</li><li>Add mitigation actions</li><li>Save & sync to Google Sheets</li>
      </ol>
    </div>\`;
}
function handleScanUpload(input) {
  if (input.files && input.files[0]) {
    const reader = new FileReader();
    reader.onload = e => {
      document.getElementById('scan-preview').innerHTML = '<div class="glass-card" style="text-align:center"><img src="'+e.target.result+'" style="max-width:100%;max-height:250px;border-radius:12px;margin-bottom:12px"><button class="submit-btn" style="margin-top:8px"><span class="material-icons-round" style="font-size:16px;vertical-align:middle;margin-right:6px">smart_toy</span> Analyze with AI</button></div>';
    };
    reader.readAsDataURL(input.files[0]);
  }
}

// ═══ NEAR MISS ═══
function renderNearMiss() {
  return \`
    <div class="glass-card" style="border-left:3px solid var(--amber)">
      <div style="font-size:12px;font-weight:600;display:flex;align-items:center;gap:6px;margin-bottom:4px">
        <span class="material-icons-round" style="font-size:14px;color:var(--amber)">lightbulb</span> Report a Near Miss
      </div>
      <div style="font-size:11px;color:var(--text3)">A near miss is an unplanned event that could have caused injury or damage but didn't.</div>
    </div>
    <div class="form-group"><label>Description *</label><textarea class="form-input" placeholder="What happened? Describe the near miss event..."></textarea></div>
    <div class="form-group"><label>Location / Area *</label><input class="form-input" placeholder="e.g. SMS-II, Crane Bay, BF Control Room"></div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
      <div class="form-group"><label>Severity</label><select class="form-input"><option>Low</option><option>Medium</option><option selected>High</option><option>Critical</option></select></div>
      <div class="form-group"><label>Category</label><select class="form-input">\${NEAR_MISS_CATEGORIES.map(c=>'<option>'+c+'</option>').join('')}</select></div>
    </div>
    <div class="form-group"><label>Plant</label><select class="form-input">\${PLANTS.map(p=>'<option>'+p+'</option>').join('')}</select></div>
    <div class="form-group"><label>Attach Photo (optional)</label><div class="scan-zone" style="padding:20px"><span class="material-icons-round" style="font-size:28px;color:var(--text4)">add_photo_alternate</span><p style="font-size:11px;margin-top:6px">Tap to add photo evidence</p></div></div>
    <div class="form-group"><label>Suggested Actions (AI auto-fill)</label><textarea class="form-input" placeholder="AI will suggest corrective actions..." style="min-height:60px"></textarea></div>
    <button class="submit-btn"><span class="material-icons-round" style="font-size:16px;vertical-align:middle;margin-right:6px">send</span> Submit Near Miss Report</button>\`;
}

// ═══ CHAT ═══
function renderChat() {
  return \`
    <div class="chat-messages" style="height:calc(100vh - 260px);overflow-y:auto">
      <div class="chat-bubble bot"><strong>🛡️ Suraksha Saathi</strong><br><br>Namaste! I'm your AI safety assistant for SAIL plants.<br>Ask me about safety regulations, PPE, permits, and more!</div>
      <div class="suggestion-chips">\${CHAT_SUGGESTIONS.map(s=>'<div class="suggestion-chip" onclick="addUserMsg(\\''+s.replace(/'/g,"\\\\'")+'\\')">'+s+'</div>').join('')}</div>
    </div>
    <div class="chat-input-bar">
      <input class="chat-input" placeholder="Ask Suraksha Saathi..." id="chat-input" onkeypress="if(event.key==='Enter')sendChat()">
      <button class="chat-send" onclick="sendChat()"><span class="material-icons-round" style="font-size:18px">send</span></button>
    </div>\`;
}
function addUserMsg(text) {
  const msgs = document.querySelector('.chat-messages');
  if (msgs) { msgs.innerHTML += '<div class="chat-bubble user">'+text+'</div><div class="chat-bubble bot" style="opacity:0.7"><em>AI is thinking...</em></div>'; msgs.scrollTop = msgs.scrollHeight; }
}
function sendChat() {
  const input = document.getElementById('chat-input');
  if (input && input.value.trim()) { addUserMsg(input.value); input.value = ''; }
}

// ═══ REPORTS ═══
function renderReports() {
  return \`
    <div class="report-tabs">\${REPORT_TABS.map((t,i)=>'<div class="report-tab '+(activeReportTab===i?'active':'')+'" onclick="activeReportTab='+i+';renderTab()">'+t+'</div>').join('')}</div>
    \${activeReportTab===0?renderOverview():''}
    \${activeReportTab===1?renderIncidentLog():''}
    \${activeReportTab===2?renderAnalysis():''}
    \${activeReportTab===3?renderPlantWise():''}\`;
}
function renderOverview() {
  const total=sampleIncidents.length,open=sampleIncidents.filter(i=>i.status!=='CLOSED').length,closed=total-open;
  return '<div class="stats-grid"><div class="stat-card"><div class="stat-value" style="color:var(--cyan)">'+total+'</div><div class="stat-label">Total</div></div><div class="stat-card"><div class="stat-value" style="color:var(--amber)">'+open+'</div><div class="stat-label">Open</div></div><div class="stat-card"><div class="stat-value" style="color:var(--green)">'+closed+'</div><div class="stat-label">Closed</div></div><div class="stat-card"><div class="stat-value" style="color:var(--crit)">'+sampleIncidents.filter(i=>i.severity==='Critical').length+'</div><div class="stat-label">Critical</div></div></div>';
}
function renderIncidentLog() {
  return sampleIncidents.map(inc => '<div class="incident-card"><div class="incident-header"><span style="font-size:11px;color:var(--text4);font-weight:600">'+inc.id+'</span><span class="severity-badge severity-'+inc.severity.toLowerCase()+'">'+inc.severity+'</span></div><div style="font-size:13px;font-weight:600;margin-bottom:6px;color:var(--text1)">'+inc.title+'</div><div style="display:flex;gap:12px;font-size:10px;color:var(--text4)"><span>'+inc.plant+'</span><span>'+inc.date+'</span><span style="margin-left:auto;padding:2px 8px;border-radius:4px;background:'+(inc.status==='CLOSED'?'rgba(0,230,118,0.1)':'rgba(255,171,0,0.1)')+';color:'+(inc.status==='CLOSED'?'var(--green)':'var(--amber)')+'">'+inc.status+'</span></div></div>').join('');
}
function renderAnalysis() {
  const pColors=['${c.crit}','${c.red}','${c.amber}','${c.cyan}','${c.green}'];
  return '<div class="chart-card"><div class="chart-title"><span class="material-icons-round" style="font-size:16px;color:var(--accent)">insights</span> Monthly Trend</div><div class="bar-chart" style="height:100px">'+[3,5,2,7,4,6].map((v,i)=>{const months=['Feb','Mar','Apr','May','Jun','Jul'];return '<div class="bar" style="height:'+(v/7*90)+'px;background:var(--accent);opacity:'+(i===5?1:0.5)+'"><span style="position:absolute;top:-16px;left:50%;transform:translateX(-50%);font-size:9px;color:var(--text3)">'+v+'</span><span class="bar-label">'+months[i]+'</span></div>';}).join('')+'</div></div><div class="chart-card"><div class="chart-title"><span class="material-icons-round" style="font-size:16px;color:var(--cyan)">category</span> By Category</div>'+['Electrical','Fall/Slip','Fire','Crane','PPE','Chemical'].map((cat,i)=>{const vals=[3,2,2,1,1,1];return '<div class="h-bar-row"><div class="h-bar-label">'+cat+'</div><div class="h-bar-track"><div class="h-bar-fill" style="width:'+(vals[i]/3*100)+'%;background:'+pColors[i%5]+'"></div></div><div class="h-bar-count">'+vals[i]+'</div></div>';}).join('')+'</div>';
}
function renderPlantWise() {
  const pColors=['${c.crit}','${c.red}','${c.amber}','${c.cyan}','${c.green}'];
  const plants={};sampleIncidents.forEach(i=>{plants[i.plant]=(plants[i.plant]||0)+1;});
  const entries=Object.entries(plants).sort((a,b)=>b[1]-a[1]);const max=entries[0]?.[1]||1;
  return '<div class="chart-card"><div class="chart-title"><span class="material-icons-round" style="font-size:16px;color:var(--accent)">domain</span> Plant-wise</div>'+entries.map(([p,c],i)=>'<div class="h-bar-row"><div class="h-bar-label">'+p+'</div><div class="h-bar-track"><div class="h-bar-fill" style="width:'+(c/max*100)+'%;background:'+pColors[i%5]+'"></div></div><div class="h-bar-count">'+c+'</div></div>').join('')+'</div>';
}

// ═══ INIT ═══
renderTab();
</script>
</body>
</html>`;
}

// ─── WATCH MODE ───────────────────────────────────────────────

function watch() {
  const dirs = [
    path.join(ROOT, 'lib'),
    path.join(ROOT, 'lib', 'screens'),
    path.join(ROOT, 'lib', 'widgets'),
    path.join(ROOT, 'lib', 'services'),
  ];

  console.log('[build-preview] Watching for changes...');
  console.log('[build-preview] Press Ctrl+C to stop\n');

  let debounce = null;
  const rebuild = (eventType, filename) => {
    if (filename && !filename.endsWith('.dart')) return;
    if (debounce) clearTimeout(debounce);
    debounce = setTimeout(() => {
      console.log(`[build-preview] Change detected: ${filename || 'unknown'}`);
      try { build(); } catch (e) { console.error('[build-preview] Error:', e.message); }
    }, 300);
  };

  dirs.forEach(dir => {
    try { fs.watch(dir, { recursive: false }, rebuild); }
    catch (e) { /* dir may not exist */ }
  });

  // Also watch lib/ recursively if supported
  try { fs.watch(path.join(ROOT, 'lib'), { recursive: true }, rebuild); }
  catch (e) { /* fallback to individual dirs above */ }
}

// ─── ENTRY ────────────────────────────────────────────────────

build();

if (process.argv.includes('--watch') || process.argv.includes('-w')) {
  watch();
}
