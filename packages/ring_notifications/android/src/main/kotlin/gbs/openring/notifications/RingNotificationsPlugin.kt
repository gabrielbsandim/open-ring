package gbs.openring.notifications

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
    private var workoutShown = false
    private var workoutServiceStarted = false
    private var screenOn: BroadcastReceiver? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context?.let(::hideWorkout)
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
                "showWorkout" -> {
                    showWorkout(app, call)
                    result.success(null)
                }
                "hideWorkout" -> {
                    hideWorkout(app)
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

    private fun showWorkout(app: Context, call: MethodCall) {
        val notice = WorkoutNotice(
            channelName = requireNotNull(call.argument<String>("channelName")),
            title = call.argument<String>("title"),
            text = call.argument<String>("text"),
            elapsedMs = requireNotNull(call.argument<Number>("elapsedMs")).toLong(),
            running = requireNotNull(call.argument<Boolean>("running")),
            pauseLabel = requireNotNull(call.argument<String>("pauseLabel")),
            resumeLabel = requireNotNull(call.argument<String>("resumeLabel")),
            stopLabel = requireNotNull(call.argument<String>("stopLabel")),
            link = call.argument<String>("link"),
            confirming = call.argument<Boolean>("confirming") ?: false,
            ringLost = call.argument<Boolean>("ringLost") ?: false,
            saveLabel = call.argument<String>("saveLabel") ?: "Save",
            keepLabel = call.argument<String>("keepLabel") ?: "Continue",
            reconnectLabel = call.argument<String>("reconnectLabel") ?: "Reconnect",
            publicTitle = call.argument<String>("publicTitle"),
            publicText = call.argument<String>("publicText"),
        )
        // Only the engine that shows the workout hears its buttons, never the worker's.
        WorkoutForegroundService.listener = { action -> channel?.invokeMethod("workoutAction", action) }
        WorkoutForegroundService.pending = notice
        if (workoutShown) return showWorkoutNotification(app, notice)
        workoutShown = true
        listenScreenOn(app)
        startWorkoutService(app, notice)
    }

    private fun listenScreenOn(app: Context) {
        if (screenOn != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) = postHeldWorkoutNotice(app)
        }
        app.registerReceiver(receiver, IntentFilter(Intent.ACTION_SCREEN_ON))
        screenOn = receiver
    }

    private fun stopListeningScreenOn(app: Context) {
        val receiver = screenOn ?: return
        screenOn = null
        app.unregisterReceiver(receiver)
    }

    // From Android 14 a connectedDevice service needs the Bluetooth grant, so
    // there a workout with no ring gets the same notification without it.
    private fun startWorkoutService(app: Context, notice: WorkoutNotice) {
        if (!mayRunWorkoutService(app)) return showWorkoutNotification(app, notice)
        WorkoutForegroundService.cancelStop()
        app.startForegroundService(Intent(app, WorkoutForegroundService::class.java))
        workoutServiceStarted = true
    }

    private fun hideWorkout(app: Context) {
        if (!workoutShown) return
        workoutShown = false
        stopListeningScreenOn(app)
        WorkoutForegroundService.listener = null
        if (workoutServiceStarted) WorkoutForegroundService.stop()
        workoutServiceStarted = false
        cancelWorkoutNotification(app)
    }

    private fun mayRunWorkoutService(app: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return canConnectToRing(app)
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
