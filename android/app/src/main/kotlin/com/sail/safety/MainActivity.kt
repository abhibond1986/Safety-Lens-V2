package com.sail.safety

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.sail.safety/app_updater"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val apkPath = call.argument<String>("apkPath")
                        if (apkPath != null) {
                            try {
                                installApkSilently(apkPath)
                                result.success("install_triggered")
                            } catch (e: Exception) {
                                result.error("INSTALL_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARG", "apkPath is required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Uses Android PackageInstaller API to install the APK.
     * On devices where the app has been granted REQUEST_INSTALL_PACKAGES
     * permission, this will install with minimal or no user interaction.
     *
     * Android 12+ with the same signing key = fully silent.
     * Older versions = one-tap system confirmation.
     */
    private fun installApkSilently(apkPath: String) {
        val apkFile = File(apkPath)
        if (!apkFile.exists()) {
            throw Exception("APK file not found at: $apkPath")
        }

        val packageInstaller: PackageInstaller = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        )

        // Set the package name so the system knows it's an update
        params.setAppPackageName("com.sail.safety")

        // On Android 12+, request user pre-approval for seamless updates
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(
                PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED
            )
        }

        // On Android 14+, set the installer as update owner for silent updates
        if (Build.VERSION.SDK_INT >= 34) {
            params.setInstallerPackageName(packageName)
        }

        val sessionId = packageInstaller.createSession(params)
        val session = packageInstaller.openSession(sessionId)

        // Write APK to the install session
        session.openWrite("safety_lens_update.apk", 0, apkFile.length()).use { outputStream ->
            FileInputStream(apkFile).use { inputStream ->
                inputStream.copyTo(outputStream)
            }
            session.fsync(outputStream)
        }

        // Create a PendingIntent for the install result
        val intent = Intent(this, InstallResultReceiver::class.java).apply {
            action = "com.sail.safety.INSTALL_RESULT"
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            sessionId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        // Commit the session — this triggers the install
        session.commit(pendingIntent.intentSender)
    }
}
