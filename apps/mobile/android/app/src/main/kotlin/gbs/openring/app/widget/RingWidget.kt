package gbs.openring.app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.size
import androidx.glance.layout.width
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import gbs.openring.app.R

private const val LOW_BATTERY_PERCENT = 20

class RingWidgetReceiver : HomeWidgetGlanceWidgetReceiver<RingWidget>() {
    override val glanceAppWidget = RingWidget()
}

class RingWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { RingContent(WidgetData.read(currentState<HomeWidgetGlanceState>().preferences)) }
    }
}

@Composable
private fun RingContent(data: WidgetData) {
    val context = LocalContext.current
    val format = WidgetFormat(context)
    val palette = WidgetPalette.of(data.appearance.appTheme)
    val snapshot = data.snapshot
    val nowMs = System.currentTimeMillis()
    val freshness = snapshot?.freshness(nowMs)
    val paired = snapshot != null && freshness != Freshness.UNPAIRED && freshness != Freshness.NEVER_SYNCED
    val battery = if (paired) snapshot?.batteryPercent else null
    val charging = paired && snapshot?.batteryCharging == true && freshness != Freshness.STALE
    val status = format.ringStatus(snapshot, nowMs, LOW_BATTERY_PERCENT)
    WidgetSurface(palette, WidgetLinks.RING, verticalAlignment = Alignment.CenterVertically) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Label(
                text = context.getString(R.string.widget_ring_name),
                color = palette.textPrimary,
                size = 13.sp,
                bold = true,
                modifier = GlanceModifier.defaultWeight(),
            )
            if (charging && battery != null) {
                Image(
                    provider = ImageProvider(R.drawable.ic_widget_bolt),
                    contentDescription = null,
                    modifier = GlanceModifier.size(14.dp),
                    colorFilter = ColorFilter.tint(palette.activity),
                )
                Spacer(modifier = GlanceModifier.width(4.dp))
            }
            Label(format.show(battery, format::percent), palette.textPrimary, 14.sp, bold = true)
        }
        WidgetFormat.share(battery, 100)?.let {
            Gap(6)
            ProgressBar(it, batteryColor(battery, status.stale, charging, palette), palette)
        }
        Gap(6)
        StatusLine(status, palette)
    }
}

private fun batteryColor(percent: Int?, stale: Boolean, charging: Boolean, palette: WidgetPalette) = when {
    stale -> palette.textLabel
    charging -> palette.activity
    percent != null && percent <= LOW_BATTERY_PERCENT -> palette.stress
    else -> palette.activity
}
