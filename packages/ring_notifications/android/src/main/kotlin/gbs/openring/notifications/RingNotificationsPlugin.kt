package gbs.openring.notifications

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val CHANNEL = "gbs.openring.app/ring_notifications"
private const val ANDROID_CHANNEL_ID = "ring_alerts"
private const val ERROR_CODE = "ring_notifications_error"

// A plugin, not a channel in MainActivity, so the WorkManager engine has it too.
class RingNotificationsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var syncServiceStarted = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val app = context ?: return result.error(ERROR_CODE, "detached", null)
        try {
            when (call.method) {
                "enabled" -> result.success(manager(app).areNotificationsEnabled())
                "show" -> {
                    show(app, call)
                    result.success(null)
                }
                "startSyncService" -> {
                    startSyncService(app, call)
                    result.success(null)
                }
                "stopSyncService" -> {
                    stopSyncService()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error(ERROR_CODE, error.message ?: error.javaClass.simpleName, null)
        }
    }

    private fun manager(app: Context) =
        app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun show(app: Context, call: MethodCall) {
        val id = requireNotNull(call.argument<Int>("id"))
        val manager = manager(app)
        manager.createNotificationChannel(
            NotificationChannel(
                ANDROID_CHANNEL_ID,
                requireNotNull(call.argument<String>("channelName")),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
        val body = requireNotNull(call.argument<String>("body"))
        val notification = Notification.Builder(app, ANDROID_CHANNEL_ID)
            .setSmallIcon(smallIcon(app))
            .setContentTitle(call.argument<String>("title"))
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openIntent(app, id, call.argument<String>("link")))
            .build()
        manager.notify(id, notification)
    }

    private fun startSyncService(app: Context, call: MethodCall) {
        check(canConnectToRing(app)) { "BLUETOOTH_CONNECT is not granted" }
        val intent = Intent(app, RingSyncForegroundService::class.java)
            .putExtra(RingSyncForegroundService.EXTRA_CHANNEL_NAME, call.argument<String>("channelName"))
            .putExtra(RingSyncForegroundService.EXTRA_TITLE, call.argument<String>("title"))
        app.startForegroundService(intent)
        syncServiceStarted = true
    }

    private fun stopSyncService() {
        if (!syncServiceStarted) return
        syncServiceStarted = false
        RingSyncForegroundService.stop()
    }

    private fun canConnectToRing(app: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return app.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun openIntent(app: Context, id: Int, link: String?): PendingIntent? {
        val launch = app.packageManager.getLaunchIntentForPackage(app.packageName) ?: return null
        launch.data = link?.let(Uri::parse)
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            app,
            id,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}

// ic_notification belongs to the app; res/raw/keep.xml protects it from shrinking.
internal fun smallIcon(app: Context): Int =
    app.resources.getIdentifier("ic_notification", "drawable", app.packageName)
        .takeIf { it != 0 }
        ?: app.applicationInfo.icon
