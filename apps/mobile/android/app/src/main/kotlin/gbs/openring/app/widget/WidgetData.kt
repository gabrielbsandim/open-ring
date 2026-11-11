package gbs.openring.app.widget

import android.content.SharedPreferences
import java.time.LocalDate
import org.json.JSONException
import org.json.JSONObject

internal const val SNAPSHOT_KEY = "openring_snapshot"
internal const val APPEARANCE_KEY = "openring_appearance"

internal enum class Freshness { UNPAIRED, NEVER_SYNCED, FRESH, STALE }

internal enum class Metric(val id: String) {
    READINESS("readiness"),
    SLEEP("sleep"),
    STEPS("steps"),
    HEART_RATE("heartRate"),
    SPO2("spo2"),
    STRESS("stress"),
    BATTERY("battery");

    companion object {
        fun of(id: String): Metric? = entries.firstOrNull { it.id == id }
    }
}

internal enum class Units {
    METRIC,
    IMPERIAL;

    companion object {
        fun of(name: String?): Units = if (name == "imperial") IMPERIAL else METRIC
    }
}

internal enum class WorkoutKind(val id: String) {
    RUNNING("running"),
    WALKING("walking"),
    CYCLING("cycling"),
    HIKING("hiking"),
    STRENGTH("strength"),
    TREADMILL("treadmill"),
    STATIONARY_BIKE("stationaryBike"),
    ELLIPTICAL("elliptical"),
    YOGA("yoga"),
    OTHER("other");

    companion object {
        fun of(id: String?): WorkoutKind = entries.firstOrNull { it.id == id } ?: OTHER
    }
}

internal data class LastWorkout(
    val kind: WorkoutKind,
    val startMs: Long,
    val elapsedSeconds: Long,
    val distanceMeters: Double?,
) {
    companion object {
        fun parse(json: JSONObject?): LastWorkout? {
            if (json == null) return null
            val startMs = json.long("startMs") ?: return null
            return LastWorkout(
                kind = WorkoutKind.of(json.text("type")),
                startMs = startMs,
                elapsedSeconds = json.long("elapsedSeconds") ?: 0L,
                distanceMeters = json.double("distanceMeters"),
            )
        }
    }
}

internal enum class ThemeChoice {
    SYSTEM,
    DARK,
    LIGHT;

    companion object {
        fun of(name: String?, fallback: ThemeChoice): ThemeChoice = when (name) {
            "system" -> SYSTEM
            "dark" -> DARK
            "light" -> LIGHT
            else -> fallback
        }
    }
}

internal data class Snapshot(
    val date: LocalDate?,
    val paired: Boolean,
    val syncedAtMs: Long?,
    val staleAfterMs: Long,
    val stepGoal: Int,
    val readiness: Int?,
    val restingHeartRate: Int?,
    val hrv: Int?,
    val sleepMinutes: Int?,
    val sleepScore: Int?,
    val steps: Int?,
    val heartRateMean: Int?,
    val spo2: Int?,
    val stress: Int?,
    val batteryPercent: Int?,
    val lastWorkout: LastWorkout?,
) {
    val hasHealthData: Boolean
        get() = listOf(
            readiness, restingHeartRate, hrv, sleepMinutes, sleepScore,
            steps, heartRateMean, spo2, stress,
        ).any { it != null }

    fun freshness(nowMs: Long): Freshness = when {
        !paired -> Freshness.UNPAIRED
        syncedAtMs == null -> Freshness.NEVER_SYNCED
        nowMs - syncedAtMs > staleAfterMs -> Freshness.STALE
        else -> Freshness.FRESH
    }

    companion object {
        private const val DEFAULT_STALE_AFTER_MS = 3L * 60 * 60 * 1000

        fun parse(raw: String?): Snapshot? {
            val json = raw?.let(::objectOf) ?: return null
            return Snapshot(
                date = json.text("date")?.let(::dateOf),
                paired = json.optBoolean("paired", false),
                syncedAtMs = json.long("syncedAtMs"),
                staleAfterMs = json.long("staleAfterMs") ?: DEFAULT_STALE_AFTER_MS,
                stepGoal = json.int("stepGoal") ?: 0,
                readiness = json.int("readiness"),
                restingHeartRate = json.int("restingHeartRate"),
                hrv = json.int("hrv"),
                sleepMinutes = json.int("sleepMinutes"),
                sleepScore = json.int("sleepScore"),
                steps = json.int("steps"),
                heartRateMean = json.int("heartRateMean"),
                spo2 = json.int("spo2"),
                stress = json.int("stress"),
                batteryPercent = json.int("batteryPercent"),
                lastWorkout = LastWorkout.parse(json.optJSONObject("lastWorkout")),
            )
        }
    }
}

internal data class Appearance(
    val appTheme: ThemeChoice,
    val todayTheme: ThemeChoice,
    val todayMetrics: List<Metric>,
    val units: Units,
) {
    companion object {
        val DEFAULT = Appearance(
            appTheme = ThemeChoice.SYSTEM,
            todayTheme = ThemeChoice.SYSTEM,
            todayMetrics = listOf(Metric.SLEEP, Metric.STEPS, Metric.HEART_RATE),
            units = Units.METRIC,
        )

        fun parse(raw: String?): Appearance {
            val json = raw?.let(::objectOf) ?: return DEFAULT
            val app = ThemeChoice.of(json.text("appTheme"), ThemeChoice.SYSTEM)
            val metrics = json.optJSONArray("todayMetrics")
            return Appearance(
                appTheme = app,
                todayTheme = ThemeChoice.of(json.text("todayTheme"), app),
                todayMetrics = (0 until (metrics?.length() ?: 0))
                    .mapNotNull { metrics?.optString(it)?.let(Metric::of) },
                units = Units.of(json.text("units")),
            )
        }
    }
}

internal data class WidgetData(val snapshot: Snapshot?, val appearance: Appearance) {
    companion object {
        fun read(preferences: SharedPreferences) = WidgetData(
            snapshot = Snapshot.parse(preferences.getString(SNAPSHOT_KEY, null)),
            appearance = Appearance.parse(preferences.getString(APPEARANCE_KEY, null)),
        )
    }
}

private fun objectOf(raw: String): JSONObject? = try {
    JSONObject(raw)
} catch (_: JSONException) {
    null
}

private fun dateOf(iso: String): LocalDate? = try {
    LocalDate.parse(iso)
} catch (_: java.time.format.DateTimeParseException) {
    null
}

private fun JSONObject.int(key: String): Int? = if (isNull(key)) null else optInt(key)

private fun JSONObject.long(key: String): Long? = if (isNull(key)) null else optLong(key)

private fun JSONObject.double(key: String): Double? = if (isNull(key)) null else optDouble(key)

private fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key)
