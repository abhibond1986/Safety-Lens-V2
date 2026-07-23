# User Monitoring System - Setup and Usage Guide

## Overview

The User Monitoring System tracks user registrations, login/logout timestamps, and session activity in the Safety Lens V2 application. This guide explains how to set up and use the monitoring system.

## Features

- **User Registration Tracking**: Monitor when users first register in the app
- **Login/Logout Timestamps**: Track every login and logout event with precise timestamps
- **Session Duration**: Calculate and store total session time per user
- **Active Users View**: See who is currently online (active within last 15 minutes)
- **User Analytics**: Track incidents reported, AI scans performed, near misses reported
- **Device Information**: Store device type, OS, and app version for each session
- **Detailed Event Log**: Complete audit trail of all login/logout events

## Database Setup

### Step 1: Run the SQL Setup Script

1. Open your Supabase Dashboard
2. Navigate to **SQL Editor**
3. Click **New Query**
4. Copy the contents of `supabase_user_monitoring_setup.sql`
5. Paste into the query editor
6. Click **Run**

The script will create:
- `user_sessions` table - Main user tracking table
- `session_logs` table - Detailed event log
- `active_users` view - Currently online users
- `user_stats_summary` view - Aggregate statistics
- Helper functions for login/logout tracking

### Step 2: Verify Setup

Run this query to verify the tables were created:

```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('user_sessions', 'session_logs');
```

You should see both tables listed.

## Database Schema

### user_sessions Table

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| user_id | TEXT | User ID or PNO (unique) |
| user_name | TEXT | Full name |
| user_email | TEXT | Email address |
| plant_code | TEXT | Plant/location code |
| is_admin | BOOLEAN | Admin flag |
| is_contractor | BOOLEAN | Contractor flag |
| registered_at | TIMESTAMPTZ | First registration timestamp |
| last_login_at | TIMESTAMPTZ | Most recent login |
| last_logout_at | TIMESTAMPTZ | Most recent logout |
| last_activity_at | TIMESTAMPTZ | Last app activity |
| device_info | JSONB | Device metadata |
| login_count | INTEGER | Total number of logins |
| total_session_duration_minutes | INTEGER | Cumulative session time |
| incidents_reported | INTEGER | Total incidents reported |
| ai_scans_performed | INTEGER | Total AI scans |
| near_misses_reported | INTEGER | Total near misses |
| created_at | TIMESTAMPTZ | Record creation time |
| updated_at | TIMESTAMPTZ | Last update time |

### session_logs Table

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| user_id | TEXT | User ID or PNO |
| user_name | TEXT | Full name |
| event_type | TEXT | 'login', 'logout', 'register' |
| event_timestamp | TIMESTAMPTZ | When the event occurred |
| device_info | JSONB | Device metadata |
| session_duration_minutes | INTEGER | Duration for logout events |
| ip_address | TEXT | Optional IP tracking |
| created_at | TIMESTAMPTZ | Record creation time |

## Integration with Flutter App

### 1. Add Supabase Client (if not already present)

Add to your `pubspec.yaml`:

```yaml
dependencies:
  supabase_flutter: ^2.0.0
```

### 2. Track User Login

Call this when a user successfully logs in:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> trackUserLogin(Map<String, dynamic> user) async {
  final supabase = Supabase.instance.client;
  
  final deviceInfo = {
    'platform': Platform.operatingSystem,
    'version': Platform.operatingSystemVersion,
    'app_version': '2.0.0', // Replace with your actual version
  };

  await supabase.rpc('record_user_login', params: {
    'p_user_id': user['pno'] ?? user['id'],
    'p_user_name': user['name'],
    'p_user_email': user['email'],
    'p_plant_code': user['plant'],
    'p_is_admin': user['isAdmin'] ?? false,
    'p_is_contractor': user['isContractor'] ?? false,
    'p_device_info': deviceInfo,
  });
}
```

### 3. Track User Logout

Call this when a user logs out:

```dart
Future<void> trackUserLogout(String userId, int sessionDurationMinutes) async {
  final supabase = Supabase.instance.client;
  
  await supabase.rpc('record_user_logout', params: {
    'p_user_id': userId,
    'p_session_duration_minutes': sessionDurationMinutes,
  });
}
```

### 4. Update User Activity (Keep-Alive)

Call this periodically (e.g., every 5 minutes) while the app is active:

```dart
Future<void> updateUserActivity(String userId) async {
  final supabase = Supabase.instance.client;
  
  await supabase.rpc('update_user_activity', params: {
    'p_user_id': userId,
  });
}
```

### 5. Example: Complete Session Management

```dart
class SessionManager {
  DateTime? _sessionStartTime;
  Timer? _keepAliveTimer;
  
  Future<void> startSession(Map<String, dynamic> user) async {
    _sessionStartTime = DateTime.now();
    
    // Track login
    await trackUserLogin(user);
    
    // Start keep-alive timer (every 5 minutes)
    _keepAliveTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => updateUserActivity(user['pno']),
    );
  }
  
  Future<void> endSession(String userId) async {
    _keepAliveTimer?.cancel();
    
    if (_sessionStartTime != null) {
      final duration = DateTime.now().difference(_sessionStartTime!).inMinutes;
      await trackUserLogout(userId, duration);
    }
  }
}
```

## Monitoring Dashboard Queries

### View Currently Active Users

```sql
SELECT * FROM active_users;
```

Returns all users who have been active in the last 15 minutes.

### View User Statistics Summary

```sql
SELECT * FROM user_stats_summary;
```

Returns aggregate statistics across all users.

### View Recent Logins

```sql
SELECT 
  user_name,
  event_timestamp,
  device_info->>'platform' as platform,
  device_info->>'app_version' as app_version
FROM session_logs
WHERE event_type = 'login'
ORDER BY event_timestamp DESC
LIMIT 50;
```

### View User Session History

```sql
SELECT 
  user_name,
  last_login_at,
  last_logout_at,
  login_count,
  total_session_duration_minutes,
  incidents_reported,
  ai_scans_performed,
  near_misses_reported
FROM user_sessions
ORDER BY last_login_at DESC;
```

### Find Inactive Users (Not logged in for 30+ days)

```sql
SELECT 
  user_id,
  user_name,
  plant_code,
  last_login_at,
  EXTRACT(DAY FROM (NOW() - last_login_at)) as days_since_login
FROM user_sessions
WHERE last_login_at < NOW() - INTERVAL '30 days'
ORDER BY last_login_at ASC;
```

### Users by Plant

```sql
SELECT 
  plant_code,
  COUNT(*) as total_users,
  COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') as active_last_week
FROM user_sessions
WHERE plant_code IS NOT NULL
GROUP BY plant_code
ORDER BY total_users DESC;
```

### Top Active Users (by incidents reported)

```sql
SELECT 
  user_name,
  plant_code,
  incidents_reported,
  ai_scans_performed,
  near_misses_reported,
  login_count
FROM user_sessions
ORDER BY incidents_reported DESC
LIMIT 20;
```

## Building an Admin Dashboard

You can build a Flutter admin dashboard that displays this data:

```dart
// Example: Fetch active users
Future<List<Map<String, dynamic>>> getActiveUsers() async {
  final supabase = Supabase.instance.client;
  
  final response = await supabase
      .from('active_users')
      .select()
      .order('last_activity_at', ascending: false);
      
  return List<Map<String, dynamic>>.from(response);
}

// Example: Fetch user stats
Future<Map<String, dynamic>> getUserStats() async {
  final supabase = Supabase.instance.client;
  
  final response = await supabase
      .from('user_stats_summary')
      .select()
      .single();
      
  return response;
}
```

## Real-time Updates

Enable real-time subscriptions for live monitoring:

```dart
final supabase = Supabase.instance.client;

// Subscribe to user session changes
final subscription = supabase
    .from('user_sessions')
    .stream(primaryKey: ['id'])
    .listen((data) {
      // Update UI with new data
      print('User sessions updated: ${data.length}');
    });

// Don't forget to cancel when done
subscription.cancel();
```

## Best Practices

1. **Call trackUserLogin()** immediately after successful authentication
2. **Call trackUserLogout()** when user explicitly logs out OR when app is terminated
3. **Update activity regularly** (every 5 minutes) to maintain accurate "online" status
4. **Track analytics** by incrementing counters when users create incidents/scans
5. **Monitor query performance** on large datasets - indexes are already created for common queries

## Security Considerations

- Row Level Security (RLS) is enabled on both tables
- All users can read session data (needed for admin dashboards)
- Users can only insert/update their own records
- Consider adding IP address tracking for additional security audit
- Device info helps identify suspicious login patterns

## Troubleshooting

### Issue: Function not found error

**Solution**: Make sure you ran the complete SQL setup script. The helper functions are created at the bottom of the script.

### Issue: Permission denied errors

**Solution**: Check that RLS policies are correctly applied. Run:

```sql
SELECT * FROM pg_policies WHERE tablename IN ('user_sessions', 'session_logs');
```

### Issue: active_users view is empty

**Solution**: The view only shows users active in the last 15 minutes. Check the base table:

```sql
SELECT COUNT(*) FROM user_sessions WHERE last_login_at IS NOT NULL;
```

## Future Enhancements

Consider adding:
- Geographic location tracking (lat/long from device)
- Push notification tracking (delivered/read status)
- App crash reports linked to sessions
- Session replay data for debugging
- A/B test variant tracking per user
- Feature usage analytics per session

## Support

For questions or issues, contact the development team or refer to the main Safety Lens documentation.
