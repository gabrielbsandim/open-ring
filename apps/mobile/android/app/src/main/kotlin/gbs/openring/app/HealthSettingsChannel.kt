package gbs.openring.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class HealthSettingsChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "open") {
            result.notImplemented()
            return
        }
        open()
        result.success(null)
    }

    // Android 14 ships Health Connect in the system; older versions need the
    // separate app, so a missing one falls through to its store page.
    private fun open() {
        for (intent in candidates()) {
            if (start(intent)) return
        }
    }

    private fun candidates(): List<Intent> {
        val settings = Intent(ACTION_HEALTH_CONNECT_SETTINGS)
        val store = Intent(Intent.ACTION_VIEW, Uri.parse(STORE_URI))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return listOf(settings, store)
        }
        val permissions = Intent(ACTION_MANAGE_HEALTH_PERMISSIONS)
            .putExtra(Intent.EXTRA_PACKAGE_NAME, activity.packageName)
        return listOf(permissions, settings, store)
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

    companion object {
        const val CHANNEL = "gbs.openring.app/health_settings"
        private const val ACTION_HEALTH_CONNECT_SETTINGS = "androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"
        private const val ACTION_MANAGE_HEALTH_PERMISSIONS =
            "android.health.connect.action.MANAGE_HEALTH_PERMISSIONS"
        private const val STORE_URI = "market://details?id=com.google.android.apps.healthdata"
    }
}
