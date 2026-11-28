package gbs.openring.app

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class RestartChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "restart") {
            result.notImplemented()
            return
        }
        result.success(null)
        restart()
    }

    // Exiting the process ends every isolate, so the next start opens the
    // database only after the staged restore has been swapped in.
    private fun restart() {
        val launch = activity.packageManager.getLaunchIntentForPackage(activity.packageName)
        val component = launch?.component ?: return
        activity.startActivity(Intent.makeRestartActivityTask(component))
        activity.finishAffinity()
        Runtime.getRuntime().exit(0)
    }

    companion object {
        const val CHANNEL = "gbs.openring.app/restart"
    }
}
