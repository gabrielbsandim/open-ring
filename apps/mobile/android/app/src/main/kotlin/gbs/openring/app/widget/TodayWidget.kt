package gbs.openring.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
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
import androidx.glance.layout.ColumnScope
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
private val LARGE_SIZE = DpSize(250.dp, 220.dp)

private enum class TodaySize(val maxFields: Int) { SMALL(1), MEDIUM(3), LARGE(6) }

class TodayWidgetReceiver : HomeWidgetGlanceWidgetReceiver<TodayWidget>() {
    override val glanceAppWidget = TodayWidget()
}

class TodayWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override val sizeMode = SizeMode.Responsive(setOf(SMALL_SIZE, MEDIUM_SIZE, LARGE_SIZE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { TodayContent(WidgetData.read(currentState<HomeWidgetGlanceState>().preferences)) }
    }
}

@Composable
private fun todaySizeBucket(): TodaySize {
    val size = LocalSize.current
    return when {
        size.width < 250.dp -> TodaySize.SMALL
        size.height < 220.dp -> TodaySize.MEDIUM
        else -> TodaySize.LARGE
    }
}

@Composable
private fun TodayContent(data: WidgetData) {
    val context = LocalContext.current
    val format = WidgetFormat(context)
    val palette = WidgetPalette.of(data.appearance.todayTheme)
    val snapshot = data.snapshot
    val sizeBucket = todaySizeBucket()
    val visible = data.appearance.todayMetrics.take(sizeBucket.maxFields)
    val nowMs = System.currentTimeMillis()
    val status = todayFooterStatus(snapshot, format, context, nowMs)
    val title = listOfNotNull(
        context.getString(R.string.widget_today_name),
        snapshot?.date?.let(format::date),
    ).joinToString(" · ")
    val noRingData = snapshot != null &&
        !snapshot.hasHealthData &&
        (snapshot.dayScore == null || Metric.DAY_SCORE !in visible)
    WidgetSurface(palette, WidgetLinks.TODAY) {
        when {
            visible.isEmpty() -> {
                Label(context.getString(R.string.widget_today_name), palette.textPrimary, 13.sp, bold = true)
                Gap(8)
                Message(context.getString(R.string.widget_today_no_metrics), palette)
            }
            snapshot == null -> {
                Label(context.getString(R.string.widget_today_name), palette.textPrimary, 13.sp, bold = true)
                Gap(8)
                Message(context.getString(R.string.widget_no_snapshot), palette)
            }
            !snapshot.paired && visible.all { it.requiresRing } -> {
                val heading = if (sizeBucket == TodaySize.SMALL) format.label(visible.first()) else context.getString(R.string.widget_today_name)
                Label(heading, palette.textPrimary, 13.sp, bold = true)
                Gap(8)
                Message(context.getString(R.string.widget_unpaired), palette)
                Spacer(modifier = GlanceModifier.defaultWeight())
                StatusLine(status, palette)
            }
            noRingData && visible.all { it.requiresRing } -> {
                HeaderRow(title, status, palette)
                Gap(8)
                Message(context.getString(R.string.widget_no_data), palette)
            }
            sizeBucket == TodaySize.SMALL -> {
                TodaySmall(visible.first(), snapshot, data.appearance.units, format, palette, status)
            }
            sizeBucket == TodaySize.MEDIUM -> {
                HeaderRow(title, status, palette)
                Gap(10)
                TodayMedium(visible, snapshot, data.appearance.units, format, palette, status.stale)
            }
            else -> {
                HeaderRow(title, status, palette)
                Gap(8)
                TodayLarge(visible, snapshot, data.appearance.units, format, palette, status.stale)
            }
        }
    }
}

private fun todayFooterStatus(
    snapshot: Snapshot?,
    format: WidgetFormat,
    context: Context,
    nowMs: Long,
): Status {
    if (snapshot != null && !snapshot.paired) {
        return Status(context.getString(R.string.widget_unpaired_short), false)
    }
    return format.status(snapshot, nowMs)
}

@Composable
private fun HeaderRow(title: String, status: Status, palette: WidgetPalette) {
    if (prefersSingleColumn()) {
        Column(modifier = GlanceModifier.fillMaxWidth()) {
            Label(title, palette.textPrimary, 13.sp, bold = true)
            StatusLine(status, palette)
        }
        return
    }
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Label(title, palette.textPrimary, 13.sp, bold = true, modifier = GlanceModifier.defaultWeight())
        Spacer(modifier = GlanceModifier.width(8.dp))
        StatusLine(status, palette)
    }
}

@Composable
private fun ColumnScope.TodaySmall(
    metric: Metric,
    snapshot: Snapshot,
    units: Units,
    format: WidgetFormat,
    palette: WidgetPalette,
    status: Status,
) {
    MetricBlock(metric, snapshot, units, format, palette, valueSize = 26.sp, stale = status.stale, modifier = GlanceModifier.fillMaxWidth())
    Spacer(modifier = GlanceModifier.defaultWeight())
    StatusLine(status, palette)
}

@Composable
private fun TodayMedium(
    metrics: List<Metric>,
    snapshot: Snapshot,
    units: Units,
    format: WidgetFormat,
    palette: WidgetPalette,
    stale: Boolean,
) {
    if (prefersSingleColumn()) {
        Column(modifier = GlanceModifier.fillMaxWidth()) {
            metrics.forEach { MetricRow(it, snapshot, units, format, palette, stale) }
        }
        return
    }
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        metrics.forEachIndexed { index, metric ->
            if (index > 0) Spacer(modifier = GlanceModifier.width(10.dp))
            MetricBlock(
                metric = metric,
                snapshot = snapshot,
                units = units,
                format = format,
                palette = palette,
                valueSize = 20.sp,
                stale = stale,
                modifier = GlanceModifier.defaultWeight(),
            )
        }
    }
}

@Composable
private fun TodayLarge(
    metrics: List<Metric>,
    snapshot: Snapshot,
    units: Units,
    format: WidgetFormat,
    palette: WidgetPalette,
    stale: Boolean,
) {
    val rest = if (metrics.first() == Metric.DAY_SCORE) {
        DayScoreHero(snapshot, format, palette, stale)
        val remaining = metrics.drop(1)
        if (remaining.isNotEmpty()) {
            Gap(8)
            Divider(palette)
            Gap(8)
        }
        remaining
    } else {
        metrics
    }
    if (rest.isEmpty()) return
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        if (prefersSingleColumn()) {
            rest.forEach { MetricRow(it, snapshot, units, format, palette, stale) }
            return@Column
        }
        rest.chunked(2).forEachIndexed { rowIndex, pair ->
            if (rowIndex > 0) Gap(8)
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                pair.forEachIndexed { colIndex, metric ->
                    if (colIndex > 0) Spacer(modifier = GlanceModifier.width(10.dp))
                    MetricBlock(
                        metric = metric,
                        snapshot = snapshot,
                        units = units,
                        format = format,
                        palette = palette,
                        valueSize = 16.sp,
                        stale = stale,
                        modifier = GlanceModifier.defaultWeight(),
                    )
                }
                if (pair.size == 1) Spacer(modifier = GlanceModifier.defaultWeight())
            }
        }
    }
}

@Composable
private fun DayScoreHero(snapshot: Snapshot, format: WidgetFormat, palette: WidgetPalette, stale: Boolean) {
    val display = format.dayScore(snapshot, stale)
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        MetricHeading(Metric.DAY_SCORE, format, palette, GlanceModifier)
        if (display.messageTitle != null) {
            Gap(4)
            Label(display.messageTitle, palette.textPrimary, 13.sp, bold = true)
            display.messageDetail?.let { Label(it, palette.textLabel, 10.sp, maxLines = 2) }
            return@Column
        }
        Gap(4)
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
            Label(display.value, palette.textPrimary, 30.sp, bold = true)
            Spacer(modifier = GlanceModifier.width(8.dp))
            Label(display.detail, palette.textLabel, 11.sp, maxLines = 2, modifier = GlanceModifier.defaultWeight())
        }
        Gap(6)
        PillarBar(display.pillarPoints, palette)
        Gap(4)
        Row(modifier = GlanceModifier.fillMaxWidth()) {
            format.pillarShortLabels().forEach { short ->
                Label(short, palette.textLabel, 9.sp, modifier = GlanceModifier.defaultWeight(), maxLines = 1)
            }
        }
    }
}

@Composable
private fun MetricHeading(metric: Metric, format: WidgetFormat, palette: WidgetPalette, modifier: GlanceModifier) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        Swatch(palette.accent(metric))
        Spacer(modifier = GlanceModifier.width(5.dp))
        Label(format.label(metric), palette.textSecondary, 11.sp, maxLines = 1)
    }
}

@Composable
private fun MetricBlock(
    metric: Metric,
    snapshot: Snapshot,
    units: Units,
    format: WidgetFormat,
    palette: WidgetPalette,
    valueSize: TextUnit,
    stale: Boolean,
    modifier: GlanceModifier,
) {
    if (metric == Metric.DAY_SCORE) {
        DayScoreColumn(format.dayScore(snapshot, stale), format, palette, valueSize, modifier)
        return
    }
    val text = format.metric(metric, snapshot, units)
    val scaledSize = if (metric == Metric.ENERGY || (metric == Metric.WEIGHT && snapshot.hideNumbers)) {
        (valueSize.value * 0.7f).sp
    } else {
        valueSize
    }
    Column(modifier = modifier) {
        MetricHeading(metric, format, palette, GlanceModifier)
        Gap(5)
        Label(text.value, palette.textPrimary, scaledSize, bold = true, maxLines = 2)
        text.progress?.let {
            Gap(5)
            ProgressBar(it, palette.accent(metric), palette)
        }
        Gap(5)
        Label(text.detail, palette.textLabel, 10.sp, maxLines = 2)
    }
}

@Composable
private fun DayScoreColumn(
    display: DayScoreDisplay,
    format: WidgetFormat,
    palette: WidgetPalette,
    valueSize: TextUnit,
    modifier: GlanceModifier,
) {
    Column(modifier = modifier) {
        MetricHeading(Metric.DAY_SCORE, format, palette, GlanceModifier)
        if (display.messageTitle != null) {
            Gap(6)
            Label(display.messageTitle, palette.textPrimary, 12.sp, bold = true, maxLines = 2)
            display.messageDetail?.let {
                Gap(3)
                Label(it, palette.textLabel, 10.sp, maxLines = 2)
            }
            return@Column
        }
        Gap(5)
        Label(display.value, palette.textPrimary, valueSize, bold = true)
        Gap(5)
        PillarBar(display.pillarPoints, palette)
        Gap(5)
        Label(display.detail, palette.textLabel, 10.sp, maxLines = 2)
    }
}

@Composable
private fun MetricRow(
    metric: Metric,
    snapshot: Snapshot,
    units: Units,
    format: WidgetFormat,
    palette: WidgetPalette,
    stale: Boolean,
) {
    val text = if (metric == Metric.DAY_SCORE) {
        val ds = format.dayScore(snapshot, stale)
        MetricText(ds.value, ds.messageDetail ?: ds.messageTitle ?: ds.detail, null)
    } else {
        format.metric(metric, snapshot, units)
    }
    Column(modifier = GlanceModifier.fillMaxWidth().padding(bottom = 4.dp)) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            MetricHeading(metric, format, palette, GlanceModifier.defaultWeight())
            Label(text.value, palette.textPrimary, 14.sp, bold = true)
        }
        Label(text.detail, palette.textLabel, 10.sp)
    }
}
