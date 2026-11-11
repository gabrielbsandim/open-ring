package gbs.openring.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

private const val SYNC_CHANNEL_ID = "ring_sync"
private const val NOTIFICATION_ID = 7301

// A worker started inside an idle process has no component the system counts,
// so Android reclaims the process mid-sync. This service keeps it alive.
class RingSyncForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            promote(intent)
        } catch (_: RuntimeException) {
            stopPending = false
            stopSelf()
            return START_NOT_STICKY
        }
        active = this
        if (stopPending) stopNow()
        return START_NOT_STICKY
    }

    private fun promote(intent: Intent?) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                SYNC_CHANNEL_ID,
                intent?.getStringExtra(EXTRA_CHANNEL_NAME) ?: SYNC_CHANNEL_ID,
                NotificationManager.IMPORTANCE_MIN,
            ),
        )
        val notification = Notification.Builder(this, SYNC_CHANNEL_ID)
            .setSmallIcon(smallIcon(this))
            .setContentTitle(intent?.getStringExtra(EXTRA_TITLE))
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification)
            return
        }
        startForeground(
            NOTIFICATION_ID,
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
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val EXTRA_TITLE = "title"

        private var active: RingSyncForegroundService? = null
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
    }
}
