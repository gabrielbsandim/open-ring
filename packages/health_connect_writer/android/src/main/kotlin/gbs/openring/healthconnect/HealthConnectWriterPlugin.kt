package gbs.openring.healthconnect

import io.flutter.embedding.engine.plugins.FlutterPlugin

// A plugin, not channels in MainActivity, so the WorkManager engine gets them too.
class HealthConnectWriterPlugin : FlutterPlugin {

    private var channels: List<EngineChannel> = emptyList()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        channels = listOf(
            HealthConnectSleepChannel(context),
            HealthConnectExerciseChannel(context),
            HealthConnectHeartRateChannel(context),
        )
        channels.forEach { it.attach(binding.binaryMessenger) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channels.forEach { it.close() }
        channels = emptyList()
    }
}
