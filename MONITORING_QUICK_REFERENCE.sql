-- ═══════════════════════════════════════════════════════════════════════════
--  Safety Lens V2 - User Monitoring Quick Reference
--  Copy-paste queries for common monitoring tasks
-- ═══════════════════════════════════════════════════════════════════════════

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ MOST COMMON QUERIES                                                       ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- 1. WHO IS CURRENTLY ONLINE? (Active in last 15 minutes)
SELECT
  user_name,
  plant_code,
  last_login_at,
  last_activity_at,
  ROUND(EXTRACT(EPOCH FROM (NOW() - last_login_at))/60, 0) AS minutes_online
FROM active_users
ORDER BY last_activity_at DESC;

-- 2. OVERALL STATISTICS
SELECT * FROM user_stats_summary;

-- 3. ALL REGISTERED USERS (sorted by most recent)
SELECT
  user_id,
  user_name,
  plant_code,
  is_admin,
  is_contractor,
  last_login_at,
  login_count,
  incidents_reported,
  ai_scans_performed
FROM user_sessions
ORDER BY last_login_at DESC NULLS LAST;

-- 4. RECENT LOGINS (Last 24 hours)
SELECT
  user_name,
  plant_code,
  last_login_at,
  device_info->>'platform' AS platform,
  device_info->>'app_version' AS app_version
FROM user_sessions
WHERE last_login_at > NOW() - INTERVAL '24 hours'
ORDER BY last_login_at DESC;

-- 5. RECENT LOGIN/LOGOUT EVENTS
SELECT
  user_name,
  event_type,
  event_timestamp,
  session_duration_minutes,
  device_info->>'platform' AS platform
FROM session_logs
ORDER BY event_timestamp DESC
LIMIT 50;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ USER ACTIVITY ANALYSIS                                                    ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Most Active Users (by total logins)
SELECT
  user_name,
  plant_code,
  login_count,
  total_session_duration_minutes,
  ROUND(total_session_duration_minutes::numeric / login_count, 1) AS avg_session_minutes
FROM user_sessions
WHERE login_count > 0
ORDER BY login_count DESC
LIMIT 20;

-- Most Productive Users (by incidents reported)
SELECT
  user_name,
  plant_code,
  incidents_reported,
  ai_scans_performed,
  near_misses_reported,
  (incidents_reported + near_misses_reported) AS total_reports
FROM user_sessions
WHERE incidents_reported > 0 OR near_misses_reported > 0
ORDER BY total_reports DESC
LIMIT 20;

-- Inactive Users (not logged in for 30+ days)
SELECT
  user_id,
  user_name,
  plant_code,
  last_login_at,
  EXTRACT(DAY FROM (NOW() - last_login_at))::integer AS days_since_login
FROM user_sessions
WHERE last_login_at < NOW() - INTERVAL '30 days'
ORDER BY last_login_at ASC;

-- Never Logged In (registered but never used the app)
SELECT
  user_id,
  user_name,
  plant_code,
  created_at AS registered_at
FROM user_sessions
WHERE last_login_at IS NULL
ORDER BY created_at DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ PLANT-WISE ANALYSIS                                                       ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Users by Plant
SELECT
  plant_code,
  COUNT(*) AS total_users,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') AS active_last_7_days,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '30 days') AS active_last_30_days,
  COUNT(*) FILTER (WHERE is_admin = true) AS admin_count,
  COUNT(*) FILTER (WHERE is_contractor = true) AS contractor_count,
  SUM(incidents_reported) AS total_incidents,
  SUM(ai_scans_performed) AS total_ai_scans
FROM user_sessions
WHERE plant_code IS NOT NULL
GROUP BY plant_code
ORDER BY total_users DESC;

-- Most Active Plant (by user activity)
SELECT
  plant_code,
  COUNT(*) AS active_users,
  SUM(login_count) AS total_logins,
  SUM(incidents_reported) AS total_incidents
FROM user_sessions
WHERE last_login_at > NOW() - INTERVAL '7 days'
GROUP BY plant_code
ORDER BY active_users DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ TIME-BASED ANALYSIS                                                       ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Login Activity by Hour (last 24 hours)
SELECT
  EXTRACT(HOUR FROM event_timestamp) AS hour_of_day,
  COUNT(*) AS login_count
FROM session_logs
WHERE event_type = 'login'
  AND event_timestamp > NOW() - INTERVAL '24 hours'
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- Login Activity by Day (last 7 days)
SELECT
  DATE(event_timestamp) AS login_date,
  COUNT(*) AS login_count,
  COUNT(DISTINCT user_id) AS unique_users
FROM session_logs
WHERE event_type = 'login'
  AND event_timestamp > NOW() - INTERVAL '7 days'
GROUP BY login_date
ORDER BY login_date DESC;

-- Average Session Duration by User
SELECT
  user_name,
  plant_code,
  login_count,
  total_session_duration_minutes,
  ROUND(total_session_duration_minutes::numeric / NULLIF(login_count, 0), 1) AS avg_session_minutes
FROM user_sessions
WHERE login_count > 0
ORDER BY avg_session_minutes DESC
LIMIT 20;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ ADMIN & CONTRACTOR ANALYSIS                                               ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- All Admins
SELECT
  user_id,
  user_name,
  plant_code,
  last_login_at,
  login_count
FROM user_sessions
WHERE is_admin = true
ORDER BY last_login_at DESC;

-- All Contractors
SELECT
  user_id,
  user_name,
  plant_code,
  last_login_at,
  login_count,
  incidents_reported
FROM user_sessions
WHERE is_contractor = true
ORDER BY last_login_at DESC;

-- Admin Activity Comparison
SELECT
  'Admins' AS user_type,
  COUNT(*) AS total_users,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') AS active_last_7_days,
  SUM(login_count) AS total_logins,
  SUM(incidents_reported) AS total_incidents
FROM user_sessions
WHERE is_admin = true
UNION ALL
SELECT
  'Regular Users' AS user_type,
  COUNT(*) AS total_users,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') AS active_last_7_days,
  SUM(login_count) AS total_logins,
  SUM(incidents_reported) AS total_incidents
FROM user_sessions
WHERE is_admin = false AND is_contractor = false
UNION ALL
SELECT
  'Contractors' AS user_type,
  COUNT(*) AS total_users,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') AS active_last_7_days,
  SUM(login_count) AS total_logins,
  SUM(incidents_reported) AS total_incidents
FROM user_sessions
WHERE is_contractor = true;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ DEVICE & PLATFORM ANALYSIS                                                ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Users by Platform
SELECT
  device_info->>'platform' AS platform,
  COUNT(*) AS user_count,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') AS active_last_7_days
FROM user_sessions
WHERE device_info IS NOT NULL
GROUP BY device_info->>'platform'
ORDER BY user_count DESC;

-- Users by App Version
SELECT
  device_info->>'app_version' AS app_version,
  COUNT(*) AS user_count,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') AS active_last_7_days
FROM user_sessions
WHERE device_info IS NOT NULL
GROUP BY device_info->>'app_version'
ORDER BY user_count DESC;

-- Recent Logins with Device Details
SELECT
  user_name,
  last_login_at,
  device_info->>'platform' AS platform,
  device_info->>'version' AS os_version,
  device_info->>'app_version' AS app_version
FROM user_sessions
WHERE last_login_at > NOW() - INTERVAL '24 hours'
ORDER BY last_login_at DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ SEARCH & FILTER QUERIES                                                   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Find User by Name (partial match)
SELECT
  user_id,
  user_name,
  plant_code,
  last_login_at,
  login_count,
  incidents_reported
FROM user_sessions
WHERE user_name ILIKE '%search_term%'  -- Replace 'search_term' with actual name
ORDER BY last_login_at DESC;

-- Find User by Plant
SELECT
  user_id,
  user_name,
  plant_code,
  last_login_at,
  login_count
FROM user_sessions
WHERE plant_code = 'BSP'  -- Replace 'BSP' with actual plant code
ORDER BY last_login_at DESC;

-- Users Who Never Reported Incidents
SELECT
  user_id,
  user_name,
  plant_code,
  last_login_at,
  login_count
FROM user_sessions
WHERE incidents_reported = 0
  AND ai_scans_performed = 0
  AND near_misses_reported = 0
  AND login_count > 0
ORDER BY login_count DESC;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ DAILY MONITORING DASHBOARD QUERIES                                        ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Today's Summary
SELECT
  'Today' AS period,
  COUNT(DISTINCT user_id) AS unique_logins,
  COUNT(*) AS total_logins,
  SUM(session_duration_minutes) AS total_minutes
FROM session_logs
WHERE event_timestamp::date = CURRENT_DATE
  AND event_type = 'login';

-- This Week's Summary
SELECT
  'This Week' AS period,
  COUNT(DISTINCT user_id) AS unique_users,
  COUNT(*) AS total_logins,
  SUM(session_duration_minutes) AS total_minutes
FROM session_logs
WHERE event_timestamp > date_trunc('week', CURRENT_DATE)
  AND event_type = 'login';

-- Growth Metrics (compare this week vs last week)
WITH this_week AS (
  SELECT COUNT(DISTINCT user_id) AS users FROM session_logs
  WHERE event_timestamp > date_trunc('week', CURRENT_DATE)
    AND event_type = 'login'
),
last_week AS (
  SELECT COUNT(DISTINCT user_id) AS users FROM session_logs
  WHERE event_timestamp > date_trunc('week', CURRENT_DATE) - INTERVAL '7 days'
    AND event_timestamp < date_trunc('week', CURRENT_DATE)
    AND event_type = 'login'
)
SELECT
  tw.users AS this_week_users,
  lw.users AS last_week_users,
  tw.users - lw.users AS growth,
  ROUND(((tw.users - lw.users)::numeric / NULLIF(lw.users, 0) * 100), 1) AS growth_percent
FROM this_week tw, last_week lw;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ DATA MANAGEMENT                                                           ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Clean Up Old Session Logs (older than 90 days)
-- CAUTION: This permanently deletes data!
-- DELETE FROM session_logs
-- WHERE event_timestamp < NOW() - INTERVAL '90 days';

-- Reset User Statistics (for testing only!)
-- CAUTION: This resets all counters to zero!
-- UPDATE user_sessions
-- SET login_count = 0,
--     total_session_duration_minutes = 0,
--     incidents_reported = 0,
--     ai_scans_performed = 0,
--     near_misses_reported = 0;


-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║ MANUAL OPERATIONS (Use with caution!)                                    ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- Manually record a login (for testing)
-- SELECT record_user_login(
--   'TEST123',           -- user_id
--   'Test User',         -- user_name
--   'test@sail.in',      -- user_email
--   'BSP',               -- plant_code
--   false,               -- is_admin
--   false,               -- is_contractor
--   '{"platform": "android", "app_version": "2.0.0"}'::jsonb  -- device_info
-- );

-- Manually record a logout (for testing)
-- SELECT record_user_logout('TEST123', 45);  -- user_id, session_duration_minutes

-- Manually update activity (for testing)
-- SELECT update_user_activity('TEST123');

-- Delete a specific user (CAUTION!)
-- DELETE FROM session_logs WHERE user_id = 'USER123';
-- DELETE FROM user_sessions WHERE user_id = 'USER123';


-- ═══════════════════════════════════════════════════════════════════════════
--  QUICK TIPS
--
--  1. Save commonly used queries as "Saved Queries" in Supabase dashboard
--  2. Use LIMIT and pagination for large datasets
--  3. Add WHERE clauses to filter by date range for better performance
--  4. Use the views (active_users, user_stats_summary) for fastest results
--  5. Consider materializing complex queries if they run too slowly
-- ═══════════════════════════════════════════════════════════════════════════
