package gbs.openring.healthconnect

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// The health plugin writes one SleepSessionRecord per stage; this writes one
// session per night with its stage list.
class HealthConnectSleepChannel(private val context: Context) :
    EngineChannel(CHANNEL, ERROR) {

    private val client by lazy { HealthConnectClient.getOrCreate(context) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ids" -> answer(result) { ids(call) }
            "deleteRange" -> run(result) { deleteRange(call) }
            "write" -> run(result) { write(call) }
            else -> result.notImplemented()
        }
    }

    // Unlike the health plugin's read, a failure here reaches Dart, so an
    // empty list really means no session is left in the window.
    private suspend fun ids(call: MethodCall): List<String> {
        val range = range(call)
        val ids = mutableListOf<String>()
        var pageToken: String? = null
        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = SleepSessionRecord::class,
                    timeRangeFilter = range,
                    pageToken = pageToken,
                ),
            )
            ids.addAll(response.records.map { it.metadata.id })
            pageToken = response.pageToken
        } while (!pageToken.isNullOrEmpty())
        return ids
    }

    // Health Connect only deletes the caller's own records.
    private suspend fun deleteRange(call: MethodCall) {
        client.deleteRecords(SleepSessionRecord::class, range(call))
    }

    private suspend fun write(call: MethodCall) {
        client.insertRecords(listOf(session(call)))
    }

    private fun session(call: MethodCall): SleepSessionRecord {
        val stages = call.argument<List<Map<String, Any>>>("stages").orEmpty()
        return SleepSessionRecord(
            startTime = instant(call.argument("start")),
            startZoneOffset = null,
            endTime = instant(call.argument("end")),
            endZoneOffset = null,
            metadata = Metadata.autoRecorded(
                device = Device(type = Device.TYPE_RING),
                clientRecordId = requireNotNull(call.argument<String>("clientRecordId")),
                clientRecordVersion = long(call.argument("version")),
            ),
            stages = stages.map(::stage),
        )
    }

    private fun stage(arguments: Map<String, Any>): SleepSessionRecord.Stage =
        SleepSessionRecord.Stage(
            startTime = instant(arguments["start"]),
            endTime = instant(arguments["end"]),
            stage = stageType(arguments["stage"] as? String),
        )

    private fun stageType(name: String?): Int = when (name) {
        "light" -> SleepSessionRecord.STAGE_TYPE_LIGHT
        "deep" -> SleepSessionRecord.STAGE_TYPE_DEEP
        "rem" -> SleepSessionRecord.STAGE_TYPE_REM
        "awake" -> SleepSessionRecord.STAGE_TYPE_AWAKE
        else -> SleepSessionRecord.STAGE_TYPE_UNKNOWN
    }

    companion object {
        const val CHANNEL = "gbs.openring.app/health_connect_sleep"
        private const val ERROR = "health_connect_sleep"
    }
}
