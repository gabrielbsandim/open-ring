package gbs.openring.app.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import gbs.openring.app.MainActivity
import gbs.openring.app.R

internal object WidgetLinks {
    const val READINESS = "openring://widget/today/readiness"
    const val TODAY = "openring://widget/today"
    const val RING = "openring://widget/ring"
    const val WORKOUT = "openring://widget/activity/workout"
    const val TODAY_CONFIG = "openring://widget/ring/settings/widgets/today"
    const val MODULES = "openring://widget/ring/settings/modules"
}

internal const val SINGLE_COLUMN_FONT_SCALE = 1.3f

private val PILLAR_MAX_WEIGHTS = floatArrayOf(30f, 35f, 20f, 10f, 5f)

internal fun openIntent(context: Context, link: String): Intent =
    Intent(Intent.ACTION_VIEW, Uri.parse(link), context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

@Composable
internal fun prefersSingleColumn(): Boolean =
    LocalContext.current.resources.configuration.fontScale > SINGLE_COLUMN_FONT_SCALE

@Composable
internal fun WidgetSurface(
    palette: WidgetPalette,
    link: String,
    verticalAlignment: Alignment.Vertical = Alignment.Top,
    content: @Composable ColumnScope.() -> Unit,
) {
    val context = LocalContext.current
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(palette.surface)
            .cornerRadius(28.dp)
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .clickable(actionStartActivity(openIntent(context, link))),
        verticalAlignment = verticalAlignment,
        content = content,
    )
}

@Composable
internal fun Label(
    text: String,
    color: ColorProvider,
    size: TextUnit,
    modifier: GlanceModifier = GlanceModifier,
    bold: Boolean = false,
    maxLines: Int = Int.MAX_VALUE,
) {
    Text(
        text = text,
        modifier = modifier,
        maxLines = maxLines,
        style = TextStyle(
            color = color,
            fontSize = size,
            fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal,
        ),
    )
}

@Composable
internal fun StatusLine(status: Status, palette: WidgetPalette) {
    if (!status.stale) {
        Label(text = status.text, color = palette.textLabel, size = 10.sp, maxLines = 2)
        return
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Image(
            provider = ImageProvider(R.drawable.ic_widget_warn),
            contentDescription = null,
            modifier = GlanceModifier.size(12.dp),
            colorFilter = ColorFilter.tint(palette.stress),
        )
        Spacer(modifier = GlanceModifier.width(4.dp))
        Label(text = status.text, color = palette.stress, size = 10.sp, bold = true, maxLines = 2)
    }
}

@Composable
internal fun Message(text: String, palette: WidgetPalette) {
    Label(text = text, color = palette.textLabel, size = 13.sp)
}

@Composable
internal fun ProgressBar(progress: Float, color: ColorProvider, palette: WidgetPalette) {
    LinearProgressIndicator(
        progress = progress,
        modifier = GlanceModifier.fillMaxWidth().height(5.dp),
        color = color,
        backgroundColor = palette.track,
    )
}

@Composable
internal fun PillarBar(pillarPoints: List<Double?>?, palette: WidgetPalette) {
    val colors = listOf(palette.sleep, palette.activity, palette.heart, palette.stress, palette.oxygen)
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        PILLAR_MAX_WEIGHTS.forEachIndexed { index, maxWeight ->
            if (index > 0) Spacer(modifier = GlanceModifier.width(3.dp))
            val earned = pillarPoints?.getOrNull(index)
            val progress = if (earned == null) 0f else (earned.toFloat() / maxWeight).coerceIn(0f, 1f)
            LinearProgressIndicator(
                progress = progress,
                modifier = GlanceModifier.defaultWeight().height(5.dp),
                color = colors[index],
                backgroundColor = palette.track,
            )
        }
    }
}

@Composable
internal fun Swatch(color: ColorProvider) {
    Box(modifier = GlanceModifier.size(8.dp).background(color).cornerRadius(2.dp)) {}
}

@Composable
internal fun Gap(height: Int) {
    Spacer(modifier = GlanceModifier.height(height.dp))
}
