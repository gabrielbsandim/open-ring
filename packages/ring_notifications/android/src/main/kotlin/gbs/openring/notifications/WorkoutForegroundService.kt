package gbs.openring.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder

private const val WORKOUT_CHANNEL_ID = "workout_live"
private const val WORKOUT_NOTIFICATION_ID = 7302
private const val ACTION_PREFIX = "gbs.openring.notifications.workout."

internal data class WorkoutNotice(
    val channelName: String,
    val title: String?,
    val text: String?,
    val elapsedMs: Long,
    val running: Boolean,
    val pauseLabel: String,
    val resumeLabel: String,
    val stopLabel: String,
    val link: String?,
)

// Keeps the process alive for a workout with no route, where no location
// service runs, and owns the notification the workout is read from.
class WorkoutForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action?.removePrefix(ACTION_PREFIX)
        if (action != null && action != intent.action) return onAction(action)
        try {
            promote()
        } catch (_: RuntimeException) {
            stopPending = false
            stopSelf()
            return START_NOT_STICKY
        }
        active = this
        if (stopPending) stopNow()
        return START_NOT_STICKY
    }

    // A tap on a notification left behind by a dead process finds no workout.
    private fun onAction(action: String): Int {
        if (active == null) stopSelf()
        listener?.invoke(action)
        return START_NOT_STICKY
    }

    private fun promote() {
        val notification = workoutNotification(this, requireNotNull(pending))
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            startForeground(WORKOUT_NOTIFICATION_ID, notification)
            return
        }
        startForeground(
            WORKOUT_NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
    }

    private fun stopNow() {
        active = null
        stopPending = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    companion object {
        internal var pending: WorkoutNotice? = null
        internal var listener: ((String) -> Unit)? = null

        private var active: WorkoutForegroundService? = null
        private var stopPending = false

        // Stopping before startForeground runs makes Android crash the app, so
        // an early stop waits for onStartCommand.
        fun stop() {
            val service = active
            if (service == null) {
                stopPending = true
                return
            }
            service.stopNow()
        }

        internal fun cancelStop() {
            stopPending = false
        }
    }
}

internal fun showWorkoutNotification(app: Context, notice: WorkoutNotice) {
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.notify(WORKOUT_NOTIFICATION_ID, workoutNotification(app, notice))
}

internal fun cancelWorkoutNotification(app: Context) {
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.cancel(WORKOUT_NOTIFICATION_ID)
}

private fun workoutNotification(app: Context, notice: WorkoutNotice): Notification {
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.createNotificationChannel(
        NotificationChannel(WORKOUT_CHANNEL_ID, notice.channelName, NotificationManager.IMPORTANCE_LOW),
    )
    val toggle = if (notice.running) "pause" to notice.pauseLabel else "resume" to notice.resumeLabel
    return Notification.Builder(app, WORKOUT_CHANNEL_ID)
        .setSmallIcon(smallIcon(app))
        .setContentTitle(notice.title)
        .setContentText(notice.text)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setCategory(Notification.CATEGORY_WORKOUT)
        .setVisibility(Notification.VISIBILITY_PUBLIC)
        .setShowWhen(notice.running)
        .setUsesChronometer(notice.running)
        .setWhen(System.currentTimeMillis() - notice.elapsedMs)
        .setContentIntent(openWorkout(app, notice.link))
        .addAction(workoutAction(app, toggle.first, toggle.second))
        .addAction(workoutAction(app, "stop", notice.stopLabel))
        .build()
}

private fun workoutAction(app: Context, action: String, label: String): Notification.Action {
    val intent = Intent(app, WorkoutForegroundService::class.java).setAction(ACTION_PREFIX + action)
    val pending = PendingIntent.getService(
        app,
        action.hashCode(),
        intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
    return Notification.Action.Builder(null, label, pending).build()
}

private fun openWorkout(app: Context, link: String?): PendingIntent? {
    val launch = app.packageManager.getLaunchIntentForPackage(app.packageName) ?: return null
    launch.data = link?.let(Uri::parse)
    launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
    return PendingIntent.getActivity(
        app,
        WORKOUT_NOTIFICATION_ID,
        launch,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}
