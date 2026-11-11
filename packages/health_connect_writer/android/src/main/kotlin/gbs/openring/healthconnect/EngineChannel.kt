package gbs.openring.healthconnect

import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

abstract class EngineChannel(private val name: String, private val errorCode: String) :
    MethodChannel.MethodCallHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, name).also { it.setMethodCallHandler(this) }
    }

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
        scope.cancel()
    }

    protected fun run(result: MethodChannel.Result, block: suspend () -> Unit) = answer(result) {
        block()
        null
    }

    protected fun answer(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                result.success(block())
            } catch (error: Exception) {
                result.error(errorCode, error.message ?: error.javaClass.simpleName, null)
            }
        }
    }

    // The standard codec sends a Dart int as Integer or Long depending on its size.
    protected fun long(value: Any?): Long = requireNotNull(value as? Number).toLong()

    protected fun instant(value: Any?): Instant = Instant.ofEpochMilli(long(value))

    protected fun range(call: MethodCall): TimeRangeFilter =
        TimeRangeFilter.between(instant(call.argument("from")), instant(call.argument("to")))
}
