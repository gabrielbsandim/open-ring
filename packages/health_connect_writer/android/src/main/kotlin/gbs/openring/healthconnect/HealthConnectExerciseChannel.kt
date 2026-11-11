package gbs.openring.healthconnect

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// The health plugin's workout read also reads distance, energy and steps of
// every app, so it fails without three more permissions; this needs READ_EXERCISE only.
class HealthConnectExerciseChannel(private val context: Context) :
    EngineChannel(CHANNEL, ERROR) {

    private val client by lazy { HealthConnectClient.getOrCreate(context) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "read" -> answer(result) { sessions(call).map(::sessionMap) }
            else -> result.notImplemented()
        }
    }

    private suspend fun sessions(call: MethodCall): List<ExerciseSessionRecord> {
        val range = range(call)
        val sessions = mutableListOf<ExerciseSessionRecord>()
        var pageToken: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = ExerciseSessionRecord::class,
                    timeRangeFilter = range,
                    pageToken = pageToken,
                ),
            )
            sessions.addAll(response.records)
            pageToken = response.pageToken
        } while (!pageToken.isNullOrEmpty())
        return sessions
    }

    private fun sessionMap(session: ExerciseSessionRecord): Map<String, Any?> = mapOf(
        "id" to session.metadata.id,
        "source" to session.metadata.dataOrigin.packageName,
        "activityType" to activityType(session.exerciseType),
        "start" to session.startTime.toEpochMilli(),
        "end" to session.endTime.toEpochMilli(),
        "offsetSeconds" to session.startZoneOffset?.totalSeconds,
    )

    // OpenRing's own activity type ids; anything else is shown as other.
    private fun activityType(type: Int): String = when (type) {
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING -> "running"
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> "walking"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING -> "cycling"
        ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> "hiking"
        ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING,
        ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING -> "strength_training"
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL -> "treadmill_running"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY -> "stationary_cycling"
        ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL -> "elliptical"
        ExerciseSessionRecord.EXERCISE_TYPE_YOGA -> "yoga"
        else -> "other"
    }

    companion object {
        const val CHANNEL = "gbs.openring.app/health_connect_exercise"
        private const val ERROR = "health_connect_exercise"
    }
}
