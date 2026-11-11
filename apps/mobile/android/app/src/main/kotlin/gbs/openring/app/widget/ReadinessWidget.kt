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

class ReadinessWidgetReceiver : HomeWidgetGlanceWidgetReceiver<ReadinessWidget>() {
    override val glanceAppWidget = ReadinessWidget()
}

class ReadinessWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { ReadinessContent(WidgetData.read(currentState<HomeWidgetGlanceState>().preferences)) }
    }
}

@Composable
private fun ReadinessContent(data: WidgetData) {
    val context = LocalContext.current
    val format = WidgetFormat(context)
    val palette = WidgetPalette.of(data.appearance.appTheme)
    val snapshot = data.snapshot
    val score = snapshot?.readiness
    val scoreText = format.show(score, format::integer)
    WidgetSurface(palette, WidgetLinks.READINESS) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Label(
                text = context.getString(R.string.widget_readiness_name),
                color = palette.textPrimary,
                size = 12.sp,
                bold = true,
                modifier = GlanceModifier.defaultWeight(),
            )
            Label(context.getString(R.string.widget_estimate), palette.textLabel, 10.sp)
        }
        Gap(8)
        if (prefersSingleColumn()) {
            Label(scoreText, palette.textPrimary, 30.sp, bold = true)
            Gap(6)
            Factors(snapshot, format, palette)
        } else {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Label(scoreText, palette.textPrimary, 34.sp, bold = true)
                Spacer(modifier = GlanceModifier.width(12.dp))
                Column(modifier = GlanceModifier.defaultWeight()) { Factors(snapshot, format, palette) }
            }
        }
        Gap(8)
        WidgetFormat.share(score, 100)?.let { ProgressBar(it, palette.textPrimary, palette) }
        Gap(6)
        ReadinessFooter(snapshot, format, palette)
    }
}

@Composable
private fun Factors(snapshot: Snapshot?, format: WidgetFormat, palette: WidgetPalette) {
    val context = LocalContext.current
    Factor(context.getString(R.string.widget_resting_hr), format.show(snapshot?.restingHeartRate, format::integer), palette)
    Factor(context.getString(R.string.widget_hrv), format.show(snapshot?.hrv, format::integer), palette)
    Factor(context.getString(R.string.widget_metric_sleep), format.show(snapshot?.sleepScore, format::integer), palette)
}

@Composable
private fun Factor(label: String, value: String, palette: WidgetPalette) {
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        Label(label, palette.textLabel, 11.sp, modifier = GlanceModifier.defaultWeight())
        Label(value, palette.textPrimary, 11.sp, bold = true)
    }
}

@Composable
private fun ReadinessFooter(snapshot: Snapshot?, format: WidgetFormat, palette: WidgetPalette) {
    val context = LocalContext.current
    val now = System.currentTimeMillis()
    val pending = snapshot?.paired == true && snapshot.readiness == null
    if (pending) {
        Label(context.getString(R.string.widget_readiness_pending), palette.textSecondary, 10.sp, maxLines = 2)
    }
    StatusLine(format.status(snapshot, now), palette)
}
