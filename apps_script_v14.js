// ============================================================
// SAIL SAFETY LENS — COMPLETE APPS SCRIPT v24
//
// CHANGES FROM v23:
//   ✅ Auto-repair headers: getSheet() detects missing/wrong column headers and fixes them
//   ✅ Fixes legacy sheets created by older script versions with fewer columns
//
// CHANGES FROM v22:
//   ✅ TRUE PARALLEL: UrlFetchApp.fetchAll() fires Gemini + OpenRouter simultaneously
//   ✅ Best-result selection: picks most hazards / highest confidence
//   ✅ CacheService quota cooldown: exhausted providers skipped for 60s
//   ✅ Base64 cleaning: properly strips data URI prefix BEFORE sanitizing
//   ✅ Reduced timeout budget: 45s max (was 4 min — client was timing out at 90s)
//   ✅ Clear error propagation: _isOnline:false always set on failure path
//
// CHANGES FROM v20:
//   ✅ Intelligent model fallback: gemini-2.5-flash → 2.0-flash → 2.0-flash-lite → OpenRouter
//   ✅ Quota exhaustion detection: bails ALL models immediately (no wasted retries)
//   ✅ Structured logging: [AI] / [PARALLEL] / [CACHE] prefixes
//   ✅ parseGoogleResponse / parseOpenRouterResponse extracted for reuse
//
// REQUIRED SCRIPT PROPERTY:
//   GOOGLE_AI_KEY = AIza... (from https://aistudio.google.com/apikey)
//
// OPTIONAL SCRIPT PROPERTY:
//   AI_PRIMARY_PROVIDER = 'google' (default) | 'openrouter' | 'google_only'
//
// EXISTING PROPERTY (kept for fallback):
//   OPENROUTER_API_KEY = sk-or-v1-...
// ============================================================

const CLOUDINARY_CLOUD_NAME    = 'dzt1vxsdg';
const CLOUDINARY_UPLOAD_PRESET = 'safety_lens';

const SHEET_INCIDENTS = 'incidents';
const SHEET_USERS     = 'users';
const SHEET_FEEDBACK  = 'feedback';
const SHEET_KNOWLEDGE = 'knowledge';

// ★ v20: Model fallback chain — try all available free-tier models
const GOOGLE_MODELS    = ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-2.0-flash-lite'];
const GOOGLE_MODEL     = 'gemini-2.5-flash';  // free tier — primary
// ★ v22: Use a DIFFERENT provider on OpenRouter so it's a true fallback
// when Google Gemini quota is exhausted.
// nvidia/nemotron-nano-12b-v2-vl:free — NVIDIA free vision model (NOT Google, avoids shared quota)
const OPENROUTER_MODEL = 'nvidia/nemotron-nano-12b-v2-vl:free'; // NVIDIA free vision, fast 12B
const OPENROUTER_MODEL_PAID = 'anthropic/claude-sonnet-4'; // paid fallback if free fails

const INCIDENT_COLS = [
  'id', 'date', 'title', 'plant', 'dept', 'location', 'severity',
  'wsaCategory', 'obsType', 'desc', 'people', 'immediateAction',
  'type', 'status', 'reportedBy', 'reportedByPno', 'riskScore',
  'confidence', 'summary', 'correctiveAction', 'closedBy',
  'closingRemarks', 'closedAt', 'investigationStartedAt',
  'actionTakenAt', 'imageHash', 'hazardCount', 'imageBase64',
  'hazards', 'pdfUrl', 'syncedAt'
];

const USER_COLS = [
  'uid', 'name', 'designation', 'plant', 'department',
  'pno', 'mobile', 'email', 'isAdmin', 'status',
  'username', 'passwordHash', 'createdAt', 'lastLogin'
];

const FEEDBACK_COLS  = ['id','imageSeed','type','hazardName','hazardJson','timestamp','user'];
const KNOWLEDGE_COLS = ['id','title','content','source','uploadedAt','uploadedBy'];


// ============================================================
//  MAIN ENTRY POINTS
// ============================================================
function doGet(e)  { return handle(e); }
function doPost(e) { return handle(e); }

function handle(e) {
  if (!e) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: true, time: new Date().toISOString(), version: 'v24', note: 'Run via web URL — not from editor' }))
      .setMimeType(ContentService.MimeType.JSON);
  }
  try {
    let params = e.parameter || {};
    if (e.postData && e.postData.contents) {
      const ct = e.postData.type || '';
      if (ct.includes('application/json') || ct.includes('text/plain')) {
        try { Object.assign(params, JSON.parse(e.postData.contents)); } catch(x) {}
      }
    }

    const action = params.action || 'health';
    let result;

    switch (action) {
      case 'health':
      case 'ping':
        result = {
          ok: true,
          time: new Date().toISOString(),
          version: 'v24',
          primaryProvider: getAiPrimary(),
          googleKeyPresent: !!getGoogleKey(),
          openrouterKeyPresent: !!getOpenRouterKey(),
          models: GOOGLE_MODELS
        };
        break;

      // ★ v21: API keys are NEVER sent to client (security fix)
      case 'getApiKeys':
        result = {
          error: 'API keys are no longer exposed to client. All AI calls go through server-side.',
          googleKey: '',
          openRouterKey: ''
        };
        break;

      case 'diagnose': {
        // ★ v20: Enhanced diagnostics — tests every model with latency
        var diag = { google: {}, openrouter: {}, recommended: '', timestamp: new Date().toISOString() };
        var gKey = getGoogleKey();
        var bestModel = '';
        var bestLatency = 999999;

        if (gKey) {
          for (var di = 0; di < GOOGLE_MODELS.length; di++) {
            var dModel = GOOGLE_MODELS[di];
            try {
              var dStart = new Date().getTime();
              var dUrl = 'https://generativelanguage.googleapis.com/v1beta/models/'
                + dModel + ':generateContent?key=' + encodeURIComponent(gKey);
              var dResp = UrlFetchApp.fetch(dUrl, {
                method: 'post', contentType: 'application/json',
                payload: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: 'Say OK' }] }], generationConfig: { maxOutputTokens: 10 } }),
                muteHttpExceptions: true
              });
              var dCode = dResp.getResponseCode();
              var dLatency = new Date().getTime() - dStart;
              diag.google[dModel] = { status: dCode, latency_ms: dLatency };
              if (dCode === 200 && dLatency < bestLatency) {
                bestLatency = dLatency;
                bestModel = dModel;
              }
            } catch (de) {
              diag.google[dModel] = { status: 'ERROR', error: de.toString().substring(0, 100) };
            }
          }
        } else {
          diag.google = 'NO_KEY';
        }

        var oKey = getOpenRouterKey();
        if (oKey) {
          try {
            var oStart = new Date().getTime();
            var oResp = UrlFetchApp.fetch('https://openrouter.ai/api/v1/chat/completions', {
              method: 'post', contentType: 'application/json',
              headers: { 'Authorization': 'Bearer ' + oKey, 'HTTP-Referer': 'https://abhibond1986.github.io/Safety-Lens-V2/', 'X-Title': 'SAIL Safety Lens' },
              payload: JSON.stringify({ model: OPENROUTER_MODEL, messages: [{ role: 'user', content: 'Say OK' }], max_tokens: 10 }),
              muteHttpExceptions: true
            });
            var oCode = oResp.getResponseCode();
            var oLatency = new Date().getTime() - oStart;
            diag.openrouter = { status: oCode, latency_ms: oLatency, model: OPENROUTER_MODEL };
          } catch (oe) {
            diag.openrouter = { status: 'ERROR', error: oe.toString().substring(0, 100) };
          }
        } else {
          diag.openrouter = 'NO_KEY';
        }

        diag.recommended = bestModel || 'openrouter';
        result = diag;
        break;
      }

      // ★ v15: reads prompt from app if provided; accepts fallback base64
      case 'analyzeUrl': {
        const prompt = (params.prompt && params.prompt.length > 100)
          ? params.prompt
          : getSailPrompt('sail_full');
        result = analyzeImageUrl(params.imageUrl || '', prompt, params.imageBase64 || '');
        break;
      }
      case 'gemini': {
        const hasImage = params.imageBase64 && params.imageBase64.length > 10;
        if (hasImage) {
          // ★ v14: also support app-provided prompt for gemini action
          const imgPrompt = (params.prompt && params.prompt.length > 100)
            ? params.prompt
            : getSailPrompt('sail_full');
          result = analyzeImage(imgPrompt, params.imageBase64);
        } else {
          const tp = params.prompt || '';
          result = tp ? callGeminiText(tp) : { success: false, error: 'No prompt' };
        }
        break;
      }

      case 'listIncidents':
        result = listSheet(SHEET_INCIDENTS, INCIDENT_COLS);
        break;
      case 'addIncident':
        result = upsertIncident(params);
        break;
      case 'updateIncidentStatus':
      case 'updateIncident':
        result = upsertIncident(params);
        break;
      case 'deleteIncident':
        result = deleteIncident(params.id || '');
        break;

      case 'clearAllIncidents':
        result = clearAllIncidents();
        break;
      case 'clearKnowledgeBase':
        result = clearKnowledgeBase();
        break;

      case 'formatSheet':
      case 'formatIncidentsSheet':
        result = formatIncidentsSheet();
        break;

      case 'addFeedback':   result = addRow(SHEET_FEEDBACK, FEEDBACK_COLS, params); break;
      case 'listFeedback':  result = listSheet(SHEET_FEEDBACK, FEEDBACK_COLS); break;

      case 'addKnowledge':  result = addRow(SHEET_KNOWLEDGE, KNOWLEDGE_COLS, params); break;
      case 'listKnowledge': result = listSheet(SHEET_KNOWLEDGE, KNOWLEDGE_COLS); break;

      // ★ v24: MASTER DATA SYNC — plants, departments, WSA causes, etc.
      case 'saveMasterData': result = saveMasterData(params); break;
      case 'getMasterData':  result = getMasterData(); break;

      case 'uploadPdfToDrive': {
        const b64   = params.pdfBase64  || '';
        const name  = params.fileName   || 'SafetyLens_Report.pdf';
        const incId = params.incidentId || '';
        Logger.log('[PDF] uploadPdfToDrive: incId=' + incId + ', name=' + name + ', b64Len=' + b64.length);
        if (!b64) { result = { success: false, error: 'No PDF data' }; break; }
        try {
          const bytes  = Utilities.base64Decode(b64);
          const blob   = Utilities.newBlob(bytes, 'application/pdf', name);
          const folder = getOrCreateDriveFolder_();
          const file   = folder.createFile(blob);
          file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
          const viewUrl = 'https://drive.google.com/file/d/' + file.getId() + '/view';
          Logger.log('[PDF] Uploaded to Drive: ' + viewUrl);
          if (incId) {
            Logger.log('[PDF] Updating incident ' + incId + ' with pdfUrl');
            upsertIncident({ id: incId, pdfUrl: viewUrl });
          }
          result = { success: true, pdfUrl: viewUrl, fileId: file.getId() };
        } catch(e) {
          Logger.log('[PDF] ERROR: ' + e.toString());
          result = { success: false, error: e.toString() };
        }
        break;
      }

      case 'register':      result = registerUser(params); break;
      case 'login':         result = loginUser(params.username || '', params.passwordHash || ''); break;

      case 'listUsers':
      case 'getUsers':      result = listUsers(); break;
      case 'addUser':       result = adminAddUser(params); break;
      case 'updateUser':    result = adminUpdateUser(params); break;
      case 'upsertUser':    result = adminAddUser(params); break;
      case 'updateRole':    result = updateUserField(params.username, 'isAdmin', params.isAdmin); break;
      case 'updateStatus':  result = updateUserField(params.username, 'status', params.status); break;
      case 'deleteUser':    result = deleteUser(params.username); break;

      default:
        result = { error: 'Unknown action: ' + action };
    }

    return ContentService
      .createTextOutput(JSON.stringify(result))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    Logger.log('handle() error: ' + err.toString());
    return ContentService
      .createTextOutput(JSON.stringify({ error: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}


// ============================================================
//  PROVIDER CONFIG HELPERS
// ============================================================
function getAiPrimary() {
  const p = PropertiesService.getScriptProperties().getProperty('AI_PRIMARY_PROVIDER');
  return (p === 'openrouter' || p === 'google_only') ? p : 'google';
}
function getGoogleKey() {
  return PropertiesService.getScriptProperties().getProperty('GOOGLE_AI_KEY') || '';
}
function getOpenRouterKey() {
  return PropertiesService.getScriptProperties().getProperty('OPENROUTER_API_KEY') || '';
}


// ============================================================
//  PROVIDER HEALTH MONITORING (v20)
// ============================================================
function getProviderHealth() {
  var health = {
    google: 'UNKNOWN',
    googleModel: '',
    openrouter: 'UNKNOWN',
    lastError: '',
    timestamp: new Date().toISOString()
  };

  var gKey = getGoogleKey();
  if (!gKey) {
    health.google = 'NO_KEY';
  } else {
    for (var i = 0; i < GOOGLE_MODELS.length; i++) {
      var model = GOOGLE_MODELS[i];
      try {
        var url = 'https://generativelanguage.googleapis.com/v1beta/models/'
          + model + ':generateContent?key=' + encodeURIComponent(gKey);
        var resp = UrlFetchApp.fetch(url, {
          method: 'post', contentType: 'application/json',
          payload: JSON.stringify({
            contents: [{ role: 'user', parts: [{ text: 'Say OK' }] }],
            generationConfig: { maxOutputTokens: 10 }
          }),
          muteHttpExceptions: true
        });
        var code = resp.getResponseCode();
        if (code === 200) {
          health.google = 'OK';
          health.googleModel = model;
          break;
        }
        health.lastError = 'HTTP_' + code + ' on ' + model;
      } catch (e) {
        health.lastError = model + ': ' + e.toString().substring(0, 100);
      }
    }
    if (health.google !== 'OK') health.google = 'UNAVAILABLE';
  }

  var oKey = getOpenRouterKey();
  if (!oKey) {
    health.openrouter = 'NO_KEY';
  } else {
    try {
      var oResp = UrlFetchApp.fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'post', contentType: 'application/json',
        headers: { 'Authorization': 'Bearer ' + oKey, 'HTTP-Referer': 'https://abhibond1986.github.io/Safety-Lens-V2/', 'X-Title': 'SAIL Safety Lens' },
        payload: JSON.stringify({ model: OPENROUTER_MODEL, messages: [{ role: 'user', content: 'Say OK' }], max_tokens: 10 }),
        muteHttpExceptions: true
      });
      health.openrouter = oResp.getResponseCode() === 200 ? 'OK' : 'HTTP_' + oResp.getResponseCode();
    } catch (e) {
      health.openrouter = 'ERROR';
      health.lastError = e.toString().substring(0, 100);
    }
  }

  return health;
}


// ============================================================
//  CLEAR ALL INCIDENTS
// ============================================================
function clearAllIncidents() {
  try {
    const sheet = getSheet(SHEET_INCIDENTS);
    const lastRow = sheet.getLastRow();
    if (lastRow > 1) {
      sheet.deleteRows(2, lastRow - 1);
      Logger.log('clearAllIncidents: deleted ' + (lastRow - 1) + ' rows');
    }
    return {
      ok: true, success: true,
      message: 'All incidents cleared',
      rowsCleared: Math.max(0, lastRow - 1)
    };
  } catch (e) {
    return { ok: false, success: false, error: e.toString() };
  }
}


// ============================================================
//  CLEAR REMOTE KNOWLEDGE BASE
// ============================================================
function clearKnowledgeBase() {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = ss.getSheetByName(SHEET_KNOWLEDGE);
    if (!sheet) {
      return {
        ok: true, success: true,
        message: 'No remote KB sheet — skipped',
        rowsCleared: 0
      };
    }
    const lastRow = sheet.getLastRow();
    if (lastRow > 1) sheet.deleteRows(2, lastRow - 1);
    return {
      ok: true, success: true,
      message: 'KB cleared',
      rowsCleared: Math.max(0, lastRow - 1)
    };
  } catch (e) {
    return { ok: false, success: false, error: e.toString() };
  }
}


// ============================================================
//  INCIDENT UPSERT
// ============================================================
function upsertIncident(params) {
  const sheet   = getSheet(SHEET_INCIDENTS);
  const data    = sheet.getDataRange().getValues();
  const headers = data[0];
  const idCol   = headers.indexOf('id');
  const incId   = String(params.id || '');
  const now     = new Date().toISOString();

  const safe = function(col, val) {
    if (val === undefined || val === null) return '';
    if (col === 'imageBase64') return val ? '[image]' : '';
    if (col === 'hazards') {
      try {
        const h = typeof val === 'string' ? JSON.parse(val) : val;
        return JSON.stringify(h).substring(0, 5000);
      } catch (_) { return String(val).substring(0, 5000); }
    }
    const s = String(val);
    return s.length > 3000 ? s.substring(0, 3000) : s;
  };

  const hazardCount = function() {
    try {
      const h = typeof params.hazards === 'string'
        ? JSON.parse(params.hazards) : (params.hazards || []);
      return Array.isArray(h) ? h.length : 0;
    } catch (_) { return 0; }
  };

  if (incId) {
    for (var i = 1; i < data.length; i++) {
      if (String(data[i][idCol]) === incId) {
        INCIDENT_COLS.forEach(function(col, j) {
          var colIdx = headers.indexOf(col);
          if (colIdx < 0) return;
          if (col === 'syncedAt') {
            sheet.getRange(i + 1, colIdx + 1).setValue(now);
            return;
          }
          if (col === 'hazardCount') {
            const hc = hazardCount();
            if (hc > 0) sheet.getRange(i + 1, colIdx + 1).setValue(hc);
            return;
          }
          var incoming = params[col];
          if (incoming !== undefined && incoming !== null && String(incoming) !== '') {
            if (col === 'pdfUrl' && String(incoming).indexOf('http') === 0) {
              sheet.getRange(i + 1, colIdx + 1).setFormula(makePdfHyperlink(incoming));
            } else {
              sheet.getRange(i + 1, colIdx + 1).setValue(safe(col, incoming));
            }
          }
        });
        return { ok: true, action: 'updated', id: incId, row: i + 1 };
      }
    }
  }

  const row = INCIDENT_COLS.map(function(col) {
    if (col === 'syncedAt')    return now;
    if (col === 'hazardCount') return hazardCount();
    return safe(col, params[col]);
  });

  sheet.appendRow(row);
  try {
    const newRow = sheet.getLastRow();
    const pdfIdx = headers.indexOf('pdfUrl');
    if (pdfIdx >= 0 && params.pdfUrl && String(params.pdfUrl).indexOf('http') === 0) {
      sheet.getRange(newRow, pdfIdx + 1).setFormula(makePdfHyperlink(params.pdfUrl));
    }
  } catch (_) {}
  try { sheet.autoResizeColumns(1, Math.min(20, INCIDENT_COLS.length)); } catch(_) {}
  // ★ v17: Auto-format sheet after every insert for professional look
  try { formatIncidentsSheet(); } catch(_) {}
  return { ok: true, action: 'inserted', id: incId, row: sheet.getLastRow() };
}

function deleteIncident(id) {
  try {
    if (!id) return { ok: false, error: 'No id' };
    const sheet = getSheet(SHEET_INCIDENTS);
    const data  = sheet.getDataRange().getValues();
    const idCol = data[0].indexOf('id');
    for (var i = 1; i < data.length; i++) {
      if (String(data[i][idCol]) === String(id)) {
        sheet.deleteRow(i + 1);
        return { ok: true, deleted: id };
      }
    }
    return { ok: false, error: 'Incident not found: ' + id };
  } catch(err) { return { ok: false, error: err.toString() }; }
}


// ============================================================
//  AUTH
// ============================================================
function registerUser(p) {
  try {
    const sheet   = getSheet(SHEET_USERS);
    const data    = sheet.getDataRange().getValues();
    const headers = data[0];
    const usernameCol = headers.indexOf('username');
    const pnoCol      = headers.indexOf('pno');

    for (var i = 1; i < data.length; i++) {
      if (data[i][usernameCol] && data[i][usernameCol] === p.username)
        return { success: false, error: 'Username already exists' };
      if (p.pno && data[i][pnoCol] && data[i][pnoCol] === p.pno)
        return { success: false, error: 'Employee P.No already registered' };
    }

    const isFirstUser = (data.length <= 1);
    const isAdmin = isFirstUser ? 'TRUE' : 'FALSE';
    const uid = Utilities.getUuid();
    const now = new Date().toISOString();

    const newUser = {
      uid: uid, name: p.name || '', designation: p.designation || '',
      plant: p.plant || '', department: p.department || '',
      pno: p.pno || '', mobile: p.mobile || '', email: p.email || '',
      isAdmin: isAdmin, status: 'active',
      username: p.username || '', passwordHash: p.passwordHash || '',
      createdAt: now, lastLogin: ''
    };

    sheet.appendRow(USER_COLS.map(function(c){ return newUser[c] || ''; }));

    return {
      success: true, uid: uid, isAdmin: isAdmin === 'TRUE',
      message: isFirstUser
        ? 'Account created. You are the first user — admin access granted.'
        : 'Account created.'
    };
  } catch(err) {
    return { success: false, error: err.toString() };
  }
}

function loginUser(username, passwordHash) {
  try {
    if (!username || !passwordHash)
      return { success: false, error: 'Username and password required' };

    if (username === 'admin' && passwordHash === simpleHash('admin')) {
      return {
        success: true, uid: 'SYSTEM_ADMIN', name: 'System Admin',
        username: 'admin', isAdmin: true, status: 'active',
        plant: 'Corporate – Ranchi', department: 'Safety HQ',
        designation: 'Administrator'
      };
    }

    const sheet   = getSheet(SHEET_USERS);
    const data    = sheet.getDataRange().getValues();
    const headers = data[0];
    const usernameCol     = headers.indexOf('username');
    const pnoCol          = headers.indexOf('pno');
    const passwordHashCol = headers.indexOf('passwordHash');
    const statusCol       = headers.indexOf('status');
    const lastLoginCol    = headers.indexOf('lastLogin');
    const isAdminCol      = headers.indexOf('isAdmin');

    for (var i = 1; i < data.length; i++) {
      const rowUsername = String(data[i][usernameCol] || '');
      const rowPno      = String(data[i][pnoCol]      || '');
      const rowHash     = String(data[i][passwordHashCol] || '');

      if ((rowUsername === username || rowPno === username) && rowHash === passwordHash) {
        const rowStatus = String(data[i][statusCol] || 'active').toLowerCase();
        if (rowStatus === 'inactive')
          return { success: false, error: 'Account is inactive. Contact admin.' };

        if (lastLoginCol >= 0)
          sheet.getRange(i + 1, lastLoginCol + 1).setValue(new Date().toISOString());

        const user = {};
        headers.forEach(function(h, j) {
          if (h !== 'passwordHash') user[h] = data[i][j];
        });
        user.isAdmin = String(data[i][isAdminCol]).toUpperCase() === 'TRUE';
        return { success: true, user: user };
      }
    }
    return { success: false, error: 'Invalid username or password' };
  } catch(err) {
    return { success: false, error: err.toString() };
  }
}


// ============================================================
//  USER MANAGEMENT
// ============================================================
function listUsers() {
  try {
    const sheet   = getSheet(SHEET_USERS);
    const data    = sheet.getDataRange().getValues();
    const headers = data[0];
    const users   = [];
    for (var i = 1; i < data.length; i++) {
      if (!data[i][0]) continue;
      const u = {};
      headers.forEach(function(h, j) {
        if (h !== 'passwordHash') u[h] = data[i][j];
      });
      u.isAdmin = String(data[i][headers.indexOf('isAdmin')]).toUpperCase() === 'TRUE';
      users.push(u);
    }
    return { success: true, users: users, count: users.length };
  } catch(err) {
    return { success: false, error: err.toString() };
  }
}

function adminAddUser(p) {
  try {
    const sheet   = getSheet(SHEET_USERS);
    const data    = sheet.getDataRange().getValues();
    const headers = data[0];
    const uCol    = headers.indexOf('username');
    for (var i = 1; i < data.length; i++) {
      if (data[i][uCol] === p.username) {
        return adminUpdateUser(p);
      }
    }
  } catch(_) {}
  const resp = registerUser(p);
  if (resp.success && (p.isAdmin === 'TRUE' || p.isAdmin === true)) {
    updateUserField(p.username, 'isAdmin', 'TRUE');
    resp.isAdmin = true;
  }
  return resp;
}

function adminUpdateUser(p) {
  try {
    const sheet   = getSheet(SHEET_USERS);
    const data    = sheet.getDataRange().getValues();
    const headers = data[0];
    const uCol    = headers.indexOf('username');
    for (var i = 1; i < data.length; i++) {
      if (data[i][uCol] === p.username) {
        const protected_ = ['uid','username','createdAt'];
        headers.forEach(function(h, j) {
          if (!protected_.includes(h) && p[h] !== undefined && String(p[h]) !== '')
            sheet.getRange(i + 1, j + 1).setValue(p[h]);
        });
        return { success: true };
      }
    }
    return { success: false, error: 'User not found: ' + p.username };
  } catch(err) { return { success: false, error: err.toString() }; }
}

function updateUserField(username, field, value) {
  try {
    const sheet   = getSheet(SHEET_USERS);
    const data    = sheet.getDataRange().getValues();
    const headers = data[0];
    const uCol    = headers.indexOf('username');
    const fCol    = headers.indexOf(field);
    if (fCol < 0) return { success: false, error: 'Unknown field: ' + field };
    for (var i = 1; i < data.length; i++) {
      if (data[i][uCol] === username) {
        sheet.getRange(i + 1, fCol + 1).setValue(value);
        return { success: true };
      }
    }
    return { success: false, error: 'User not found: ' + username };
  } catch(err) { return { success: false, error: err.toString() }; }
}

function deleteUser(username) {
  try {
    if (username === 'admin') return { success: false, error: 'Cannot delete system admin' };
    const sheet   = getSheet(SHEET_USERS);
    const data    = sheet.getDataRange().getValues();
    const headers = data[0];
    const uCol    = headers.indexOf('username');
    for (var i = 1; i < data.length; i++) {
      if (data[i][uCol] === username) { sheet.deleteRow(i + 1); return { success: true }; }
    }
    return { success: false, error: 'User not found' };
  } catch(err) { return { success: false, error: err.toString() }; }
}


// ============================================================
//  SIMPLE HASH
// ============================================================
function simpleHash(str) {
  var h = 0;
  for (var i = 0; i < str.length; i++) {
    h = ((h << 5) - h) + str.charCodeAt(i);
    h = h & h;
  }
  if (h < 0) return '-' + ((-h) >>> 0).toString(36);
  return h.toString(36);
}


// ============================================================
//  SAFETY PROMPT — v14: now includes PIPE vs WIRE rules
// ============================================================
function getSailPrompt(promptMode) {
  return 'You are a senior industrial safety inspector for SAIL '
    + '(Steel Authority of India Limited), certified under IS 14489:2018 '
    + 'with 20+ years of experience in integrated steel plant safety. '
    + 'Your job is to honestly report what is visible in this photograph — '
    + 'no more, no less.\n\n'

    + '═════════════════════════════════════════════════════════\n'
    + 'STEP 1 — OBSERVE THE IMAGE (do this silently first)\n'
    + '═════════════════════════════════════════════════════════\n'
    + 'Before listing any hazard, internally describe:\n'
    + '  • What is the scene? (Workshop, vessel, panel, walkway, etc.)\n'
    + '  • What equipment, structures, or surfaces are visible?\n'
    + '  • Are there any people? How many? What are they doing?\n'
    + '  • What is the lighting and image clarity like?\n\n'
    + 'Your "summary" field MUST begin with a literal description of '
    + 'what is visible in the photo — not a generic safety statement.\n\n'

    + '═════════════════════════════════════════════════════════\n'
    + 'STEP 2 — GROUNDING RULES (NEVER violate)\n'
    + '═════════════════════════════════════════════════════════\n'
    + 'A hazard you cannot SEE is a hazard that does NOT EXIST in this image.\n\n'
    + 'NEVER invent hazards based on what is "typical" for steel plants.\n'
    + 'NEVER report a hazard category just because it would be common.\n\n'
    + 'Specifically:\n'
    + '  • If NO worker is visible → you may NOT report "fall from height", '
    + '"lack of fall protection", "no harness", "no PPE", "improper body position", '
    + 'or any other worker-related hazard.\n'
    + '  • If NO elevated work surface, scaffold, edge, platform, or opening is '
    + 'visible → you may NOT report fall-from-height risk.\n'
    + '  • If NO active machinery operation, energised circuit work, or hot work '
    + 'is visible → you may NOT report procedural violations (no LOTO, no PTW, '
    + 'no permit, etc).\n'
    + '  • If NO gas cylinders, chemicals, or flammables are visible → you may '
    + 'NOT report storage/segregation hazards.\n\n'
    + 'Better to report 2 real hazards than 7 hazards where 5 are inventions.\n\n'

    + '═════════════════════════════════════════════════════════\n'
    + 'STEP 3 — IMAGE QUALITY ESCAPE HATCH\n'
    + '═════════════════════════════════════════════════════════\n'
    + 'If the image is too blurry, dark, pixelated, low-resolution, or '
    + 'tightly cropped to identify hazards confidently:\n'
    + '  • Set "confidence" to a LOW value (30–50).\n'
    + '  • Return ONE hazard only: {\n'
    + '       name: "Image quality insufficient",\n'
    + '       severity: "LOW",\n'
    + '       description: "Image is too unclear for confident hazard '
    + 'assessment. Recapture with better lighting/resolution and from '
    + 'multiple angles for proper analysis.",\n'
    + '       regulation: "General safety inspection principles",\n'
    + '       correctiveAction: "Recapture the area with adequate lighting '
    + 'and resolution, ideally from 2–3 angles, and re-submit for analysis."\n'
    + '    }\n'
    + '  • Do NOT invent additional hazards to fill the list.\n\n'

    + '═════════════════════════════════════════════════════════\n'
    + 'STEP 4 — HAZARD CATEGORIES (match what you actually see)\n'
    + '═════════════════════════════════════════════════════════\n\n'

    + '── EQUIPMENT INTEGRITY & CORROSION ──\n'
    + '  • Corroded structural elements, brackets, supports, vessels, pipework\n'
    + '  • Corrosion Under Insulation (CUI) — rust streaks emerging from '
    + 'insulation joints or cladding edges; significant integrity risk in '
    + 'insulated vessels and piping\n'
    + '  • Damaged/deteriorated equipment cladding or insulation\n'
    + '  • Visible cracks, deformation, or leaks\n'
    + '  • Unsecured equipment, plates, panels, covers\n'
    + '  • Missing safety guards on machinery (FA 1948 S21)\n'
    + '  • Missing pressure relief devices or gauges (FA 1948 S31)\n'
    + '  • Heavy scale/deposit accumulation concealing potential defects\n\n'

    + '── ELECTRICAL HAZARDS ──\n'
    + '  • Exposed/damaged electrical wiring, cables, junction boxes\n'
    + '  • Open electrical panels with exposed live parts\n'
    + '  • Missing DANGER notices on apparatus >250V (CEA Reg 20)\n'
    + '  • Missing insulating mats in front of panels (CEA Reg 21)\n'
    + '  • Inadequate clearance (<1.0m) in front of switchboards (CEA Reg 39)\n'
    + '  • Missing/inadequate earthing connections (CEA Reg 43)\n\n'

    + '── IDENTIFICATION & SIGNAGE ──\n'
    + '  • Equipment ID plates corroded, illegible, or missing\n'
    + '  • Required hazard warning signs damaged or absent\n'
    + '  • Unlabelled equipment whose function/contents/parameters cannot be '
    + 'determined\n'
    + '  • Calibration tags missing or expired on gauges/instruments\n\n'

    + '── HOUSEKEEPING ──\n'
    + '  • Debris, scale, or deposits on equipment, floors, walkways\n'
    + '  • Oil/water/chemical spills creating slip risk\n'
    + '  • Tools, materials, or stored items obstructing access routes\n'
    + '  • Cables, hoses, or wires snaking across walkways (trip risk)\n\n'

    + '── WORKER-RELATED (only if workers ACTUALLY visible) ──\n'
    + '  • Worker at height without fall arrest — FA 1948 S32(c) + IS 3521:1999\n'
    + '  • Worker without required PPE for the task (helmet IS 2925, '
    + 'footwear IS 5852, eye IS 5983, etc.)\n'
    + '  • Worker in danger zone or unsafe body position\n'
    + '  • Improper manual handling (men >55kg, women >30kg — FA 1948 S34)\n\n'

    + '── STORAGE / CHEMICAL (only if visible) ──\n'
    + '  • Gas cylinders unchained, valve caps missing, mis-stored, '
    + 'mis-colour-coded (SMPV Rules 2016)\n'
    + '  • O₂ + flammable gas within 6 m of each other (SMPV Rule 14)\n'
    + '  • Flammable materials near ignition sources (FA 1948 S37)\n'
    + '  • Chemicals stored without containment, segregation, or labelling\n\n'

    // ★ NEW v14: PIPE vs WIRE differentiation
    + '═════════════════════════════════════════════════════════\n'
    + 'PIPE vs WIRE DIFFERENTIATION (CRITICAL for steel plants)\n'
    + '═════════════════════════════════════════════════════════\n'
    + 'Steel plants have THOUSANDS of pipes but few exposed wires.\n'
    + 'Before labelling anything as "electrical wire", apply these rules:\n\n'
    + '  Rule 1: If it is mounted on brackets/clamps/pipe supports → PIPE\n'
    + '  Rule 2: If it is colour-coded (Blue=Air, Yellow=Gas, Green=Water,\n'
    + '           Red=Fire, Black=Oil, Silver/Aluminium=Steam) → PIPE\n'
    + '           (per IS 2379:1963 pipe colour code)\n'
    + '  Rule 3: If it runs along pipe racks or between equipment → PIPE\n'
    + '  Rule 4: If it has flanges, valves, or threaded joints → PIPE\n'
    + '  Rule 5: If diameter is >6mm and material looks metallic → PIPE\n'
    + '  Rule 6: Only label as "electrical wire/cable" if you see:\n'
    + '           — PVC/rubber insulation sheathing\n'
    + '           — Cable trays (perforated metal trays)\n'
    + '           — Conduit (corrugated flexible tubing)\n'
    + '           — Junction boxes at endpoints\n'
    + '           — Multiple thin conductors bundled together\n\n'
    + 'GAS CYLINDER COLOUR CODES (IS 4379:1981):\n'
    + '  Oxygen=Black body/White neck, Acetylene=Maroon,\n'
    + '  Nitrogen=Grey body/Black neck, Hydrogen=Red,\n'
    + '  Argon=Peacock Blue, CO2=Aluminium/Silver,\n'
    + '  LPG=Dark Red, Chlorine=Golden Yellow\n\n'
    + 'PIPE COLOUR CODES (IS 2379:1963):\n'
    + '  Blue=Compressed Air, Yellow=Natural Gas/Fuel Gas,\n'
    + '  Green=Water (all types), Red=Fire fighting,\n'
    + '  Black=Oil/Petroleum, Silver/Aluminium=Steam,\n'
    + '  Orange=Acid, Violet=Alkali, Brown=Mining/Slurry\n\n'

    + '═════════════════════════════════════════════════════════\n'
    + 'CRITICAL CITATION RULES — NEVER VIOLATE\n'
    + '═════════════════════════════════════════════════════════\n'
    + '1. Working at height → ALWAYS cite FA 1948 S32(c) — NEVER S36.\n'
    + '2. S36 = confined space / dangerous fumes ONLY.\n'
    + '3. For corrosion / equipment integrity → FA 1948 S39 (defective '
    + 'equipment to be taken out of service) + IS 14489:2018 Clause 4.\n'
    + '4. For Corrosion Under Insulation (CUI) → general safety principles '
    + '+ IS 14489:2018 Clause 4 (inspection & maintenance).\n'
    + '5. For unlabelled / un-identified equipment → "General safety '
    + 'principles for equipment identification". Do not invent a section.\n'
    + '6. Cite a regulation ONLY if its condition is actually visible in '
    + 'the image. If unsure, use "General safety principles".\n'
    + '7. Give EXACT section/clause numbers — never say "applicable '
    + 'regulations".\n'
    + '8. Every corrective action MUST start with an action verb (Install, '
    + 'Replace, Inspect, Insulate, De-energise, Remove, Verify, Clean, etc.).\n'
    + '9. Bounding box values are normalised 0.0–1.0 (x = left edge, '
    + 'y = top edge, w = width, h = height).\n\n'

    + '═════════════════════════════════════════════════════════\n'
    + 'PEOPLE COUNT\n'
    + '═════════════════════════════════════════════════════════\n'
    + 'Count ONLY persons actually visible (including partial silhouettes '
    + 'and shadows). If NO persons are visible, put 0. Never invent presence.\n\n'

    + '═════════════════════════════════════════════════════════\n'
    + 'WSA 13 CAUSE CATEGORIES (assign best fit, one per hazard)\n'
    + '═════════════════════════════════════════════════════════\n'
    + '1.Failure to follow procedure  2.Lack of hazard awareness  '
    + '3.Improper PPE use\n'
    + '4.Unsafe body positioning  5.Equipment failure  '
    + '6.Communication failure\n'
    + '7.Human error  8.Poor housekeeping  9.Lack of supervision\n'
    + '10.Fatigue/time pressure  11.Unauthorized operation  '
    + '12.Inadequate isolation  13.Environmental\n\n'

    + '═════════════════════════════════════════════════════════\n'
    + 'OUTPUT FORMAT — valid JSON ONLY, no markdown, no preamble\n'
    + '═════════════════════════════════════════════════════════\n'
    + '{\n'
    + '  "overallRisk": "CRITICAL|HIGH|MEDIUM|LOW",\n'
    + '  "riskScore": <0-100>,\n'
    + '  "confidence": <0-100, LOWER if image unclear>,\n'
    + '  "people": <integer count of ACTUALLY VISIBLE persons, 0 if none>,\n'
    + '  "summary": "Sentence 1: literal description of what is visible in '
    + 'the photo. Sentence 2: highest-priority concern identified. '
    + 'Sentence 3 (optional): regulatory context.",\n'
    + '  "hazards": [\n'
    + '    {\n'
    + '      "name": "max 5 words describing what is VISIBLE",\n'
    + '      "severity": "CRITICAL|HIGH|MEDIUM|LOW",\n'
    + '      "description": "What is visible (specific to this image). Why '
    + 'it is dangerous. Do NOT generalise beyond what the image shows.",\n'
    + '      "regulation": "exact section IF visible condition matches; '
    + 'otherwise \\"General safety principles\\"",\n'
    + '      "correctiveAction": "starts with action verb; specific to this '
    + 'hazard",\n'
    + '      "type": "Unsafe Act|Unsafe Condition",\n'
    + '      "wsaCause": "number. description e.g. 5. Equipment failure",\n'
    + '      "bbox": {"x": 0.1, "y": 0.1, "w": 0.3, "h": 0.4}\n'
    + '    }\n'
    + '  ],\n'
    + '  "wsa": ["list of WSA causes ACTUALLY applicable"],\n'
    + '  "preventive": ["long-term measure with IS standard if applicable"],\n'
    + '  "ptw_required": "PTW types needed or \\"None\\"",\n'
    + '  "nearest_standard": "primary IS standard or \\"General safety principles\\""\n'
    + '}\n\n'

    + 'REMEMBER:\n'
    + '  • An empty hazards list is acceptable if the image truly shows no hazards.\n'
    + '  • A SHORT list of REAL hazards is far better than a LONG list with inventions.\n'
    + '  • Your reputation depends on accuracy, not on finding the most hazards.';
}


// ============================================================
//  GOOGLE AI STUDIO DIRECT (FREE PRIMARY)
// ============================================================
function callGoogleDirectImage(prompt, base64, mimeType) {
  const key = getGoogleKey();
  if (!key) {
    Logger.log('[AI] ERROR: no GOOGLE_AI_KEY set, skipping');
    return null;
  }

  let pure = base64 || '';
  const commaIdx = pure.indexOf(',');
  if (pure.indexOf('base64') >= 0 && commaIdx > 0) {
    pure = pure.substring(commaIdx + 1);
  }
  pure = pure.replace(/\s+/g, '');

  if (pure.length < 100) {
    Logger.log('[AI] ERROR: image data too small (' + pure.length + ' chars)');
    return null;
  }

  var globalStart = new Date().getTime();

  // ★ v20: Intelligent model fallback with exponential backoff
  for (var mi = 0; mi < GOOGLE_MODELS.length; mi++) {
    var model = GOOGLE_MODELS[mi];
    Logger.log('[AI] Model=' + model + ' (' + (mi+1) + '/' + GOOGLE_MODELS.length + ') starting...');

    // ✅ v23: Reduced budget — 45s max (no point making client wait 90s)
    var elapsed = new Date().getTime() - globalStart;
    if (elapsed > 45000) {
      Logger.log('[AI] TIMEOUT: total elapsed ' + Math.round(elapsed/1000) + 's, aborting (45s budget)');
      break;
    }

    var url = 'https://generativelanguage.googleapis.com/v1beta/models/'
      + model + ':generateContent?key=' + encodeURIComponent(key);

    var payload = {
      contents: [{
        role: 'user',
        parts: [
          { text: prompt },
          { inline_data: { mime_type: mimeType || 'image/jpeg', data: pure } }
        ]
      }],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 4096,
        responseMimeType: 'application/json'
      }
    };

    // ★ v22: Reduced backoff — 2 attempts max (quota exhaustion is instant, no point retrying)
    var BACKOFF = [0, 3];

    try {
      var resp, code, lastErrBody = '';
      for (var attempt = 1; attempt <= 2; attempt++) {
        if (attempt > 1) {
          var wait = BACKOFF[attempt - 1];
          Logger.log('[AI] Model=' + model + ' Attempt=' + attempt + ' waiting ' + wait + 's...');
          Utilities.sleep(wait * 1000);
        }

        resp = UrlFetchApp.fetch(url, {
          method: 'post',
          contentType: 'application/json',
          payload: JSON.stringify(payload),
          muteHttpExceptions: true
        });
        code = resp.getResponseCode();
        Logger.log('[AI] Model=' + model + ' Attempt=' + attempt + ' HTTP=' + code);

        // Success — break out of retry loop
        if (code === 200) break;

        lastErrBody = resp.getContentText().substring(0, 500);

        // QUOTA EXHAUSTION — affects ALL models on this key, bail immediately
        if (lastErrBody.indexOf('Quota exceeded') >= 0 || lastErrBody.indexOf('RESOURCE_EXHAUSTED') >= 0) {
          Logger.log('[AI] 🚫 QUOTA EXHAUSTED — all models on this key are blocked');
          Logger.log('[AI] Error: ' + lastErrBody.substring(0, 300));
          setProviderCooldown('google', 60); // ✅ v23: Cache cooldown
          return null; // Skip ALL remaining models
        }

        // 404 — model doesn't exist, skip to next model immediately
        if (code === 404) {
          Logger.log('[AI] Model=' + model + ' not found (404), skipping');
          break;
        }

        // 400/401/403 — permanent error, skip this model
        if (code === 400 || code === 401 || code === 403) {
          Logger.log('[AI] Model=' + model + ' permanent error HTTP=' + code + ': ' + lastErrBody.substring(0, 200));
          break;
        }

        // 429/500/503 — transient, worth retrying
        if (code === 429 || code === 500 || code === 503) {
          if (attempt >= 2) {
            Logger.log('[AI] Model=' + model + ' exhausted retries, moving to next');
          }
          continue;
        }

        // Unknown error code — log and move on
        Logger.log('[AI] Model=' + model + ' unexpected HTTP=' + code + ': ' + lastErrBody.substring(0, 200));
        break;
      }

      // If we didn't get 200 after retries, try next model
      if (code !== 200) continue;

      // ── Parse and validate response ──
      var data;
      try {
        data = JSON.parse(resp.getContentText());
      } catch (parseErr) {
        Logger.log('[AI] Model=' + model + ' JSON parse error on response: ' + parseErr.toString());
        continue;
      }

      if (!data.candidates || data.candidates.length === 0) {
        Logger.log('[AI] Model=' + model + ' no candidates, promptFeedback='
          + JSON.stringify(data.promptFeedback || {}));
        continue;
      }

      var c = data.candidates[0];
      if (c.finishReason && c.finishReason !== 'STOP' && c.finishReason !== 'MAX_TOKENS') {
        Logger.log('[AI] Model=' + model + ' blocked, finishReason=' + c.finishReason);
        continue;
      }
      if (!c.content || !c.content.parts || c.content.parts.length === 0) {
        Logger.log('[AI] Model=' + model + ' empty content parts');
        continue;
      }

      var text = c.content.parts[0].text || '';
      text = text.trim();
      if (!text) {
        Logger.log('[AI] Model=' + model + ' empty text in parts[0]');
        continue;
      }

      // ── Safe JSON extraction ──
      if (text.startsWith('```json')) text = text.substring(7);
      if (text.startsWith('```'))     text = text.substring(3);
      if (text.endsWith('```'))       text = text.slice(0, -3);
      var f = text.indexOf('{'), l = text.lastIndexOf('}');
      if (f < 0 || l <= f) {
        Logger.log('[AI] Model=' + model + ' no JSON object found in response: ' + text.substring(0, 200));
        continue;
      }
      text = text.substring(f, l + 1);

      var result;
      try {
        result = JSON.parse(text.trim());
      } catch (jsonErr) {
        Logger.log('[AI] Model=' + model + ' malformed JSON: ' + jsonErr.toString());
        Logger.log('[AI] Raw text (first 300): ' + text.substring(0, 300));
        continue;
      }

      // ── Validate result has required fields ──
      if (typeof result !== 'object' || result === null) {
        Logger.log('[AI] Model=' + model + ' result is not an object');
        continue;
      }

      result._provider = 'google_direct';
      result._model    = model;
      if (result.people === undefined) result.people = 0;
      if (!result.hazards) result.hazards = [];
      if (!result.overallRisk) result.overallRisk = 'UNKNOWN';

      if (data.usageMetadata) {
        result._tokens = {
          'in':  data.usageMetadata.promptTokenCount     || 0,
          'out': data.usageMetadata.candidatesTokenCount || 0,
          total: data.usageMetadata.totalTokenCount      || 0
        };
      }

      var totalMs = new Date().getTime() - globalStart;
      Logger.log('[AI] ✓ SUCCESS Model=' + model + ' hazards=' + result.hazards.length
        + ' tokens=' + ((result._tokens && result._tokens.total) || '?')
        + ' elapsed=' + totalMs + 'ms');
      return result;

    } catch (err) {
      Logger.log('[AI] Model=' + model + ' EXCEPTION: ' + err.toString());
      continue;  // try next model
    }
  }

  var totalMs = new Date().getTime() - globalStart;
  Logger.log('[AI] All Google models failed after ' + totalMs + 'ms');
  return null;
}

function callGoogleDirectText(prompt) {
  const key = getGoogleKey();
  if (!key) {
    Logger.log('[AI-Text] No GOOGLE_AI_KEY set');
    return null;
  }

  var BACKOFF = [0, 5, 10, 20];

  // ★ v20: Try all models with retry logic (same as image version)
  for (var mi = 0; mi < GOOGLE_MODELS.length; mi++) {
    var model = GOOGLE_MODELS[mi];
    var url = 'https://generativelanguage.googleapis.com/v1beta/models/'
      + model + ':generateContent?key=' + encodeURIComponent(key);

    var payload = {
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.3, maxOutputTokens: 2048 }
    };

    for (var attempt = 1; attempt <= 4; attempt++) {
      if (attempt > 1) Utilities.sleep(BACKOFF[attempt - 1] * 1000);

      try {
        var resp = UrlFetchApp.fetch(url, {
          method: 'post',
          contentType: 'application/json',
          payload: JSON.stringify(payload),
          muteHttpExceptions: true
        });
        var code = resp.getResponseCode();
        Logger.log('[AI-Text] Model=' + model + ' Attempt=' + attempt + ' HTTP=' + code);

        // Quota exhaustion — bail all models
        if (code === 429 || code === 503) {
          var body = resp.getContentText();
          if (body.indexOf('Quota exceeded') >= 0 || body.indexOf('RESOURCE_EXHAUSTED') >= 0) {
            Logger.log('[AI-Text] Quota exhausted, bailing');
            return null;
          }
          if (attempt >= 4) break; // move to next model
          continue;
        }

        if (code === 404) break; // model not found, next model
        if (code !== 200) break; // permanent error, next model

        var data = JSON.parse(resp.getContentText());
        if (!data.candidates || !data.candidates[0] ||
            !data.candidates[0].content || !data.candidates[0].content.parts) {
          Logger.log('[AI-Text] Model=' + model + ' no valid candidates');
          break;
        }

        return {
          success: true,
          result: data.candidates[0].content.parts[0].text || '',
          _provider: 'google_direct',
          _model: model
        };
      } catch (err) {
        Logger.log('[AI-Text] Model=' + model + ' exception: ' + err.toString());
        break;
      }
    }
  }

  Logger.log('[AI-Text] All Google models failed');
  return null;
}


// ============================================================
//  OPENROUTER (PAID FALLBACK)
// ============================================================
function callOpenRouterText(prompt) {
  try {
    const response = callOpenRouterWithRetry({
      model: OPENROUTER_MODEL,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 2048, temperature: 0.3
    });
    if (!response) return { success: false, error: 'OpenRouter unavailable' };
    if (response.getResponseCode() !== 200) {
      return { success: false, error: 'HTTP ' + response.getResponseCode() };
    }
    const data = JSON.parse(response.getContentText());
    const txt = data.choices && data.choices[0] && data.choices[0].message
      ? data.choices[0].message.content : '';
    return { success: true, result: txt, _provider: 'openrouter' };
  } catch(err) { return { success: false, error: err.toString() }; }
}

function callOpenRouterImageUrl(imageUrl, prompt) {
  // Try free model first, then paid fallback
  var models = [OPENROUTER_MODEL, OPENROUTER_MODEL_PAID];
  for (var mi = 0; mi < models.length; mi++) {
    var modelName = models[mi];
    try {
      Logger.log('OpenRouter URL: trying model=' + modelName);
      const response = callOpenRouterWithRetry({
        model: modelName,
        messages: [{
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            { type: 'image_url', image_url: { url: imageUrl } }
          ]
        }],
        max_tokens: 4096, temperature: 0.2
      });
      if (!response) continue;
      const code = response.getResponseCode();
      Logger.log('OpenRouter URL: model=' + modelName + ' HTTP=' + code);
      if (code !== 200) {
        Logger.log('OpenRouter error: ' + response.getContentText().substring(0, 300));
        continue;
      }

      let text = JSON.parse(response.getContentText())
        .choices[0].message.content.trim();
      if (text.startsWith('```json')) text = text.substring(7);
      if (text.startsWith('```'))     text = text.substring(3);
      if (text.endsWith('```'))       text = text.slice(0, -3);
      const f = text.indexOf('{'), l = text.lastIndexOf('}');
      if (f >= 0 && l > f) text = text.substring(f, l + 1);

      const result = JSON.parse(text.trim());
      result._provider = 'openrouter';
      result._model    = modelName;
      if (result.people === undefined) result.people = 0;
      if (!result.hazards) result.hazards = [];
      Logger.log('OpenRouter URL: SUCCESS model=' + modelName + ' hazards=' + result.hazards.length);
      return result;
    } catch(err) {
      Logger.log('OpenRouter URL: model=' + modelName + ' exception: ' + err.toString());
      continue;
    }
  }
  return null;
}

// ★ v22: OpenRouter with base64 data URL — tries free model then paid fallback
function callOpenRouterImageBase64(base64, mimeType, prompt) {
  const dataUrl = 'data:' + (mimeType || 'image/jpeg') + ';base64,' + base64;
  var models = [OPENROUTER_MODEL, OPENROUTER_MODEL_PAID];
  for (var mi = 0; mi < models.length; mi++) {
    var modelName = models[mi];
    try {
      Logger.log('OpenRouter b64: trying model=' + modelName + ' (' + base64.length + ' chars)');
      const response = callOpenRouterWithRetry({
        model: modelName,
        messages: [{
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            { type: 'image_url', image_url: { url: dataUrl } }
          ]
        }],
        max_tokens: 4096, temperature: 0.2
      });
      if (!response) continue;
      const code = response.getResponseCode();
      Logger.log('OpenRouter b64: model=' + modelName + ' HTTP=' + code);
      if (code !== 200) {
        Logger.log('OpenRouter b64 error: ' + response.getContentText().substring(0, 300));
        continue;
      }

      let text = JSON.parse(response.getContentText())
        .choices[0].message.content.trim();
      if (text.startsWith('```json')) text = text.substring(7);
      if (text.startsWith('```'))     text = text.substring(3);
      if (text.endsWith('```'))       text = text.slice(0, -3);
      const f = text.indexOf('{'), l = text.lastIndexOf('}');
      if (f >= 0 && l > f) text = text.substring(f, l + 1);

      const result = JSON.parse(text.trim());
      result._provider = 'openrouter';
      result._model    = modelName;
      if (result.people === undefined) result.people = 0;
      if (!result.hazards) result.hazards = [];
      Logger.log('OpenRouter b64: SUCCESS model=' + modelName + ' hazards=' + result.hazards.length);
      return result;
    } catch(err) {
      Logger.log('OpenRouter b64: model=' + modelName + ' exception: ' + err.toString());
      continue;
    }
  }
  return null;
}

function callOpenRouterWithRetry(payload) {
  const key = getOpenRouterKey();
  if (!key) {
    Logger.log('[AI-OR] No OPENROUTER_API_KEY set');
    return null;
  }
  const options = {
    method: 'post', contentType: 'application/json',
    headers: {
      'Authorization': 'Bearer ' + key,
      'HTTP-Referer': 'https://abhibond1986.github.io/Safety-Lens-V2/',
      'X-Title': 'SAIL Safety Lens'
    },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  };
  // ★ v22: 2 attempts with 1s, 3s backoff (reduced from 3 attempts / 2s,5s,10s)
  var BACKOFF = [0, 1, 3];
  var response;
  for (var attempt = 1; attempt <= 2; attempt++) {
    if (attempt > 1) {
      Logger.log('[AI-OR] Retry attempt=' + attempt + ' waiting ' + BACKOFF[attempt] + 's...');
      Utilities.sleep(BACKOFF[attempt] * 1000);
    }
    try {
      response = UrlFetchApp.fetch('https://openrouter.ai/api/v1/chat/completions', options);
      var code = response.getResponseCode();
      Logger.log('[AI-OR] Attempt=' + attempt + ' HTTP=' + code);
      if (code === 200) return response;
      // 402 = payment required, no point retrying
      if (code === 402 || code === 401 || code === 403) {
        Logger.log('[AI-OR] Permanent error HTTP=' + code + ', not retrying');
        return response;
      }
    } catch(err) {
      Logger.log('[AI-OR] Attempt=' + attempt + ' exception: ' + err.toString());
    }
  }
  return response;
}


// ============================================================
//  PROVIDER CHAIN — Google primary, OpenRouter fallback
// ============================================================
function analyzeImage(prompt, imageBase64) {
  if (!imageBase64 || imageBase64.length < 10) return { error: 'No image data' };

  // ✅ FIX v23: Properly strip data URI prefix BEFORE sanitizing
  let cleanB64 = imageBase64;
  // Strip "data:image/jpeg;base64," or similar prefix
  var commaIdx = cleanB64.indexOf(',');
  if (cleanB64.indexOf('base64') >= 0 && commaIdx > 0 && commaIdx < 100) {
    cleanB64 = cleanB64.substring(commaIdx + 1);
  }
  // Now sanitize: spaces→+, remove anything non-base64
  cleanB64 = cleanB64.replace(/ /g, '+').replace(/[^A-Za-z0-9+\/=]/g, '');
  while (cleanB64.length % 4 !== 0) cleanB64 += '=';

  Logger.log('analyzeImage: cleaned base64 length=' + cleanB64.length);

  return runProviderChain(prompt, cleanB64, 'image/jpeg', null);
}

function analyzeImageUrl(imageUrl, prompt, fallbackBase64) {
  if (!imageUrl && !fallbackBase64) return { error: 'No image URL or data provided' };

  let base64 = '';
  let mimeType = 'image/jpeg';

  // Try to fetch image from URL server-side
  if (imageUrl) {
    try {
      const resp = UrlFetchApp.fetch(imageUrl, { muteHttpExceptions: true });
      const code = resp.getResponseCode();
      if (code === 200) {
        const blob = resp.getBlob();
        const ct = blob.getContentType() || '';
        if (ct.indexOf('image/') === 0) mimeType = ct;
        else if (imageUrl.match(/\.png(\?|$)/i))  mimeType = 'image/png';
        else if (imageUrl.match(/\.webp(\?|$)/i)) mimeType = 'image/webp';
        base64 = Utilities.base64Encode(blob.getBytes());
        Logger.log('analyzeImageUrl: fetched ' + base64.length + ' chars base64, mime=' + mimeType);
      } else {
        Logger.log('analyzeImageUrl: image fetch HTTP ' + code);
      }
    } catch (err) {
      Logger.log('analyzeImageUrl: fetch exception ' + err.toString());
    }
  }

  // ★ v15: Use fallback base64 from app if server-side fetch failed
  if (!base64 && fallbackBase64 && fallbackBase64.length > 100) {
    Logger.log('analyzeImageUrl: using fallback base64 from app (' + fallbackBase64.length + ' chars)');
    base64 = fallbackBase64;
    // ✅ v23: Strip data URI prefix FIRST, then sanitize
    var fbComma = base64.indexOf(',');
    if (base64.indexOf('base64') >= 0 && fbComma > 0 && fbComma < 100) {
      base64 = base64.substring(fbComma + 1);
    }
    base64 = base64.replace(/ /g, '+').replace(/[^A-Za-z0-9+\/=]/g, '');
    while (base64.length % 4 !== 0) base64 += '=';
  }

  return runProviderChain(prompt, base64, mimeType, imageUrl);
}

function runProviderChain(prompt, base64, mimeType, cloudUrl) {
  const primary = getAiPrimary();
  Logger.log('runProviderChain: primary=' + primary
    + ', hasBase64=' + (!!base64)
    + ', hasCloudUrl=' + (!!cloudUrl)
    + ', mode=TRUE_PARALLEL');

  // ★ v24: FAST BAIL — if both providers are already on cooldown, return immediately
  // instead of wasting 60s waiting for fetchAll to timeout
  if (isProviderCoolingDown('google') && isProviderCoolingDown('openrouter')) {
    Logger.log('[AI] ⚡ FAST BAIL: both providers on cooldown — returning instantly');
    return {
      overallRisk: 'UNKNOWN', riskScore: 0, confidence: 0, people: 0,
      summary: 'AI services temporarily unavailable. All providers exhausted. Please try again in 1-2 minutes.',
      hazards: [],
      _provider: 'none', _error: 'All AI providers on cooldown', _isOnline: false,
      imageUrl: cloudUrl || null
    };
  }

  // ✅ v23: TRUE PARALLEL — Gemini + OpenRouter race simultaneously via fetchAll()
  if (primary !== 'google_only') {
    var parallelResult = runTrueParallel(prompt, base64, mimeType, cloudUrl);
    if (parallelResult) {
      if (cloudUrl) parallelResult.imageUrl = cloudUrl;
      return parallelResult;
    }
  }

  // Fallback: google_only mode or parallel failed entirely
  if (primary === 'google_only' || primary === 'google') {
    // Check cooldown before sequential attempt
    if (isProviderCoolingDown('google')) {
      Logger.log('[AI] Google on cooldown, skipping sequential fallback');
    } else {
      var result = null;
      if (base64) result = callGoogleDirectImage(prompt, base64, mimeType);
      if (result) {
        if (cloudUrl) result.imageUrl = cloudUrl;
        return result;
      }
    }
    if (primary === 'google_only') {
      return {
        error: 'Google AI Studio unavailable (free tier exhausted or key invalid).',
        overallRisk: 'UNKNOWN', riskScore: 0, confidence: 0, people: 0,
        summary: 'AI unavailable — provider on cooldown or failed.',
        hazards: [],
        _provider: 'none',
        _isOnline: false,
        imageUrl: cloudUrl || null
      };
    }
  }

  Logger.log('[AI] ✗ ALL PROVIDERS FAILED — returning structured error');
  return {
    overallRisk: 'UNKNOWN',
    riskScore: 0,
    confidence: 0,
    people: 0,
    summary: 'AI services temporarily unavailable. All providers exhausted. Please try again in 1-2 minutes.',
    hazards: [],
    _provider: 'none',
    _error: 'All AI providers failed',
    _isOnline: false,
    imageUrl: cloudUrl || null
  };
}

// ════════════════════════════════════════════════════════════════════════
//  ✅ v23: TRUE PARALLEL via UrlFetchApp.fetchAll()
//  Both providers fire simultaneously. First valid result wins.
//  Total budget: 45s max (well within Apps Script 6-min limit).
// ════════════════════════════════════════════════════════════════════════
function runTrueParallel(prompt, base64, mimeType, cloudUrl) {
  var googleKey = getGoogleKey();
  var openRouterKey = getOpenRouterKey();
  var startTime = new Date().getTime();

  if (!googleKey && !openRouterKey) {
    Logger.log('[PARALLEL] No API keys configured');
    return null;
  }

  // ✅ Check CacheService cooldowns — skip providers known to be exhausted
  var googleCooling = isProviderCoolingDown('google');
  var orCooling = isProviderCoolingDown('openrouter');

  if (googleCooling && orCooling) {
    Logger.log('[PARALLEL] Both providers on cooldown — skipping');
    return null;
  }

  // Build parallel request array
  var requests = [];
  var requestLabels = []; // Track which request is which

  // ── Google Gemini request ──
  if (googleKey && base64 && !googleCooling) {
    var googleModel = GOOGLE_MODELS[0]; // Primary model
    var googleUrl = 'https://generativelanguage.googleapis.com/v1beta/models/'
      + googleModel + ':generateContent?key=' + encodeURIComponent(googleKey);
    var googlePayload = {
      contents: [{
        role: 'user',
        parts: [
          { text: prompt },
          { inline_data: { mime_type: mimeType || 'image/jpeg', data: base64 } }
        ]
      }],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 4096,
        responseMimeType: 'application/json'
      }
    };
    requests.push({
      url: googleUrl,
      method: 'post',
      contentType: 'application/json',
      payload: JSON.stringify(googlePayload),
      muteHttpExceptions: true
    });
    requestLabels.push({ provider: 'google', model: googleModel });
    Logger.log('[PARALLEL] ▶ Queued Google ' + googleModel);
  }

  // ── OpenRouter request ──
  if (openRouterKey && base64 && !orCooling) {
    var dataUrl = 'data:' + (mimeType || 'image/jpeg') + ';base64,' + base64;
    var orPayload = {
      model: OPENROUTER_MODEL,
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: prompt },
          { type: 'image_url', image_url: { url: dataUrl } }
        ]
      }],
      max_tokens: 4096,
      temperature: 0.2
    };
    requests.push({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'post',
      contentType: 'application/json',
      headers: {
        'Authorization': 'Bearer ' + openRouterKey,
        'HTTP-Referer': 'https://abhibond1986.github.io/Safety-Lens-V2/',
        'X-Title': 'SAIL Safety Lens'
      },
      payload: JSON.stringify(orPayload),
      muteHttpExceptions: true
    });
    requestLabels.push({ provider: 'openrouter', model: OPENROUTER_MODEL });
    Logger.log('[PARALLEL] ▶ Queued OpenRouter ' + OPENROUTER_MODEL);
  }

  if (requests.length === 0) {
    Logger.log('[PARALLEL] No requests to send (all on cooldown or no keys)');
    return null;
  }

  // ✅ FIRE ALL SIMULTANEOUSLY — fetchAll() sends all requests in parallel
  Logger.log('[PARALLEL] Firing ' + requests.length + ' requests simultaneously...');
  var responses;
  try {
    responses = UrlFetchApp.fetchAll(requests);
  } catch (e) {
    Logger.log('[PARALLEL] fetchAll exception: ' + e.toString());
    return null;
  }

  var elapsed = new Date().getTime() - startTime;
  Logger.log('[PARALLEL] All responses received in ' + elapsed + 'ms');

  // ✅ Parse all responses, pick the BEST result
  var results = [];
  for (var i = 0; i < responses.length; i++) {
    var resp = responses[i];
    var label = requestLabels[i];
    var code = resp.getResponseCode();
    Logger.log('[PARALLEL] ' + label.provider + ' (' + label.model + ') HTTP=' + code);

    if (code !== 200) {
      var errBody = resp.getContentText().substring(0, 300);
      // Detect quota exhaustion → set cooldown
      if (errBody.indexOf('Quota exceeded') >= 0 || errBody.indexOf('RESOURCE_EXHAUSTED') >= 0
          || code === 429) {
        Logger.log('[PARALLEL] 🚫 ' + label.provider + ' QUOTA EXHAUSTED — cooling down 60s');
        setProviderCooldown(label.provider, 60);
      }
      continue;
    }

    // Parse response based on provider
    try {
      var parsed = null;
      if (label.provider === 'google') {
        parsed = parseGoogleResponse(resp, label.model);
      } else {
        parsed = parseOpenRouterResponse(resp);
      }

      if (parsed && parsed.hazards && parsed.hazards.length > 0) {
        parsed._parallelElapsed = elapsed;
        results.push(parsed);
        Logger.log('[PARALLEL] ✓ ' + label.provider + ' returned ' + parsed.hazards.length + ' hazards');
      } else {
        Logger.log('[PARALLEL] ' + label.provider + ' returned no hazards or parse failed');
      }
    } catch (parseErr) {
      Logger.log('[PARALLEL] ' + label.provider + ' parse error: ' + parseErr.toString());
    }
  }

  // ✅ Pick BEST result: most hazards, then highest confidence
  if (results.length === 0) {
    var totalElapsed = new Date().getTime() - startTime;
    Logger.log('[PARALLEL] ✗ ALL FAILED in ' + totalElapsed + 'ms');
    return null;
  }

  results.sort(function(a, b) {
    // Prefer more hazards
    var hDiff = (b.hazards || []).length - (a.hazards || []).length;
    if (hDiff !== 0) return hDiff;
    // Then higher confidence
    return (b.confidence || 0) - (a.confidence || 0);
  });

  var best = results[0];
  Logger.log('[PARALLEL] ✓ BEST: ' + best._provider + '/' + best._model
    + ' hazards=' + best.hazards.length + ' confidence=' + (best.confidence || '?')
    + ' totalElapsed=' + (new Date().getTime() - startTime) + 'ms');
  return best;
}

// ════════════════════════════════════════════════════════════════════════
//  ✅ v23: CacheService-based quota cooldown
//  Marks a provider as exhausted for N seconds. Prevents wasted retries.
// ════════════════════════════════════════════════════════════════════════
function isProviderCoolingDown(provider) {
  try {
    var cache = CacheService.getScriptCache();
    var val = cache.get('cooldown_' + provider);
    return val !== null;
  } catch (e) {
    return false; // CacheService unavailable — don't block
  }
}

function setProviderCooldown(provider, seconds) {
  try {
    var cache = CacheService.getScriptCache();
    cache.put('cooldown_' + provider, 'exhausted', seconds || 60);
    Logger.log('[CACHE] Set cooldown: ' + provider + ' for ' + seconds + 's');
  } catch (e) {
    Logger.log('[CACHE] Failed to set cooldown: ' + e.toString());
  }
}

// Parse a Google Gemini response into structured result
function parseGoogleResponse(resp, model) {
  var data = JSON.parse(resp.getContentText());
  if (!data.candidates || data.candidates.length === 0) return null;

  var c = data.candidates[0];
  if (c.finishReason && c.finishReason !== 'STOP' && c.finishReason !== 'MAX_TOKENS') return null;
  if (!c.content || !c.content.parts || c.content.parts.length === 0) return null;

  var text = c.content.parts[0].text || '';
  text = text.trim();
  if (!text) return null;

  if (text.startsWith('```json')) text = text.substring(7);
  if (text.startsWith('```'))     text = text.substring(3);
  if (text.endsWith('```'))       text = text.slice(0, -3);
  var f = text.indexOf('{'), l = text.lastIndexOf('}');
  if (f < 0 || l <= f) return null;
  text = text.substring(f, l + 1);

  var result = JSON.parse(text.trim());
  if (typeof result !== 'object' || result === null) return null;

  result._provider = 'google_direct';
  result._model = model;
  if (result.people === undefined) result.people = 0;
  if (!result.hazards) result.hazards = [];
  if (!result.overallRisk) result.overallRisk = 'UNKNOWN';

  if (data.usageMetadata) {
    result._tokens = {
      'in':  data.usageMetadata.promptTokenCount     || 0,
      'out': data.usageMetadata.candidatesTokenCount || 0,
      total: data.usageMetadata.totalTokenCount      || 0
    };
  }
  return result;
}

// Parse an OpenRouter response into structured result
function parseOpenRouterResponse(resp) {
  var data = JSON.parse(resp.getContentText());
  if (!data.choices || data.choices.length === 0) return null;

  var text = data.choices[0].message.content.trim();
  if (text.startsWith('```json')) text = text.substring(7);
  if (text.startsWith('```'))     text = text.substring(3);
  if (text.endsWith('```'))       text = text.slice(0, -3);
  var f = text.indexOf('{'), l = text.lastIndexOf('}');
  if (f >= 0 && l > f) text = text.substring(f, l + 1);

  var result = JSON.parse(text.trim());
  result._provider = 'openrouter';
  result._model = OPENROUTER_MODEL;
  if (result.people === undefined) result.people = 0;
  if (!result.hazards) result.hazards = [];
  if (!result.overallRisk) result.overallRisk = 'UNKNOWN';
  return result;
}

function callGeminiText(prompt) {
  const primary = getAiPrimary();
  if (primary === 'google' || primary === 'google_only') {
    const g = callGoogleDirectText(prompt);
    if (g) return g;
    if (primary === 'google_only') {
      return { success: false, error: 'Google unavailable, fallback disabled' };
    }
    return callOpenRouterText(prompt);
  } else {
    const o = callOpenRouterText(prompt);
    if (o && o.success) return o;
    const g = callGoogleDirectText(prompt);
    return g || (o || { success: false, error: 'All providers failed' });
  }
}


// ============================================================
//  CLOUDINARY
// ============================================================
function uploadToCloudinary(base64Image) {
  try {
    const url = 'https://api.cloudinary.com/v1_1/' + CLOUDINARY_CLOUD_NAME + '/image/upload';
    const response = UrlFetchApp.fetch(url, {
      method: 'post',
      payload: { file: 'data:image/jpeg;base64,' + base64Image, upload_preset: CLOUDINARY_UPLOAD_PRESET },
      muteHttpExceptions: true
    });
    if (response.getResponseCode() === 200) return JSON.parse(response.getContentText()).secure_url;
    Logger.log('Cloudinary HTTP ' + response.getResponseCode() + ': '
      + response.getContentText().substring(0, 300));
    return null;
  } catch(err) {
    Logger.log('Cloudinary exception: ' + err.toString());
    return null;
  }
}


// ============================================================
//  DRIVE / SHEET HELPERS
// ============================================================
function getOrCreateDriveFolder_() {
  const folderName = 'SAIL Safety Lens Reports';
  const folders = DriveApp.getFoldersByName(folderName);
  return folders.hasNext() ? folders.next() : DriveApp.createFolder(folderName);
}

function getSheet(name) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(name);
  if (!sheet) {
    sheet = ss.insertSheet(name);
    const cols = name === SHEET_INCIDENTS ? INCIDENT_COLS :
                 name === SHEET_USERS     ? USER_COLS     :
                 name === SHEET_FEEDBACK  ? FEEDBACK_COLS :
                                            KNOWLEDGE_COLS;
    sheet.appendRow(cols);
    sheet.getRange(1,1,1,cols.length)
      .setFontWeight('bold').setBackground('#0D47A1').setFontColor('white');
    sheet.setFrozenRows(1);
    if (name === SHEET_USERS) {
      sheet.appendRow(USER_COLS.map(function(c) {
        return ({
          uid:'SYSTEM_ADMIN', name:'System Admin', designation:'Administrator',
          plant:'Corporate – Ranchi', department:'Safety HQ',
          pno:'ADMIN001', mobile:'', email:'', isAdmin:'TRUE',
          status:'active', username:'admin',
          passwordHash: simpleHash('admin'),
          createdAt: new Date().toISOString(), lastLogin:''
        })[c] || '';
      }));
      try { sheet.autoResizeColumns(1, USER_COLS.length); } catch(_) {}
    }
    if (name === SHEET_INCIDENTS) {
      try { formatIncidentsSheet(); } catch(_) {}
    }
  } else {
    // ★ v24: REPAIR headers if sheet exists but has fewer headers than expected
    const cols = name === SHEET_INCIDENTS ? INCIDENT_COLS :
                 name === SHEET_USERS     ? USER_COLS     :
                 name === SHEET_FEEDBACK  ? FEEDBACK_COLS :
                                            KNOWLEDGE_COLS;
    const existingHeaders = sheet.getRange(1, 1, 1, cols.length).getValues()[0];
    let needsRepair = false;
    for (var h = 0; h < cols.length; h++) {
      if (!existingHeaders[h] || existingHeaders[h] !== cols[h]) {
        needsRepair = true;
        break;
      }
    }
    if (needsRepair) {
      sheet.getRange(1, 1, 1, cols.length).setValues([cols]);
      sheet.getRange(1,1,1,cols.length)
        .setFontWeight('bold').setBackground('#0D47A1').setFontColor('white');
      sheet.setFrozenRows(1);
      if (name === SHEET_INCIDENTS) {
        try { formatIncidentsSheet(); } catch(_) {}
      }
    }
  }
  return sheet;
}

// ════════════════════════════════════════════════════════════════════════
//  ★ v24: MASTER DATA SYNC — single source of truth for plants/depts/WSA
//  Stored in a 'masterdata' sheet as key-value JSON rows.
// ════════════════════════════════════════════════════════════════════════
const SHEET_MASTERDATA = 'masterdata';
const MASTERDATA_KEYS = ['plants', 'departments', 'wsaCauses', 'severities', 'statuses', 'obsTypes'];

function saveMasterData(params) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(SHEET_MASTERDATA);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_MASTERDATA);
    sheet.appendRow(['key', 'value', 'updatedAt', 'updatedBy']);
    sheet.getRange(1,1,1,4).setFontWeight('bold').setBackground('#0D47A1').setFontColor('white');
    sheet.setFrozenRows(1);
  }

  var saved = [];
  var now = new Date().toISOString();
  var actor = params.updatedBy || 'admin';

  MASTERDATA_KEYS.forEach(function(key) {
    if (params[key] !== undefined && params[key] !== null) {
      var jsonVal = (typeof params[key] === 'string') ? params[key] : JSON.stringify(params[key]);
      // Find existing row for this key
      var data = sheet.getDataRange().getValues();
      var found = false;
      for (var r = 1; r < data.length; r++) {
        if (data[r][0] === key) {
          sheet.getRange(r + 1, 2).setValue(jsonVal);
          sheet.getRange(r + 1, 3).setValue(now);
          sheet.getRange(r + 1, 4).setValue(actor);
          found = true;
          break;
        }
      }
      if (!found) {
        sheet.appendRow([key, jsonVal, now, actor]);
      }
      saved.push(key);
    }
  });

  return { ok: true, saved: saved, updatedAt: now };
}

function getMasterData() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(SHEET_MASTERDATA);
  if (!sheet) {
    // No master data saved yet — return empty (clients will use defaults)
    return { ok: true, data: {}, isEmpty: true };
  }

  var data = sheet.getDataRange().getValues();
  var result = {};
  var updatedAt = '';
  for (var r = 1; r < data.length; r++) {
    var key = data[r][0];
    var val = data[r][1];
    var ts  = data[r][2];
    if (key && MASTERDATA_KEYS.indexOf(key) >= 0) {
      try {
        result[key] = JSON.parse(val);
      } catch (_) {
        result[key] = val;
      }
      if (ts && ts > updatedAt) updatedAt = ts;
    }
  }

  return { ok: true, data: result, updatedAt: updatedAt };
}

function listSheet(sheetName, cols) {
  const sheet = getSheet(sheetName);
  const data  = sheet.getDataRange().getValues();
  if (data.length <= 1) return { ok: true, items: [] };
  const headers = data[0];
  const items = [];
  for (var i = 1; i < data.length; i++) {
    const item = {};
    for (var j = 0; j < headers.length; j++) item[headers[j]] = data[i][j];
    items.push(item);
  }
  return { ok: true, items: items, count: items.length };
}

function addRow(sheetName, cols, params) {
  const sheet = getSheet(sheetName);
  sheet.appendRow(cols.map(function(c){ return params[c] !== undefined ? params[c] : ''; }));
  return { ok: true, added: true, id: params.id || params.uid };
}


// ============================================================
//  SHEET FORMATTING (v13 feature, unchanged)
// ============================================================
function makePdfHyperlink(url) {
  if (!url || typeof url !== 'string') return '';
  if (url.indexOf('http') !== 0) return url;
  const safe = url.replace(/"/g, '""');
  return '=HYPERLINK("' + safe + '","📄 View Report")';
}

function formatIncidentsSheet() {
  try {
    const sheet = getSheet(SHEET_INCIDENTS);
    const headers = sheet.getRange(1, 1, 1, INCIDENT_COLS.length)
      .getValues()[0];
    const lastRow = sheet.getLastRow();
    const numDataRows = Math.max(0, lastRow - 1);

    // ═══════════════════════════════════════════════════════════
    // ★ v22: PROFESSIONAL DASHBOARD FORMATTING
    // ═══════════════════════════════════════════════════════════

    // 1. HEADER ROW — Dark navy gradient look with clear readable labels
    const headerRange = sheet.getRange(1, 1, 1, INCIDENT_COLS.length);
    headerRange
      .setBackground('#1A237E')
      .setFontColor('#FFFFFF')
      .setFontWeight('bold')
      .setFontSize(9)
      .setFontFamily('Google Sans')
      .setHorizontalAlignment('center')
      .setVerticalAlignment('middle')
      .setWrap(true);
    sheet.setFrozenRows(1);
    sheet.setRowHeight(1, 44);

    // 2. HEADER NOTES — add tooltip descriptions without renaming columns
    // (renaming breaks upsertIncident which reads headers by name)
    const HEADER_NOTES = {
      id: 'Unique incident ID', date: 'Date & time of incident',
      title: 'Short incident title', severity: 'CRITICAL/HIGH/MEDIUM/LOW',
      riskScore: 'AI risk score 0-100', confidence: 'AI confidence %',
      pdfUrl: 'Click to open PDF report', hazardCount: 'Number of hazards detected'
    };
    headers.forEach(function(colName, idx) {
      if (HEADER_NOTES[colName]) {
        sheet.getRange(1, idx + 1).setNote(HEADER_NOTES[colName]);
      }
    });

    // 3. COLUMN WIDTHS — optimized for readability
    const WIDTHS = {
      id: 130, date: 145, title: 260, plant: 140, dept: 130,
      location: 170, severity: 95, wsaCategory: 150, obsType: 120,
      desc: 320, people: 50, immediateAction: 260, type: 110,
      status: 105, reportedBy: 140, reportedByPno: 80,
      riskScore: 70, confidence: 70, summary: 340,
      correctiveAction: 280, closedBy: 120, closingRemarks: 240,
      closedAt: 140, investigationStartedAt: 145, actionTakenAt: 145,
      hazardCount: 75, pdfUrl: 120
    };
    Object.keys(WIDTHS).forEach(function(name) {
      const idx = headers.indexOf(name);
      if (idx >= 0) sheet.setColumnWidth(idx + 1, WIDTHS[name]);
    });

    // 4. HIDE non-essential columns (data too long / not user-facing)
    const HIDDEN = ['imageBase64', 'imageHash', 'hazards', 'syncedAt'];
    HIDDEN.forEach(function(name) {
      const idx = headers.indexOf(name);
      if (idx >= 0) {
        try { sheet.hideColumns(idx + 1); } catch(_) {}
      }
    });

    // 5. DATA ROWS FORMATTING
    if (numDataRows > 0) {
      // Set default font for all data
      const allData = sheet.getRange(2, 1, numDataRows, INCIDENT_COLS.length);
      allData
        .setFontFamily('Google Sans')
        .setFontSize(9)
        .setVerticalAlignment('middle');

      // Set consistent row height for data rows
      for (var r = 2; r <= lastRow; r++) {
        sheet.setRowHeight(r, 36);
      }

      // Wrap text in long-content columns
      ['desc', 'summary', 'correctiveAction', 'immediateAction',
       'closingRemarks', 'title']
        .forEach(function(name) {
          const idx = headers.indexOf(name);
          if (idx >= 0) {
            sheet.getRange(2, idx + 1, numDataRows, 1)
              .setWrap(true)
              .setVerticalAlignment('top');
          }
        });

      // Center-align metric/badge columns
      ['severity', 'status', 'type', 'riskScore', 'confidence',
       'hazardCount', 'people']
        .forEach(function(name) {
          const idx = headers.indexOf(name);
          if (idx >= 0) {
            sheet.getRange(2, idx + 1, numDataRows, 1)
              .setHorizontalAlignment('center')
              .setFontWeight('bold');
          }
        });

      // Bold the title column
      const titleIdx = headers.indexOf('title');
      if (titleIdx >= 0) {
        sheet.getRange(2, titleIdx + 1, numDataRows, 1)
          .setFontWeight('bold')
          .setFontSize(9);
      }

      // Format date column nicely
      const dateIdx = headers.indexOf('date');
      if (dateIdx >= 0) {
        sheet.getRange(2, dateIdx + 1, numDataRows, 1)
          .setNumberFormat('dd-MMM-yyyy hh:mm')
          .setHorizontalAlignment('center');
      }

      // Format riskScore as number with color
      const riskIdx = headers.indexOf('riskScore');
      if (riskIdx >= 0) {
        sheet.getRange(2, riskIdx + 1, numDataRows, 1)
          .setNumberFormat('0')
          .setFontSize(11);
      }
    }

    // 6. CLEAR old formatting from empty rows (fix colored empty columns)
    sheet.setConditionalFormatRules([]); // clear ALL old rules first
    if (numDataRows === 0) {
      // Clear any leftover background colors from rows 2-50
      try {
        sheet.getRange(2, 1, 50, INCIDENT_COLS.length)
          .setBackground(null)
          .setFontColor(null);
      } catch(_) {}
    }

    // 7. CONDITIONAL FORMATTING — color-coded badges (only if data exists)
    const sevIdx  = headers.indexOf('severity');
    const stIdx   = headers.indexOf('status');
    const typeIdx = headers.indexOf('type');
    const fresh = [];

    if (numDataRows > 0 && sevIdx >= 0) {
      applySeverityFormatting(sheet, sevIdx, numDataRows, fresh);
    }
    if (numDataRows > 0 && stIdx >= 0) {
      applyStatusFormatting(sheet, stIdx, numDataRows, fresh);
    }
    if (numDataRows > 0 && typeIdx >= 0) {
      applyTypeFormatting(sheet, typeIdx, numDataRows, fresh);
    }

    // Risk score color gradient
    if (numDataRows > 0) {
      const riskIdx2 = headers.indexOf('riskScore');
      if (riskIdx2 >= 0) {
        applyRiskScoreFormatting(sheet, riskIdx2, numDataRows, fresh);
      }
    }

    if (fresh.length > 0) {
      sheet.setConditionalFormatRules(fresh);
    }

    // 7. ZEBRA STRIPING — alternating row colors
    if (numDataRows > 0) {
      applyBanding(sheet, numDataRows, INCIDENT_COLS.length);
    }

    // 8. PDF HYPERLINKS — clickable "📄 Open" links
    convertExistingPdfUrlsToHyperlinks(sheet, headers);

    // 9. ADD BORDER to header row
    headerRange.setBorder(true, true, true, true, false, false,
      '#0D47A1', SpreadsheetApp.BorderStyle.SOLID_MEDIUM);

    Logger.log('formatIncidentsSheet: formatted ' + numDataRows + ' data rows');
    return {
      ok: true, success: true,
      message: 'Sheet formatted (' + numDataRows + ' rows styled)',
      rowsFormatted: numDataRows
    };
  } catch (e) {
    Logger.log('formatIncidentsSheet error: ' + e.toString());
    return { ok: false, success: false, error: e.toString() };
  }
}

function applySeverityFormatting(sheet, colIdx, numDataRows, accumulator) {
  const range = sheet.getRange(2, colIdx + 1, numDataRows, 1);
  const palette = [
    { text: 'CRITICAL', bg: '#B71C1C', fg: '#FFFFFF' },
    { text: 'HIGH',     bg: '#E53935', fg: '#FFFFFF' },
    { text: 'MEDIUM',   bg: '#FB8C00', fg: '#FFFFFF' },
    { text: 'LOW',      bg: '#43A047', fg: '#FFFFFF' },
    { text: 'UNKNOWN',  bg: '#9E9E9E', fg: '#FFFFFF' }
  ];
  palette.forEach(function(p) {
    accumulator.push(
      SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo(p.text)
        .setBackground(p.bg)
        .setFontColor(p.fg)
        .setBold(true)
        .setRanges([range])
        .build()
    );
  });
}

function applyStatusFormatting(sheet, colIdx, numDataRows, accumulator) {
  const range = sheet.getRange(2, colIdx + 1, numDataRows, 1);
  const palette = [
    { text: 'OPEN',          bg: '#FFEBEE', fg: '#B71C1C' },
    { text: 'INVESTIGATING', bg: '#FFF8E1', fg: '#E65100' },
    { text: 'CLOSED',        bg: '#E8F5E9', fg: '#1B5E20' }
  ];
  palette.forEach(function(p) {
    accumulator.push(
      SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo(p.text)
        .setBackground(p.bg)
        .setFontColor(p.fg)
        .setBold(true)
        .setRanges([range])
        .build()
    );
  });
}


function applyTypeFormatting(sheet, colIdx, numDataRows, accumulator) {
  const range = sheet.getRange(2, colIdx + 1, numDataRows, 1);
  const palette = [
    { text: 'AI_SCAN',   bg: '#E3F2FD', fg: '#0D47A1' },
    { text: 'NEAR_MISS', bg: '#FFF3E0', fg: '#E65100' }
  ];
  palette.forEach(function(p) {
    accumulator.push(
      SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo(p.text)
        .setBackground(p.bg)
        .setFontColor(p.fg)
        .setBold(true)
        .setRanges([range])
        .build()
    );
  });
}

function applyRiskScoreFormatting(sheet, colIdx, numDataRows, accumulator) {
  const range = sheet.getRange(2, colIdx + 1, numDataRows, 1);
  accumulator.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenNumberGreaterThanOrEqualTo(75)
      .setBackground('#FFCDD2')
      .setFontColor('#B71C1C')
      .setBold(true)
      .setRanges([range])
      .build()
  );
  accumulator.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenNumberBetween(40, 74)
      .setBackground('#FFF3E0')
      .setFontColor('#E65100')
      .setBold(true)
      .setRanges([range])
      .build()
  );
  accumulator.push(
    SpreadsheetApp.newConditionalFormatRule()
      .whenNumberLessThan(40)
      .setBackground('#E8F5E9')
      .setFontColor('#1B5E20')
      .setBold(true)
      .setRanges([range])
      .build()
  );
}

function applyBanding(sheet, numDataRows, numCols) {
  try {
    const existing = sheet.getBandings();
    existing.forEach(function(b) { b.remove(); });
  } catch(_) {}
  try {
    const range = sheet.getRange(1, 1, numDataRows + 1, numCols);
    const banding = range.applyRowBanding(
      SpreadsheetApp.BandingTheme.LIGHT_GREY, true, false);
    banding.setHeaderRowColor('#1A237E');
    banding.setFirstRowColor('#FFFFFF');
    banding.setSecondRowColor('#F5F7FF');
  } catch (e) {
    Logger.log('applyBanding: ' + e.toString());
  }
}

function convertExistingPdfUrlsToHyperlinks(sheet, headers) {
  const colIdx = headers.indexOf('pdfUrl');
  if (colIdx < 0) return;
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return;

  const range = sheet.getRange(2, colIdx + 1, lastRow - 1, 1);
  const values = range.getValues();
  const formulas = range.getFormulas();
  let converted = 0;

  for (let i = 0; i < values.length; i++) {
    const val = String(values[i][0] || '');
    const formula = String(formulas[i][0] || '');
    if (formula) continue;
    if (!val || val.indexOf('http') !== 0) continue;
    sheet.getRange(2 + i, colIdx + 1)
      .setFormula(makePdfHyperlink(val));
    converted++;
  }
  if (converted > 0) {
    Logger.log('Converted ' + converted + ' pdfUrl values to hyperlinks');
  }
}


// ============================================================
//  TEST FUNCTIONS
// ============================================================
function testHealth() {
  const WEB_APP_URL = ScriptApp.getService().getUrl();
  try {
    const resp = UrlFetchApp.fetch(WEB_APP_URL + '?action=health', { muteHttpExceptions: true });
    Logger.log('Health: HTTP ' + resp.getResponseCode());
    Logger.log(resp.getContentText().substring(0, 400));
  } catch(err) { Logger.log('Health error: ' + err.toString()); }
}

function testKeys() {
  Logger.log('GOOGLE_AI_KEY:     '
    + (getGoogleKey()     ? 'PRESENT, len=' + getGoogleKey().length     : 'MISSING'));
  Logger.log('OPENROUTER_API_KEY: '
    + (getOpenRouterKey() ? 'PRESENT, len=' + getOpenRouterKey().length : 'MISSING'));
  Logger.log('AI_PRIMARY_PROVIDER: ' + getAiPrimary());
}

function testGoogleText() {
  const r = callGoogleDirectText('Say hello in one word.');
  Logger.log(JSON.stringify(r));
}

function testProviderChain() {
  Logger.log('Primary: ' + getAiPrimary());
  Logger.log('Google key: ' + (getGoogleKey() ? 'YES' : 'NO'));
  Logger.log('OpenRouter key: ' + (getOpenRouterKey() ? 'YES' : 'NO'));
  const r = callGeminiText('Respond with one word: SAIL');
  Logger.log('Result: ' + JSON.stringify(r));
}

function testClearAll() {
  const result = clearAllIncidents();
  Logger.log('clearAllIncidents: ' + JSON.stringify(result));
}

function testListIncidents() {
  const result = listSheet(SHEET_INCIDENTS, INCIDENT_COLS);
  Logger.log('Count: ' + result.count);
}

function testPromptVersion() {
  const p = getSailPrompt('sail_full');
  Logger.log('Prompt length: ' + p.length);
  Logger.log('Has OBSERVE FIRST: ' + p.includes('STEP 1'));
  Logger.log('Has GROUNDING RULES: ' + p.includes('GROUNDING RULES'));
}

function testFormatSheet() {
  const result = formatIncidentsSheet();
  Logger.log('formatIncidentsSheet result: ' + JSON.stringify(result));
}
