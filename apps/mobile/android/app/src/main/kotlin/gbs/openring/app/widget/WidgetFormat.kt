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

internal data class DayScoreDisplay(
    val value: String,
    val detail: String,
    val messageTitle: String? = null,
    val messageDetail: String? = null,
    val pillarPoints: List<Double?>? = null,
    val partial: Boolean = false,
)

internal class WidgetFormat(private val context: Context) {
    private val locale = context.resources.configuration.locales[0]
    private val numbers = NumberFormat.getIntegerInstance(locale)
    private val oneDecimal = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 1
        maximumFractionDigits = 1
    }
    private val decimals = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 2
        maximumFractionDigits = 2
    }

    val none: String = context.getString(R.string.widget_no_value)

    fun integer(value: Int): String = numbers.format(value)

    fun decimal(value: Double): String = oneDecimal.format(value)

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

    fun dateRange(monday: LocalDate, sunday: LocalDate): String {
        val zone = ZoneId.systemDefault()
        val start = monday.atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        val end = sunday.atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        return DateUtils.formatDateRange(context, start, end, DAY_FLAGS)
    }

    fun goalLeverLabel(kind: GoalLeverKind): String = context.getString(
        when (kind) {
            GoalLeverKind.STRENGTH_DAYS -> R.string.widget_lever_strength
            GoalLeverKind.SLEEP_WINDOW -> R.string.widget_metric_sleep
            GoalLeverKind.STEPS -> R.string.widget_metric_steps
            GoalLeverKind.EFFORT_POINTS -> R.string.widget_metric_effort
            GoalLeverKind.WAKE_TIME -> R.string.widget_lever_wake
        },
    )

    fun goalsTag(goals: GoalsData): String = when (goals.state) {
        GoalsState.REVIEW -> context.getString(R.string.widget_goals_tag_review)
        GoalsState.PAUSED -> context.getString(R.string.widget_goals_tag_paused)
        GoalsState.HOLD -> context.getString(R.string.widget_goals_tag_hold)
        GoalsState.BASE -> context.getString(R.string.widget_goals_tag_base)
        GoalsState.RECOVERY -> context.getString(R.string.widget_goals_tag_recovery)
        GoalsState.RUNNING -> when {
            goals.maintenance -> context.getString(R.string.widget_goals_tag_maintenance)
            goals.weekNumber == null -> context.getString(R.string.widget_goals_name)
            goals.blockWeeks == null -> context.getString(R.string.widget_goals_tag_week, integer(goals.weekNumber))
            else -> context.getString(R.string.widget_goals_tag_week_of, integer(goals.weekNumber), integer(goals.blockWeeks))
        }
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

    fun ringStatus(snapshot: Snapshot?, nowMs: Long, lowThreshold: Int): Status {
        val synced = snapshot?.syncedAtMs ?: 0L
        val freshness = snapshot?.freshness(nowMs)
        if (freshness == Freshness.UNPAIRED) {
            return Status(context.getString(R.string.widget_unpaired_short), false)
        }
        val percent = snapshot?.batteryPercent
        if (freshness == Freshness.FRESH && percent != null) {
            if (snapshot.batteryCharging == true) {
                return Status(context.getString(R.string.widget_ring_charging, clock(synced)), false)
            }
            if (percent <= lowThreshold) {
                return Status(context.getString(R.string.widget_ring_low_battery, clock(synced)), false)
            }
        }
        return status(snapshot, nowMs)
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
            Metric.DAY_SCORE -> R.string.widget_metric_day_score
            Metric.WEIGHT -> R.string.widget_metric_weight
            Metric.ENERGY -> R.string.widget_metric_energy
            Metric.EFFORT -> R.string.widget_metric_effort
        },
    )

    fun bandLabel(band: DayScoreBand): String = context.getString(
        when (band) {
            DayScoreBand.GREAT -> R.string.widget_day_score_band_great
            DayScoreBand.GOOD -> R.string.widget_day_score_band_good
            DayScoreBand.MIXED -> R.string.widget_day_score_band_mixed
            DayScoreBand.LOW -> R.string.widget_day_score_band_low
        },
    )

    fun directionLabel(direction: WeightDirection): String = context.getString(
        when (direction) {
            WeightDirection.FALLING -> R.string.widget_weight_direction_falling
            WeightDirection.RISING -> R.string.widget_weight_direction_rising
            WeightDirection.STEADY -> R.string.widget_weight_direction_steady
            WeightDirection.BUILDING -> R.string.widget_weight_direction_building
        },
    )

    fun weightValue(weight: WeightData?, units: Units, hideNumbers: Boolean): String {
        if (weight == null) return none
        val kg = weight.trendKilograms
        if (hideNumbers || kg == null) return directionLabel(weight.direction)
        return when (units) {
            Units.METRIC -> context.getString(R.string.widget_weight_unit_kg, decimal(kg))
            Units.IMPERIAL -> context.getString(
                R.string.widget_weight_unit_lb,
                decimal(kg / KILOGRAMS_PER_POUND),
            )
        }
    }

    fun energyRange(energy: EnergyData?): String = when (energy) {
        null -> none
        else -> context.getString(
            R.string.widget_energy_range,
            integer(energy.lowKcal),
            integer(energy.highKcal),
        )
    }

    fun metric(metric: Metric, snapshot: Snapshot, units: Units = Units.METRIC): MetricText {
        val disconnected = !snapshot.paired && metric.requiresRing
        return when (metric) {
            Metric.READINESS -> MetricText(
                show(if (disconnected) null else snapshot.readiness, ::integer),
                context.getString(R.string.widget_estimate),
                if (disconnected) null else share(snapshot.readiness, 100),
            )
            Metric.SLEEP -> MetricText(
                show(if (disconnected) null else snapshot.sleepMinutes, ::duration),
                context.getString(
                    R.string.widget_sub_sleep_score,
                    show(if (disconnected) null else snapshot.sleepScore, ::integer),
                ),
                null,
            )
            Metric.STEPS -> MetricText(
                show(if (disconnected) null else snapshot.steps, ::integer),
                context.getString(R.string.widget_sub_steps_goal, integer(snapshot.stepGoal)),
                if (disconnected) null else share(snapshot.steps, snapshot.stepGoal),
            )
            Metric.HEART_RATE -> MetricText(
                show(if (disconnected) null else snapshot.heartRateMean, ::integer),
                context.getString(R.string.widget_sub_bpm_average),
                null,
            )
            Metric.SPO2 -> MetricText(
                show(if (disconnected) null else snapshot.spo2, ::percent),
                context.getString(R.string.widget_sub_average),
                null,
            )
            Metric.STRESS -> MetricText(
                show(if (disconnected) null else snapshot.stress, ::integer),
                context.getString(R.string.widget_sub_average),
                null,
            )
            Metric.BATTERY -> MetricText(
                show(if (disconnected) null else snapshot.batteryPercent, ::percent),
                context.getString(R.string.widget_sub_battery),
                if (disconnected) null else share(snapshot.batteryPercent, 100),
            )
            Metric.DAY_SCORE -> {
                val display = dayScore(snapshot, stale = false)
                MetricText(
                    display.value,
                    display.messageTitle ?: display.detail,
                    if (disconnected) null else share(snapshot.dayScore?.score, 100),
                )
            }
            Metric.WEIGHT -> MetricText(
                weightValue(snapshot.weight, units, snapshot.hideNumbers),
                context.getString(R.string.widget_weight_trend),
                null,
            )
            Metric.ENERGY -> MetricText(
                if (disconnected) none else energyRange(snapshot.energy),
                context.getString(R.string.widget_sub_energy),
                null,
            )
            Metric.EFFORT -> {
                val effort = if (disconnected) null else snapshot.effort
                MetricText(
                    show(effort?.points, ::integer),
                    context.getString(
                        R.string.widget_sub_effort,
                        integer(effort?.targetPoints ?: EFFORT_TARGET_DEFAULT),
                        show(effort?.strengthDays, ::integer),
                        integer(effort?.strengthTarget ?: STRENGTH_TARGET_DEFAULT),
                    ),
                    share(effort?.points, effort?.targetPoints ?: 0),
                )
            }
        }
    }

    fun dayScore(snapshot: Snapshot, stale: Boolean): DayScoreDisplay {
        if (!snapshot.paired) {
            return DayScoreDisplay(value = none, detail = context.getString(R.string.widget_readiness_pending))
        }
        val day = snapshot.dayScore
            ?: return DayScoreDisplay(value = none, detail = context.getString(R.string.widget_readiness_pending))
        val bandText = day.band?.let(::bandLabel) ?: context.getString(R.string.widget_estimate)
        return when (day.kind) {
            DayScoreKind.FIRST_DAYS -> DayScoreDisplay(
                value = none,
                detail = "",
                messageTitle = context.getString(R.string.widget_day_score_first_days_title),
                messageDetail = context.getString(R.string.widget_day_score_first_days_detail, integer(day.coverage)),
            )
            DayScoreKind.NO_SCORE -> DayScoreDisplay(
                value = none,
                detail = "",
                messageTitle = context.getString(R.string.widget_metric_day_score),
                messageDetail = context.getString(
                    when (day.gap) {
                        DayScoreGap.NIGHT, null -> R.string.widget_day_score_none_night
                        DayScoreGap.STEPS -> R.string.widget_day_score_none_steps
                        DayScoreGap.COVERAGE -> R.string.widget_day_score_none_coverage
                    },
                ),
            )
            DayScoreKind.AFTER_MIDNIGHT -> DayScoreDisplay(
                value = show(day.score, ::integer),
                detail = context.getString(R.string.widget_day_score_yesterday_final, bandText),
                pillarPoints = day.pillarPoints,
            )
            DayScoreKind.PARTIAL -> DayScoreDisplay(
                value = show(day.score, ::integer),
                detail = context.getString(R.string.widget_day_score_partial, bandText, integer(day.coverage)),
                pillarPoints = day.pillarPoints,
                partial = true,
            )
            DayScoreKind.FULL -> {
                val timestamp = day.asOfMs ?: snapshot.syncedAtMs
                val timeStr = timestamp?.let(::clock) ?: none
                val detail = context.getString(
                    if (stale) R.string.widget_day_score_as_of else R.string.widget_day_score_so_far,
                    bandText,
                    timeStr,
                )
                DayScoreDisplay(
                    value = show(day.score, ::integer),
                    detail = detail,
                    pillarPoints = day.pillarPoints,
                )
            }
        }
    }

    fun pillarShortLabels(): List<String> = listOf(
        context.getString(R.string.widget_pillar_sleep_short),
        context.getString(R.string.widget_pillar_move_short),
        context.getString(R.string.widget_pillar_rec_short),
        context.getString(R.string.widget_pillar_stress_short),
        context.getString(R.string.widget_pillar_spo2_short),
    )

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
        private const val EFFORT_TARGET_DEFAULT = 150
        private const val STRENGTH_TARGET_DEFAULT = 2
        private const val KILOGRAMS_PER_POUND = 0.45359237
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
