package com.sail.safety

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
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
                                installApk(apkPath)
                                result.success("install_triggered")
                            } catch (e: Exception) {
                                result.error("INSTALL_ERROR", e.message, null)
                            }
                        } else {
                            result.error("INVALID_ARG", "apkPath is required", null)
                        }
                    }
                    "getAppVersion" -> {
                        try {
                            val pInfo = packageManager.getPackageInfo(packageName, 0)
                            result.success(pInfo.versionName ?: "1.0.0")
                        } catch (e: Exception) {
                            result.success("1.0.0")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Install APK with best available method:
     * 1. Try PackageInstaller (silent on Android 12+ with same key)
     * 2. Fall back to ACTION_VIEW intent (shows install prompt)
     */
    private fun installApk(apkPath: String) {
        val apkFile = File(apkPath)
        if (!apkFile.exists()) {
            throw Exception("APK file not found at: $apkPath")
        }

        try {
            // Try silent PackageInstaller first
            installWithPackageInstaller(apkFile)
        } catch (e: Exception) {
            // Fallback: open install prompt via intent
            installWithIntent(apkFile)
        }
    }

    /**
     * PackageInstaller — silent on Android 12+ if same signing key
     */
    private fun installWithPackageInstaller(apkFile: File) {
        val packageInstaller: PackageInstaller = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        )

        params.setAppPackageName("com.sail.safety")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(
                PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED
            )
        }

        if (Build.VERSION.SDK_INT >= 34) {
            params.setInstallerPackageName(packageName)
        }

        val sessionId = packageInstaller.createSession(params)
        val session = packageInstaller.openSession(sessionId)

        session.openWrite("safety_lens_update.apk", 0, apkFile.length()).use { outputStream ->
            FileInputStream(apkFile).use { inputStream ->
                inputStream.copyTo(outputStream)
            }
            session.fsync(outputStream)
        }

        val intent = Intent(this, InstallResultReceiver::class.java).apply {
            action = "com.sail.safety.INSTALL_RESULT"
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            sessionId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        session.commit(pendingIntent.intentSender)
    }

    /**
     * Fallback: open the APK with standard Android install prompt.
     * Works on all devices — user sees a single "Install" button.
     */
    private fun installWithIntent(apkFile: File) {
        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                apkFile
            )
        } else {
            Uri.fromFile(apkFile)
        }

        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        startActivity(installIntent)
    }
}
