package gbs.openring.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.width
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import gbs.openring.app.R

class TodayWidgetReceiver : HomeWidgetGlanceWidgetReceiver<TodayWidget>() {
    override val glanceAppWidget = TodayWidget()
}

class TodayWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { TodayContent(WidgetData.read(currentState<HomeWidgetGlanceState>().preferences)) }
    }
}

@Composable
private fun TodayContent(data: WidgetData) {
    val context = LocalContext.current
    val format = WidgetFormat(context)
    val palette = WidgetPalette.of(data.appearance.todayTheme)
    val snapshot = data.snapshot
    val status = format.status(snapshot, System.currentTimeMillis())
    val title = listOfNotNull(
        context.getString(R.string.widget_today_name),
        snapshot?.date?.let(format::date),
    ).joinToString(" · ")
    WidgetSurface(palette, WidgetLinks.TODAY) {
        if (prefersSingleColumn()) {
            Label(title, palette.textPrimary, 13.sp, bold = true)
            StatusLine(status, palette)
        } else {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Label(title, palette.textPrimary, 13.sp, bold = true, modifier = GlanceModifier.defaultWeight())
                Spacer(modifier = GlanceModifier.width(8.dp))
                StatusLine(status, palette)
            }
        }
        Gap(10)
        TodayBody(data.appearance.todayMetrics, snapshot, format, palette)
    }
}

@Composable
private fun TodayBody(metrics: List<Metric>, snapshot: Snapshot?, format: WidgetFormat, palette: WidgetPalette) {
    val context = LocalContext.current
    when {
        metrics.isEmpty() -> Message(context.getString(R.string.widget_today_no_metrics), palette)
        snapshot == null -> Message(context.getString(R.string.widget_no_snapshot), palette)
        !snapshot.paired -> Message(context.getString(R.string.widget_unpaired), palette)
        !snapshot.hasHealthData -> Message(context.getString(R.string.widget_no_data), palette)
        prefersSingleColumn() -> metrics.forEach { MetricRow(it, format.metric(it, snapshot), format, palette) }
        else -> Row(modifier = GlanceModifier.fillMaxWidth()) {
            metrics.forEachIndexed { index, metric ->
                if (index > 0) Spacer(modifier = GlanceModifier.width(10.dp))
                MetricColumn(metric, format.metric(metric, snapshot), format, palette, GlanceModifier.defaultWeight())
            }
        }
    }
}

@Composable
private fun MetricHeading(metric: Metric, format: WidgetFormat, palette: WidgetPalette, modifier: GlanceModifier) {
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        Swatch(palette.accent(metric))
        Spacer(modifier = GlanceModifier.width(5.dp))
        Label(format.label(metric), palette.textSecondary, 11.sp)
    }
}

@Composable
private fun MetricColumn(
    metric: Metric,
    text: MetricText,
    format: WidgetFormat,
    palette: WidgetPalette,
    modifier: GlanceModifier,
) {
    Column(modifier = modifier) {
        MetricHeading(metric, format, palette, GlanceModifier)
        Gap(6)
        Label(text.value, palette.textPrimary, 22.sp, bold = true)
        text.progress?.let {
            Gap(6)
            ProgressBar(it, palette.accent(metric), palette)
        }
        Gap(6)
        Label(text.detail, palette.textLabel, 10.sp, maxLines = 2)
    }
}

@Composable
private fun MetricRow(metric: Metric, text: MetricText, format: WidgetFormat, palette: WidgetPalette) {
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        MetricHeading(metric, format, palette, GlanceModifier.defaultWeight())
        Label(text.value, palette.textPrimary, 14.sp, bold = true)
    }
    Label(text.detail, palette.textLabel, 10.sp)
    Gap(4)
}
