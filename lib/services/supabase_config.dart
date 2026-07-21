// lib/services/supabase_config.dart
// Central config + feature flag for the Supabase backend migration.
//
// SET-UP (see SUPABASE_MIGRATION_GUIDE.md):
//   1. Create the Supabase project + tables + storage bucket.
//   2. Paste your Project URL and anon public key below.
//   3. Set [enabled] = true to route the app through Supabase.
//
// SAFE ROLLBACK: set [enabled] = false and the app reverts to the previous
// Google Sheets (Apps Script) backend with no data loss.

class SupabaseConfig {
  /// Your Supabase Project URL.
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mptdergmcakhufsmcogd.supabase.co',
  );

  /// Supabase PUBLISHABLE key (sb_publishable_...). Safe to ship in the client;
  /// it only allows what your table policies / RLS permit.
  /// NEVER put the secret key (sb_secret_...) here — it bypasses all security.
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1wdGRlcmdtY2FraHVmc21jb2dkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM1MTg0ODAsImV4cCI6MjA5OTA5NDQ4MH0.zkK7JSvp6AJ1JiVqCjd130f9PwS4412VygPhGX1ga4Y',
  );

  /// Master switch. When false (or when url/anonKey are blank), the app uses
  /// the legacy Google Sheets backend. Flip to true after configuring above.
  static const bool _requested = true;

  /// True only when the flag is on AND real credentials are present.
  static bool get enabled =>
      _requested && url.isNotEmpty && anonKey.isNotEmpty;

  /// Storage bucket that holds incident evidence photos.
  static const String imageBucket = 'incident-images';
}
