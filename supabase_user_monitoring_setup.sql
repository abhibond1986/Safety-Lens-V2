-- ═══════════════════════════════════════════════════════════════════════════
--  SAIL Safety Lens — User Monitoring Table Setup
--  Purpose: Track user registrations, login/logout timestamps, and session data
--  Run this in Supabase dashboard: SQL Editor → New query → paste → Run
--  Safe to re-run (idempotent)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── STEP 1: Create user_sessions table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL UNIQUE,             -- User ID or PNO (unique per user)
  user_name TEXT,                           -- Full name
  user_email TEXT,                          -- Email address
  plant_code TEXT,                          -- Plant/location code
  is_admin BOOLEAN DEFAULT false,           -- Admin flag
  is_contractor BOOLEAN DEFAULT false,      -- Contractor flag

  -- Registration tracking
  registered_at TIMESTAMPTZ,                -- First time user registered

  -- Session tracking
  last_login_at TIMESTAMPTZ,                -- Most recent login timestamp
  last_logout_at TIMESTAMPTZ,               -- Most recent logout timestamp
  last_activity_at TIMESTAMPTZ,             -- Last app activity (for online status)

  -- Session metadata
  device_info JSONB,                        -- Device type, OS, app version
  login_count INTEGER DEFAULT 0,            -- Total number of logins
  total_session_duration_minutes INTEGER DEFAULT 0, -- Cumulative session time

  -- Analytics
  incidents_reported INTEGER DEFAULT 0,     -- Total incidents reported by user
  ai_scans_performed INTEGER DEFAULT 0,     -- Total AI scans performed
  near_misses_reported INTEGER DEFAULT 0,   -- Total near misses reported

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index on user_id for fast lookups
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);

-- Create index on last_login_at for sorting by recent activity
CREATE INDEX IF NOT EXISTS idx_user_sessions_last_login ON user_sessions(last_login_at DESC);

-- Create index on plant_code for filtering by location
CREATE INDEX IF NOT EXISTS idx_user_sessions_plant ON user_sessions(plant_code);

-- ── STEP 2: Create updated_at trigger ────────────────────────────────────────
-- Auto-update the updated_at timestamp whenever a row is modified
CREATE OR REPLACE FUNCTION update_user_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_user_sessions_updated_at ON user_sessions;
CREATE TRIGGER trigger_user_sessions_updated_at
  BEFORE UPDATE ON user_sessions
  FOR EACH ROW
  EXECUTE FUNCTION update_user_sessions_updated_at();

-- ── STEP 3: Create session_logs table (optional detailed logging) ────────────
-- This table stores individual login/logout events for detailed audit trail
CREATE TABLE IF NOT EXISTS session_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  user_name TEXT,
  event_type TEXT NOT NULL,                 -- 'login', 'logout', 'register'
  event_timestamp TIMESTAMPTZ DEFAULT NOW(),
  device_info JSONB,                        -- Device metadata
  session_duration_minutes INTEGER,         -- Duration for logout events
  ip_address TEXT,                          -- Optional IP tracking

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index on user_id and event_timestamp for fast queries
CREATE INDEX IF NOT EXISTS idx_session_logs_user_id ON session_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_session_logs_timestamp ON session_logs(event_timestamp DESC);

-- ── STEP 4: Set up RLS (Row Level Security) policies ─────────────────────────
-- Allow authenticated users to read all session data (for admin dashboard)
-- Allow users to update their own session records

ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_logs ENABLE ROW LEVEL SECURITY;

-- Policy: Allow all reads (for admin monitoring dashboard)
DROP POLICY IF EXISTS "user_sessions_read_all" ON user_sessions;
CREATE POLICY "user_sessions_read_all" ON user_sessions
  FOR SELECT USING (true);

-- Policy: Allow authenticated users to insert/update their own records
DROP POLICY IF EXISTS "user_sessions_insert" ON user_sessions;
CREATE POLICY "user_sessions_insert" ON user_sessions
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "user_sessions_update_own" ON user_sessions;
CREATE POLICY "user_sessions_update_own" ON user_sessions
  FOR UPDATE USING (true);

-- Session logs policies
DROP POLICY IF EXISTS "session_logs_read_all" ON session_logs;
CREATE POLICY "session_logs_read_all" ON session_logs
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "session_logs_insert" ON session_logs;
CREATE POLICY "session_logs_insert" ON session_logs
  FOR INSERT WITH CHECK (true);

-- ── STEP 5: Create helper views for common queries ───────────────────────────

-- View: Currently active users (logged in within last 15 minutes)
CREATE OR REPLACE VIEW active_users AS
SELECT
  user_id,
  user_name,
  user_email,
  plant_code,
  is_admin,
  is_contractor,
  last_login_at,
  last_activity_at,
  EXTRACT(EPOCH FROM (NOW() - last_login_at))/60 AS minutes_since_login
FROM user_sessions
WHERE last_login_at IS NOT NULL
  AND (last_logout_at IS NULL OR last_login_at > last_logout_at)
  AND last_activity_at > NOW() - INTERVAL '15 minutes'
ORDER BY last_activity_at DESC;

-- View: User statistics summary
CREATE OR REPLACE VIEW user_stats_summary AS
SELECT
  COUNT(*) AS total_users,
  COUNT(*) FILTER (WHERE is_admin = true) AS admin_count,
  COUNT(*) FILTER (WHERE is_contractor = true) AS contractor_count,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '24 hours') AS active_last_24h,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') AS active_last_week,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '30 days') AS active_last_month,
  SUM(incidents_reported) AS total_incidents_reported,
  SUM(ai_scans_performed) AS total_ai_scans,
  SUM(near_misses_reported) AS total_near_misses,
  SUM(login_count) AS total_logins
FROM user_sessions;

-- ── STEP 6: Sample helper functions ──────────────────────────────────────────

-- Function: Record a user login
CREATE OR REPLACE FUNCTION record_user_login(
  p_user_id TEXT,
  p_user_name TEXT DEFAULT NULL,
  p_user_email TEXT DEFAULT NULL,
  p_plant_code TEXT DEFAULT NULL,
  p_is_admin BOOLEAN DEFAULT false,
  p_is_contractor BOOLEAN DEFAULT false,
  p_device_info JSONB DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_session_id UUID;
BEGIN
  -- Insert or update user_sessions
  INSERT INTO user_sessions (
    user_id, user_name, user_email, plant_code, is_admin, is_contractor,
    last_login_at, last_activity_at, login_count, device_info
  )
  VALUES (
    p_user_id, p_user_name, p_user_email, p_plant_code, p_is_admin, p_is_contractor,
    NOW(), NOW(), 1, p_device_info
  )
  ON CONFLICT (user_id) DO UPDATE SET
    user_name = COALESCE(p_user_name, user_sessions.user_name),
    user_email = COALESCE(p_user_email, user_sessions.user_email),
    plant_code = COALESCE(p_plant_code, user_sessions.plant_code),
    is_admin = p_is_admin,
    is_contractor = p_is_contractor,
    last_login_at = NOW(),
    last_activity_at = NOW(),
    login_count = user_sessions.login_count + 1,
    device_info = COALESCE(p_device_info, user_sessions.device_info)
  RETURNING id INTO v_session_id;

  -- Log the event
  INSERT INTO session_logs (user_id, user_name, event_type, device_info)
  VALUES (p_user_id, p_user_name, 'login', p_device_info);

  RETURN v_session_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Record a user logout
CREATE OR REPLACE FUNCTION record_user_logout(
  p_user_id TEXT,
  p_session_duration_minutes INTEGER DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  -- Update user_sessions
  UPDATE user_sessions
  SET
    last_logout_at = NOW(),
    total_session_duration_minutes = total_session_duration_minutes + COALESCE(p_session_duration_minutes, 0)
  WHERE user_id = p_user_id;

  -- Log the event
  INSERT INTO session_logs (user_id, event_type, session_duration_minutes)
  SELECT user_name, 'logout', p_session_duration_minutes
  FROM user_sessions
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function: Update user activity (keep-alive)
CREATE OR REPLACE FUNCTION update_user_activity(p_user_id TEXT)
RETURNS VOID AS $$
BEGIN
  UPDATE user_sessions
  SET last_activity_at = NOW()
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- ══════════════════════════════════════════════════════════════════════════
--  SETUP COMPLETE
--
--  Tables created:
--    • user_sessions - Main user tracking table
--    • session_logs  - Detailed event log
--
--  Views created:
--    • active_users       - Currently online users
--    • user_stats_summary - Aggregate statistics
--
--  Helper functions:
--    • record_user_login(user_id, ...) - Log a user login
--    • record_user_logout(user_id, duration) - Log a user logout
--    • update_user_activity(user_id) - Update last activity timestamp
--
--  Usage in app:
--    1. On login:  SELECT record_user_login('USER123', 'John Doe', ...);
--    2. On logout: SELECT record_user_logout('USER123', 45);
--    3. Periodic:  SELECT update_user_activity('USER123');
--
--  Query examples:
--    • Active users:   SELECT * FROM active_users;
--    • User stats:     SELECT * FROM user_stats_summary;
--    • Recent logins:  SELECT * FROM session_logs WHERE event_type='login'
--                      ORDER BY event_timestamp DESC LIMIT 50;
-- ══════════════════════════════════════════════════════════════════════════
