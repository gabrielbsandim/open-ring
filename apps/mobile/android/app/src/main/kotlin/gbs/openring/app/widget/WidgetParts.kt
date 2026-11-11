package gbs.openring.app.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
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
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import gbs.openring.app.MainActivity

internal object WidgetLinks {
    const val READINESS = "openring://widget/today/readiness"
    const val TODAY = "openring://widget/today"
    const val RING = "openring://widget/ring"
    const val WORKOUT = "openring://widget/activity/workout"
    const val TODAY_CONFIG = "openring://widget/ring/settings/widgets/today"
}

internal const val SINGLE_COLUMN_FONT_SCALE = 1.3f

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
    Label(
        text = status.text,
        color = if (status.stale) palette.stress else palette.textLabel,
        size = 10.sp,
        bold = status.stale,
        maxLines = 2,
    )
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
internal fun Swatch(color: ColorProvider) {
    Box(modifier = GlanceModifier.size(8.dp).background(color).cornerRadius(2.dp)) {}
}

@Composable
internal fun Gap(height: Int) {
    Spacer(modifier = GlanceModifier.height(height.dp))
}
