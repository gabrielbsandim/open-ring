package gbs.openring.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.KeyguardManager
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
private const val ALERT_CHANNEL_ID = "workout_alerts"
private const val ALERT_NOTIFICATION_ID = 7303
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
        val notice = requireNotNull(pending)
        val notification = workoutNotification(this, notice)
        rememberPostedWorkoutNotice(notice)
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
private var postedAt = 0L
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
    post(app, notice)
}

// The screen turned on or off or the phone was unlocked: a waiting notice posts,
// and one that hides the heart rate posts again for the lock screen or shade.
internal fun refreshWorkoutNotice(app: Context) {
    val waiting = held
    if (waiting != null) {
        held = null
        return post(app, advanced(waiting, heldAt))
    }
    val last = posted ?: return
    if (last.publicTitle == null) return
    post(app, advanced(last, postedAt))
}

internal fun rememberPostedWorkoutNotice(notice: WorkoutNotice) {
    posted = notice
    postedAt = SystemClock.elapsedRealtime()
}

// The clock kept running while the notice waited.
private fun advanced(notice: WorkoutNotice, since: Long): WorkoutNotice {
    if (!notice.running) return notice
    return notice.copy(elapsedMs = notice.elapsedMs + SystemClock.elapsedRealtime() - since)
}

private fun post(app: Context, notice: WorkoutNotice) {
    rememberPostedWorkoutNotice(notice)
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
    val lockScreen = workoutBuilder(app, notice, publicTitle, publicText)
        .setVisibility(Notification.VISIBILITY_PUBLIC)
    // A default lock screen shows a private notice in full, so while the phone
    // is locked or dark the notice itself carries the text with no heart rate.
    if (lockedOrDark(app)) return lockScreen.build()
    return workoutBuilder(app, notice, notice.title, notice.text)
        .setVisibility(Notification.VISIBILITY_PRIVATE)
        .setPublicVersion(lockScreen.build())
        .build()
}

private fun lockedOrDark(app: Context): Boolean {
    val power = app.getSystemService(Context.POWER_SERVICE) as PowerManager
    val keyguard = app.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
    return !power.isInteractive || keyguard.isKeyguardLocked
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

// A heads up alert with one short vibration and no sound; tapping it
// reconnects the ring, as its text says.
internal fun showWorkoutAlert(app: Context, channelName: String, title: String?, text: String?, reconnectLabel: String) {
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val channel = NotificationChannel(ALERT_CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_HIGH)
    channel.setSound(null, null)
    channel.enableVibration(true)
    channel.vibrationPattern = longArrayOf(0, 400)
    manager.createNotificationChannel(channel)
    val reconnect = workoutAction(app, "reconnect", reconnectLabel)
    val alert = Notification.Builder(app, ALERT_CHANNEL_ID)
        .setSmallIcon(smallIcon(app))
        .setContentTitle(title)
        .setContentText(text)
        .setCategory(Notification.CATEGORY_STATUS)
        .setVisibility(Notification.VISIBILITY_PUBLIC)
        .setAutoCancel(true)
        .setContentIntent(reconnect.actionIntent)
        .addAction(reconnect)
        .build()
    manager.notify(ALERT_NOTIFICATION_ID, alert)
}

internal fun cancelWorkoutAlert(app: Context) {
    val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.cancel(ALERT_NOTIFICATION_ID)
}
