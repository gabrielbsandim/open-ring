package gbs.openring.app.widget

import android.content.Context
import android.text.format.DateUtils
import gbs.openring.app.R
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.roundToInt

internal data class Status(val text: String, val stale: Boolean)

internal data class MetricText(val value: String, val detail: String, val progress: Float?)

internal class WidgetFormat(private val context: Context) {
    private val locale = context.resources.configuration.locales[0]
    private val numbers = NumberFormat.getIntegerInstance(locale)
    private val decimals = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 2
        maximumFractionDigits = 2
    }

    val none: String = context.getString(R.string.widget_no_value)

    fun integer(value: Int): String = numbers.format(value)

    fun percent(value: Int): String = context.getString(R.string.widget_percent, integer(value))

    fun duration(minutes: Int): String = when {
        minutes < 60 -> context.getString(R.string.widget_duration_m, minutes)
        else -> context.getString(R.string.widget_duration_hm, minutes / 60, minutes % 60)
    }

    fun clock(instantMs: Long): String {
        val time = DateUtils.FORMAT_SHOW_TIME
        val flags = if (DateUtils.isToday(instantMs)) time else time or DAY_FLAGS
        return DateUtils.formatDateTime(context, instantMs, flags)
    }

    fun date(date: LocalDate): String {
        val start = date.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        return DateUtils.formatDateTime(context, start, WEEKDAY_FLAGS or DAY_FLAGS)
    }

    fun status(snapshot: Snapshot?, nowMs: Long): Status {
        val synced = snapshot?.syncedAtMs ?: 0L
        return when (snapshot?.freshness(nowMs)) {
            null -> Status(context.getString(R.string.widget_no_snapshot), false)
            Freshness.UNPAIRED -> Status(context.getString(R.string.widget_unpaired), false)
            Freshness.NEVER_SYNCED -> Status(context.getString(R.string.widget_never_synced), false)
            Freshness.FRESH -> Status(context.getString(R.string.widget_synced, clock(synced)), false)
            Freshness.STALE -> Status(context.getString(R.string.widget_stale, clock(synced)), true)
        }
    }

    fun label(metric: Metric): String = context.getString(
        when (metric) {
            Metric.READINESS -> R.string.widget_metric_readiness
            Metric.SLEEP -> R.string.widget_metric_sleep
            Metric.STEPS -> R.string.widget_metric_steps
            Metric.HEART_RATE -> R.string.widget_metric_heart_rate
            Metric.SPO2 -> R.string.widget_metric_spo2
            Metric.STRESS -> R.string.widget_metric_stress
            Metric.BATTERY -> R.string.widget_metric_battery
        },
    )

    fun metric(metric: Metric, snapshot: Snapshot): MetricText = when (metric) {
        Metric.READINESS -> MetricText(
            show(snapshot.readiness, ::integer),
            context.getString(R.string.widget_estimate),
            share(snapshot.readiness, 100),
        )
        Metric.SLEEP -> MetricText(
            show(snapshot.sleepMinutes, ::duration),
            context.getString(R.string.widget_sub_sleep_score, show(snapshot.sleepScore, ::integer)),
            null,
        )
        Metric.STEPS -> MetricText(
            show(snapshot.steps, ::integer),
            context.getString(R.string.widget_sub_steps_goal, integer(snapshot.stepGoal)),
            share(snapshot.steps, snapshot.stepGoal),
        )
        Metric.HEART_RATE -> MetricText(
            show(snapshot.heartRateMean, ::integer),
            context.getString(R.string.widget_sub_bpm_average),
            null,
        )
        Metric.SPO2 -> MetricText(
            show(snapshot.spo2, ::percent),
            context.getString(R.string.widget_sub_average),
            null,
        )
        Metric.STRESS -> MetricText(
            show(snapshot.stress, ::integer),
            context.getString(R.string.widget_sub_average),
            null,
        )
        Metric.BATTERY -> MetricText(
            show(snapshot.batteryPercent, ::percent),
            context.getString(R.string.widget_sub_battery),
            share(snapshot.batteryPercent, 100),
        )
    }

    fun show(value: Int?, text: (Int) -> String): String = value?.let(text) ?: none

    fun distance(meters: Double, units: Units): String = when (units) {
        Units.METRIC -> context.getString(R.string.widget_distance_km, decimals.format(meters / METERS_PER_KILOMETRE))
        Units.IMPERIAL -> context.getString(R.string.widget_distance_mi, decimals.format(meters / METERS_PER_MILE))
    }

    fun lastWorkout(workout: LastWorkout, units: Units): String {
        val kind = context.getString(kindLabel(workout.kind))
        val amount = workout.distanceMeters
            ?.takeIf { it >= MIN_DISTANCE_METERS }
            ?.let { distance(it, units) }
            ?: duration((workout.elapsedSeconds / 60.0).roundToInt())
        val zone = ZoneId.systemDefault()
        val day = Instant.ofEpochMilli(workout.startMs).atZone(zone).toLocalDate()
        val today = LocalDate.now(zone)
        return when (day) {
            today -> context.getString(R.string.widget_workout_last_today, kind, amount)
            today.minusDays(1) -> context.getString(R.string.widget_workout_last_yesterday, kind, amount)
            else -> context.getString(
                R.string.widget_workout_last_date,
                kind,
                DateUtils.formatDateTime(context, workout.startMs, DAY_FLAGS),
                amount,
            )
        }
    }

    private fun kindLabel(kind: WorkoutKind): Int = when (kind) {
        WorkoutKind.RUNNING -> R.string.widget_workout_type_running
        WorkoutKind.WALKING -> R.string.widget_workout_type_walking
        WorkoutKind.CYCLING -> R.string.widget_workout_type_cycling
        WorkoutKind.HIKING -> R.string.widget_workout_type_hiking
        WorkoutKind.STRENGTH -> R.string.widget_workout_type_strength
        WorkoutKind.TREADMILL -> R.string.widget_workout_type_treadmill
        WorkoutKind.STATIONARY_BIKE -> R.string.widget_workout_type_stationary_bike
        WorkoutKind.ELLIPTICAL -> R.string.widget_workout_type_elliptical
        WorkoutKind.YOGA -> R.string.widget_workout_type_yoga
        WorkoutKind.OTHER -> R.string.widget_workout_type_other
    }

    companion object {
        private const val METERS_PER_KILOMETRE = 1000.0
        private const val METERS_PER_MILE = 1609.344
        private const val MIN_DISTANCE_METERS = 10.0
        private const val DAY_FLAGS =
            DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH or DateUtils.FORMAT_NO_YEAR
        private const val WEEKDAY_FLAGS =
            DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_ABBREV_WEEKDAY

        fun share(value: Int?, total: Int): Float? = when {
            value == null || total <= 0 -> null
            else -> (value.toFloat() / total).coerceIn(0f, 1f)
        }
    }
}
