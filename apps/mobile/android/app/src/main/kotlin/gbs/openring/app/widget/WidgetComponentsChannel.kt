package gbs.openring.app.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WidgetComponentsChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != METHOD_THIS_WEEK) {
            result.notImplemented()
            return
        }
        val available = call.arguments as? Boolean
        if (available == null) {
            result.error("invalid_args", "Boolean availability expected.", null)
            return
        }
        setThisWeekAvailable(available)
        result.success(null)
    }

    private fun setThisWeekAvailable(available: Boolean) {
        val component = ComponentName(context, ThisWeekWidgetReceiver::class.java)
        val manager = AppWidgetManager.getInstance(context)
        val shouldEnable = available || manager.getAppWidgetIds(component).isNotEmpty()
        val state = if (shouldEnable) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        if (context.packageManager.getComponentEnabledSetting(component) == state) return
        context.packageManager.setComponentEnabledSetting(
            component,
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    companion object {
        const val CHANNEL = "gbs.openring.app/widget_components"
        private const val METHOD_THIS_WEEK = "setThisWeekAvailable"
    }
}
