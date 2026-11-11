package gbs.openring.app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PermissionsChannel(private val activity: FlutterFragmentActivity) :
    MethodChannel.MethodCallHandler {

    private val launcher: ActivityResultLauncher<Array<String>> =
        activity.registerForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { onResult() }

    private val asked: SharedPreferences by lazy {
        activity.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    }

    private var pending: Pair<String, MethodChannel.Result>? = null

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val name = call.arguments as? String
        when (call.method) {
            "status" -> result.success(status(name))
            "request" -> request(name, result)
            "openSettings" -> {
                openSettings()
                result.success(null)
            }
            "openNotificationSettings" -> {
                openNotificationSettings()
                result.success(null)
            }
            "openBatterySettings" -> {
                openBatterySettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun runtimePermissions(name: String?): Array<String>? = when (name) {
        "bluetooth" -> bluetoothPermissions()
        "notifications" -> notificationPermissions()
        else -> null
    }

    private fun bluetoothPermissions(): Array<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
    }

    private fun notificationPermissions(): Array<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return emptyArray()
        return arrayOf(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun status(name: String?): String {
        if (name == BACKGROUND_EXECUTION) return batteryExemptionStatus()
        val permissions = runtimePermissions(name) ?: return DENIED
        if (permissions.isEmpty()) return switchStatus()
        if (permissions.all(::isGranted)) return GRANTED
        if (!asked.getBoolean(name, false)) return DENIED
        if (permissions.any(activity::shouldShowRequestPermissionRationale)) return DENIED
        return PERMANENTLY_DENIED
    }

    private fun batteryExemptionStatus(): String {
        val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (power.isIgnoringBatteryOptimizations(activity.packageName)) return GRANTED
        return DENIED
    }

    // Before Android 13 notifications have no runtime permission, only the
    // per-app switch in system settings.
    private fun switchStatus(): String {
        if (NotificationManagerCompat.from(activity).areNotificationsEnabled()) return GRANTED
        return PERMANENTLY_DENIED
    }

    private fun isGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(activity, permission) ==
            PackageManager.PERMISSION_GRANTED

    private fun request(name: String?, result: MethodChannel.Result) {
        val permissions = runtimePermissions(name)
        if (name == null || permissions == null) {
            result.error("unknown_permission", "Unknown permission $name", null)
            return
        }
        val current = status(name)
        if (current == GRANTED || permissions.isEmpty()) {
            result.success(current)
            return
        }
        if (pending != null) {
            result.error("busy", "A permission request is already running", null)
            return
        }
        pending = name to result
        asked.edit().putBoolean(name, true).apply()
        launcher.launch(permissions)
    }

    private fun onResult() {
        val (name, result) = pending ?: return
        pending = null
        result.success(status(name))
    }

    private fun openSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
    }

    // Asks through the system dialog; Play reviews this permission, so the
    // listing must justify background ring sync as the app's core function.
    private fun openBatterySettings() {
        val request = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${activity.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            activity.startActivity(request)
        } catch (_: ActivityNotFoundException) {
            activity.startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    companion object {
        const val CHANNEL = "gbs.openring.app/permissions"
        private const val PREFERENCES = "openring_permissions"
        private const val BACKGROUND_EXECUTION = "backgroundExecution"
        private const val GRANTED = "granted"
        private const val DENIED = "denied"
        private const val PERMANENTLY_DENIED = "permanentlyDenied"
    }
}
