package gbs.openring.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.layout.width
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import gbs.openring.app.R

private val SMALL_SIZE = DpSize(110.dp, 110.dp)
private val MEDIUM_SIZE = DpSize(250.dp, 110.dp)
private val LARGE_SIZE = DpSize(250.dp, 200.dp)
private const val EFFORT_TARGET_DEFAULT = 150
private const val STRENGTH_TARGET_DEFAULT = 2

private enum class WeekSize { SMALL, MEDIUM, LARGE }

class ThisWeekWidgetReceiver : HomeWidgetGlanceWidgetReceiver<ThisWeekWidget>() {
    override val glanceAppWidget = ThisWeekWidget()
}

class ThisWeekWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Responsive(setOf(SMALL_SIZE, MEDIUM_SIZE, LARGE_SIZE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { ThisWeekContent(WidgetData.read(currentState<HomeWidgetGlanceState>().preferences)) }
    }
}

@Composable
private fun weekSizeBucket(): WeekSize {
    val size = LocalSize.current
    return when {
        size.width < 250.dp -> WeekSize.SMALL
        size.height < 200.dp -> WeekSize.MEDIUM
        else -> WeekSize.LARGE
    }
}

@Composable
private fun ThisWeekContent(data: WidgetData) {
    val context = LocalContext.current
    val format = WidgetFormat(context)
    val palette = WidgetPalette.of(data.appearance.appTheme)
    val snapshot = data.snapshot
    val sizeBucket = weekSizeBucket()
    val hasEffort = snapshot != null && ("effort" in snapshot.enabledModules || snapshot.effort != null)
    val hasGoals = snapshot != null && ("goals" in snapshot.enabledModules || snapshot.goals != null)
    val link = if (snapshot != null && !hasEffort && !hasGoals) WidgetLinks.MODULES else WidgetLinks.TODAY
    val nowMs = System.currentTimeMillis()
    val status = if (snapshot != null && !snapshot.paired) {
        Status(context.getString(R.string.widget_unpaired_short), false)
    } else {
        format.status(snapshot, nowMs)
    }
    WidgetSurface(palette, link) {
        when {
            snapshot == null -> {
                Label(context.getString(R.string.widget_this_week_name), palette.textPrimary, 13.sp, bold = true)
                Gap(8)
                Message(context.getString(R.string.widget_no_snapshot), palette)
            }
            !hasEffort && !hasGoals -> {
                Label(context.getString(R.string.widget_this_week_name), palette.textPrimary, 13.sp, bold = true)
                Gap(8)
                Message(context.getString(R.string.widget_this_week_off), palette)
            }
            sizeBucket == WeekSize.SMALL -> {
                Column(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                    if (hasEffort) {
                        EffortSection(snapshot, format, palette, largeNumber = true)
                    } else {
                        GoalsSection(snapshot, format, palette, large = false)
                    }
                }
                StatusLine(status, palette)
            }
            else -> {
                WeekHeader(snapshot, format, palette)
                Gap(8)
                if (sizeBucket == WeekSize.MEDIUM && !prefersSingleColumn() && hasEffort && hasGoals) {
                    Row(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                        Column(modifier = GlanceModifier.defaultWeight()) {
                            EffortSection(snapshot, format, palette, largeNumber = false)
                        }
                        Spacer(modifier = GlanceModifier.width(10.dp))
                        Column(modifier = GlanceModifier.defaultWeight()) {
                            GoalsSection(snapshot, format, palette, large = false)
                        }
                    }
                } else {
                    Column(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                        if (hasEffort) EffortSection(snapshot, format, palette, largeNumber = false)
                        if (hasEffort && hasGoals) {
                            Gap(8)
                            Divider(palette)
                            Gap(8)
                        }
                        if (hasGoals) GoalsSection(snapshot, format, palette, large = sizeBucket == WeekSize.LARGE)
                    }
                }
                StatusLine(status, palette)
            }
        }
    }
}

@Composable
private fun WeekHeader(snapshot: Snapshot, format: WidgetFormat, palette: WidgetPalette) {
    val context = LocalContext.current
    val goals = snapshot.goals
    val range = if (goals?.monday != null && goals.sunday != null) format.dateRange(goals.monday, goals.sunday) else null
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Label(context.getString(R.string.widget_this_week_name), palette.textPrimary, 13.sp, bold = true, modifier = GlanceModifier.defaultWeight())
        range?.let { Label(it, palette.textLabel, 10.sp) }
    }
}

@Composable
private fun EffortSection(snapshot: Snapshot, format: WidgetFormat, palette: WidgetPalette, largeNumber: Boolean) {
    val context = LocalContext.current
    val paired = snapshot.paired
    val effort = if (paired) snapshot.effort else null
    val target = effort?.targetPoints ?: EFFORT_TARGET_DEFAULT
    val pointsText = format.show(effort?.points, format::integer)
    val strengthText = format.show(effort?.strengthDays, format::integer)
    val strengthTarget = effort?.strengthTarget ?: STRENGTH_TARGET_DEFAULT
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Swatch(palette.textPrimary)
            Spacer(modifier = GlanceModifier.width(5.dp))
            Label(context.getString(R.string.widget_metric_effort), palette.textSecondary, 11.sp)
        }
        Gap(4)
        Row(verticalAlignment = Alignment.Bottom) {
            Label(pointsText, palette.textPrimary, if (largeNumber) 28.sp else 22.sp, bold = true)
            Spacer(modifier = GlanceModifier.width(4.dp))
            Label(context.getString(R.string.widget_sub_steps_goal, format.integer(target)), palette.textLabel, 10.sp)
        }
        WidgetFormat.share(effort?.points, target)?.let {
            Gap(4)
            ProgressBar(it, palette.activity, palette)
        }
        Gap(4)
        Label(
            context.getString(R.string.widget_effort_detail, strengthText, format.integer(strengthTarget)),
            palette.textLabel,
            10.sp,
            maxLines = 2,
        )
    }
}

@Composable
private fun GoalsSection(snapshot: Snapshot, format: WidgetFormat, palette: WidgetPalette, large: Boolean) {
    val context = LocalContext.current
    val goals = snapshot.goals
    val tag = goals?.let(format::goalsTag)
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        if (large) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Row(modifier = GlanceModifier.defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                    Swatch(palette.textLabel)
                    Spacer(modifier = GlanceModifier.width(5.dp))
                    Label(context.getString(R.string.widget_goals_name), palette.textSecondary, 11.sp, maxLines = 1)
                }
                tag?.let { Label(it, palette.textLabel, 10.sp, maxLines = 1) }
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Swatch(palette.textLabel)
                Spacer(modifier = GlanceModifier.width(5.dp))
                Label(context.getString(R.string.widget_goals_name), palette.textSecondary, 11.sp, maxLines = 1)
            }
            tag?.let { Label(it, palette.textLabel, 10.sp, maxLines = 1) }
        }
        Gap(4)
        when {
            goals == null || goals.state == GoalsState.BASE -> Label(context.getString(R.string.widget_goals_waiting), palette.textLabel, 11.sp, maxLines = 2)
            goals.state == GoalsState.PAUSED -> Label(context.getString(R.string.widget_goals_paused), palette.textLabel, 11.sp, maxLines = 3)
            goals.state == GoalsState.HOLD -> Label(context.getString(R.string.widget_goals_hold), palette.textLabel, 11.sp, maxLines = 2)
            goals.state == GoalsState.RECOVERY -> Label(context.getString(R.string.widget_goals_recovery), palette.textLabel, 11.sp, maxLines = 2)
            goals.state == GoalsState.REVIEW -> Label(context.getString(R.string.widget_goals_review), palette.textPrimary, 12.sp, bold = true, maxLines = 2)
            else -> {
                val showDots = large && snapshot.paired && !prefersSingleColumn()
                Column(modifier = GlanceModifier.fillMaxWidth()) {
                    goals.levers.take(3).forEach { lever ->
                        val ratio = if (!snapshot.paired) {
                            format.none
                        } else {
                            context.getString(R.string.widget_goals_ratio, format.integer(lever.achieved), format.integer(lever.goal))
                        }
                        Row(modifier = GlanceModifier.fillMaxWidth().padding(bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                            Label(format.goalLeverLabel(lever.kind), palette.textLabel, 11.sp, modifier = GlanceModifier.defaultWeight(), maxLines = 1)
                            if (showDots && !lever.days.isNullOrEmpty()) {
                                DotsRow(lever.days, palette)
                                Spacer(modifier = GlanceModifier.width(6.dp))
                            }
                            Label(ratio, palette.textPrimary, 11.sp, bold = true)
                        }
                    }
                }
            }
        }
    }
}
