package com.sail.safety

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

/**
 * Receives the result of the silent APK installation.
 * On success, the app will restart automatically.
 * On failure, it logs the error for debugging.
 */
class InstallResultReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AppUpdater"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // The system requires user confirmation (older Android or first-time install)
                // Launch the confirmation activity
                val confirmIntent = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirmIntent != null) {
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirmIntent)
                }
                Log.i(TAG, "Install requires user confirmation")
            }
            PackageInstaller.STATUS_SUCCESS -> {
                Log.i(TAG, "APK installed successfully — app will restart")
                // Clean up the downloaded APK
                cleanupApk(context)
            }
            PackageInstaller.STATUS_FAILURE,
            PackageInstaller.STATUS_FAILURE_ABORTED,
            PackageInstaller.STATUS_FAILURE_BLOCKED,
            PackageInstaller.STATUS_FAILURE_CONFLICT,
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE,
            PackageInstaller.STATUS_FAILURE_INVALID,
            PackageInstaller.STATUS_FAILURE_STORAGE -> {
                Log.e(TAG, "Install failed [$status]: $message")
                cleanupApk(context)
            }
            else -> {
                Log.w(TAG, "Install unknown status [$status]: $message")
            }
        }
    }

    private fun cleanupApk(context: Context) {
        try {
            val apkFile = java.io.File(context.cacheDir, "safety_lens_update.apk")
            if (apkFile.exists()) {
                apkFile.delete()
                Log.d(TAG, "Cleaned up APK file")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to cleanup APK: ${e.message}")
        }
    }
}
