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
import android.os.PowerManager
import android.os.SystemClock

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
    val confirming: Boolean = false,
    val ringLost: Boolean = false,
    val saveLabel: String = "Save",
    val keepLabel: String = "Continue",
    val reconnectLabel: String = "Reconnect",
    val publicTitle: String? = null,
    val publicText: String? = null,
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

    // A tap on a notification left behind by a dead process or a closed
    // screen finds no workout, so the tap clears it.
    private fun onAction(action: String): Int {
        val heard = listener
        if (heard == null) clearStale()
        if (active == null) stopSelf()
        heard?.invoke(action)
        return START_NOT_STICKY
    }

    private fun clearStale() {
        cancelWorkoutNotification(this)
        active?.stopNow()
    }

    // The workout ends with the task, so its notification goes with it.
    override fun onTaskRemoved(rootIntent: Intent?) {
        listener = null
        cancelWorkoutNotification(this)
        stop()
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
        pending = null
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
        // an early stop waits for onStartCommand and the notice stays until then.
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

private var posted: WorkoutNotice? = null
private var held: WorkoutNotice? = null
private var heldAt = 0L

// With the screen off a running notice waits unless its running, question or
// ring state changed; the last one waiting posts when the screen turns on.
internal fun showWorkoutNotification(app: Context, notice: WorkoutNotice) {
    val power = app.getSystemService(Context.POWER_SERVICE) as PowerManager
    val last = posted
    val sameShape = last != null && last.running == notice.running &&
        last.confirming == notice.confirming && last.ringLost == notice.ringLost
    if (!power.isInteractive && notice.running && sameShape) {
        held = notice
        heldAt = SystemClock.elapsedRealtime()
        return
    }
    held = null
    posted = notice
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.notify(WORKOUT_NOTIFICATION_ID, workoutNotification(app, notice))
}

internal fun postHeldWorkoutNotice(app: Context) {
    val waiting = held ?: return
    // The clock kept running while the notice waited.
    val notice = waiting.copy(elapsedMs = waiting.elapsedMs + SystemClock.elapsedRealtime() - heldAt)
    held = null
    posted = notice
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.notify(WORKOUT_NOTIFICATION_ID, workoutNotification(app, notice))
}

internal fun forgetWorkoutNotice() {
    posted = null
    held = null
}

internal fun cancelWorkoutNotification(app: Context) {
    forgetWorkoutNotice()
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.cancel(WORKOUT_NOTIFICATION_ID)
}

private fun workoutNotification(app: Context, notice: WorkoutNotice): Notification {
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.createNotificationChannel(
        NotificationChannel(WORKOUT_CHANNEL_ID, notice.channelName, NotificationManager.IMPORTANCE_LOW),
    )
    val publicTitle = notice.publicTitle
    val publicText = notice.publicText
    if (publicTitle == null || publicText == null) {
        return workoutBuilder(app, notice, notice.title, notice.text)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()
    }
    // The lock screen shows the public version, which has no heart rate.
    val lockScreen = workoutBuilder(app, notice, publicTitle, publicText).build()
    return workoutBuilder(app, notice, notice.title, notice.text)
        .setVisibility(Notification.VISIBILITY_PRIVATE)
        .setPublicVersion(lockScreen)
        .build()
}

private fun workoutBuilder(
    app: Context,
    notice: WorkoutNotice,
    title: String?,
    text: String?,
): Notification.Builder {
    val builder = Notification.Builder(app, WORKOUT_CHANNEL_ID)
        .setSmallIcon(smallIcon(app))
        .setContentTitle(title)
        .setContentText(text)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setCategory(Notification.CATEGORY_WORKOUT)
        .setShowWhen(notice.running)
        .setUsesChronometer(notice.running)
        .setWhen(System.currentTimeMillis() - notice.elapsedMs)
        .setContentIntent(openWorkout(app, notice.link))
    workoutActions(notice).forEach { (action, label) -> builder.addAction(workoutAction(app, action, label)) }
    return builder
}

// The end question offers only Save and Continue; a lost ring adds Reconnect.
private fun workoutActions(notice: WorkoutNotice): List<Pair<String, String>> {
    if (notice.confirming) return listOf("save" to notice.saveLabel, "keep" to notice.keepLabel)
    val toggle = if (notice.running) "pause" to notice.pauseLabel else "resume" to notice.resumeLabel
    val reconnect = if (notice.ringLost) listOf("reconnect" to notice.reconnectLabel) else emptyList()
    return listOf(toggle, "stop" to notice.stopLabel) + reconnect
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
