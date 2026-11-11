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
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.size
import androidx.glance.layout.width
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import gbs.openring.app.R

class WorkoutWidgetReceiver : HomeWidgetGlanceWidgetReceiver<WorkoutWidget>() {
    override val glanceAppWidget = WorkoutWidget()
}

class WorkoutWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { WorkoutContent(WidgetData.read(currentState<HomeWidgetGlanceState>().preferences)) }
    }
}

@Composable
private fun WorkoutContent(data: WidgetData) {
    val context = LocalContext.current
    val palette = WidgetPalette.of(data.appearance.appTheme)
    val last = data.snapshot?.lastWorkout
    val subtitle = last
        ?.let { WidgetFormat(context).lastWorkout(it, data.appearance.units) }
        ?: context.getString(R.string.widget_workout_subtitle)
    WidgetSurface(palette, WidgetLinks.WORKOUT, verticalAlignment = Alignment.CenterVertically) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = GlanceModifier.size(44.dp).background(palette.activity).cornerRadius(22.dp),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    provider = ImageProvider(R.drawable.ic_widget_play),
                    contentDescription = null,
                    modifier = GlanceModifier.size(20.dp),
                    colorFilter = ColorFilter.tint(palette.onAccent),
                )
            }
            Spacer(modifier = GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Label(context.getString(R.string.widget_workout_name), palette.textPrimary, 15.sp, bold = true)
                Label(subtitle, palette.textLabel, 11.sp, maxLines = 2)
            }
            Image(
                provider = ImageProvider(R.drawable.ic_widget_chevron),
                contentDescription = null,
                modifier = GlanceModifier.size(18.dp),
                colorFilter = ColorFilter.tint(palette.textLabel),
            )
        }
    }
}
