package gbs.openring.app.widget

import android.content.SharedPreferences
import java.time.LocalDate
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

internal const val SNAPSHOT_KEY = "openring_snapshot"
internal const val APPEARANCE_KEY = "openring_appearance"

internal enum class Freshness { UNPAIRED, NEVER_SYNCED, FRESH, STALE }

internal enum class Metric(val id: String, val requiresRing: Boolean = true) {
    READINESS("readiness"),
    SLEEP("sleep"),
    STEPS("steps"),
    HEART_RATE("heartRate"),
    SPO2("spo2"),
    STRESS("stress"),
    BATTERY("battery"),
    DAY_SCORE("dayScore"),
    WEIGHT("weight", requiresRing = false),
    ENERGY("energy"),
    EFFORT("effort");

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

internal enum class DayScoreKind(val id: String) {
    FULL("full"),
    PARTIAL("partial"),
    FIRST_DAYS("firstDays"),
    NO_SCORE("noScore"),
    AFTER_MIDNIGHT("afterMidnight");

    companion object {
        fun of(id: String?): DayScoreKind? = entries.firstOrNull { it.id == id }
    }
}

internal enum class DayScoreBand(val id: String) {
    GREAT("great"),
    GOOD("good"),
    MIXED("mixed"),
    LOW("low");

    companion object {
        fun of(id: String?): DayScoreBand? = entries.firstOrNull { it.id == id }
    }
}

internal enum class DayScoreGap(val id: String) {
    NIGHT("night"),
    STEPS("steps"),
    COVERAGE("coverage");

    companion object {
        fun of(id: String?): DayScoreGap? = entries.firstOrNull { it.id == id }
    }
}

internal data class DayScoreData(
    val kind: DayScoreKind,
    val score: Int?,
    val band: DayScoreBand?,
    val coverage: Int,
    val pillarPoints: List<Double?>?,
    val asOfMs: Long?,
    val gap: DayScoreGap?,
) {
    companion object {
        fun parse(json: JSONObject?): DayScoreData? {
            if (json == null) return null
            val kind = DayScoreKind.of(json.text("kind")) ?: return null
            return DayScoreData(
                kind = kind,
                score = json.int("score"),
                band = DayScoreBand.of(json.text("band")),
                coverage = json.int("coverage") ?: 0,
                pillarPoints = json.optJSONArray("pillarPoints")?.toNullableDoubles(),
                asOfMs = json.long("asOfMs"),
                gap = DayScoreGap.of(json.text("gap")),
            )
        }
    }
}

internal enum class WeightDirection(val id: String) {
    FALLING("falling"),
    RISING("rising"),
    STEADY("steady"),
    BUILDING("building");

    companion object {
        fun of(id: String?): WeightDirection = entries.firstOrNull { it.id == id } ?: BUILDING
    }
}

internal data class WeightData(val trendKilograms: Double?, val direction: WeightDirection) {
    companion object {
        fun parse(json: JSONObject?): WeightData? {
            if (json == null) return null
            return WeightData(
                trendKilograms = json.double("trendKilograms"),
                direction = WeightDirection.of(json.text("direction")),
            )
        }
    }
}

internal data class EnergyData(val lowKcal: Int, val highKcal: Int) {
    companion object {
        fun parse(json: JSONObject?): EnergyData? {
            if (json == null) return null
            val low = json.int("lowKcal") ?: return null
            val high = json.int("highKcal") ?: return null
            return EnergyData(lowKcal = low, highKcal = high)
        }
    }
}

internal data class EffortData(
    val points: Int,
    val targetPoints: Int,
    val strengthDays: Int,
    val strengthTarget: Int,
) {
    companion object {
        fun parse(json: JSONObject?): EffortData? {
            if (json == null) return null
            val points = json.int("points") ?: return null
            val targetPoints = json.int("targetPoints") ?: return null
            val strengthDays = json.int("strengthDays") ?: return null
            val strengthTarget = json.int("strengthTarget") ?: return null
            return EffortData(points, targetPoints, strengthDays, strengthTarget)
        }
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
    val batteryCharging: Boolean? = null,
    val lastWorkout: LastWorkout?,
    val enabledModules: Set<String> = emptySet(),
    val hideNumbers: Boolean = false,
    val dayScore: DayScoreData? = null,
    val weight: WeightData? = null,
    val energy: EnergyData? = null,
    val effort: EffortData? = null,
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
                batteryCharging = json.bool("batteryCharging"),
                lastWorkout = LastWorkout.parse(json.optJSONObject("lastWorkout")),
                enabledModules = json.optJSONArray("enabledModules")?.toStringSet() ?: emptySet(),
                hideNumbers = json.optBoolean("hideNumbers", false),
                dayScore = DayScoreData.parse(json.optJSONObject("dayScore")),
                weight = WeightData.parse(json.optJSONObject("weight")),
                energy = EnergyData.parse(json.optJSONObject("energy")),
                effort = EffortData.parse(json.optJSONObject("effort")),
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

private fun JSONArray.toStringSet(): Set<String> =
    (0 until length()).mapNotNull { if (isNull(it)) null else optString(it) }.toSet()

private fun JSONArray.toNullableDoubles(): List<Double?> = (0 until length()).map { index ->
    if (isNull(index)) null else optDouble(index).takeUnless { it.isNaN() }
}

private fun JSONObject.bool(key: String): Boolean? = if (isNull(key)) null else optBoolean(key)

private fun JSONObject.int(key: String): Int? = if (isNull(key)) null else optInt(key)

private fun JSONObject.long(key: String): Long? = if (isNull(key)) null else optLong(key)

private fun JSONObject.double(key: String): Double? =
    if (isNull(key)) null else optDouble(key).takeUnless { it.isNaN() }

private fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key)
