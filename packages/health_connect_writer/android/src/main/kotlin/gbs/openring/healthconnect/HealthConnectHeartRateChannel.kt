package gbs.openring.healthconnect

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// The health plugin writes one HeartRateRecord per sample; this writes each
// series Dart built as one record with all its samples.
class HealthConnectHeartRateChannel(private val context: Context) :
    EngineChannel(CHANNEL, ERROR) {

    private val client by lazy { HealthConnectClient.getOrCreate(context) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deleteRange" -> run(result) { deleteRange(call) }
            "write" -> run(result) { write(call) }
            else -> result.notImplemented()
        }
    }

    // Health Connect only deletes the caller's own records.
    private suspend fun deleteRange(call: MethodCall) {
        client.deleteRecords(HeartRateRecord::class, range(call))
    }

    private suspend fun write(call: MethodCall) {
        val version = long(call.argument("version"))
        val active = call.argument<Boolean>("active") == true
        val records = call.argument<List<Map<String, Any>>>("records").orEmpty()
        if (records.isEmpty()) return
        client.insertRecords(records.map { record(it, version, active) })
    }

    private fun record(arguments: Map<String, Any>, version: Long, active: Boolean): HeartRateRecord {
        val times = (arguments["times"] as? List<*>).orEmpty()
        val bpm = (arguments["bpm"] as? List<*>).orEmpty()
        require(times.size == bpm.size) { "times and bpm differ in length" }
        return HeartRateRecord(
            startTime = instant(arguments["start"]),
            startZoneOffset = null,
            endTime = instant(arguments["end"]),
            endZoneOffset = null,
            samples = times.indices.map { HeartRateRecord.Sample(instant(times[it]), long(bpm[it])) },
            metadata = metadata(requireNotNull(arguments["clientRecordId"] as? String), version, active),
        )
    }

    private fun metadata(clientRecordId: String, version: Long, active: Boolean): Metadata {
        val ring = Device(type = Device.TYPE_RING)
        if (active) return Metadata.activelyRecorded(ring, clientRecordId, version)
        return Metadata.autoRecorded(ring, clientRecordId, version)
    }

    companion object {
        const val CHANNEL = "gbs.openring.app/health_connect_heart_rate"
        private const val ERROR = "health_connect_heart_rate"
    }
}
