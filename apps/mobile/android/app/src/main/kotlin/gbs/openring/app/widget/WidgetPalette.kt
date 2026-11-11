package gbs.openring.app.widget

import androidx.annotation.ColorRes
import androidx.glance.unit.ColorProvider
import gbs.openring.app.R

internal class WidgetPalette private constructor(
    @ColorRes surface: Int,
    @ColorRes track: Int,
    @ColorRes textPrimary: Int,
    @ColorRes textSecondary: Int,
    @ColorRes textLabel: Int,
    @ColorRes sleep: Int,
    @ColorRes heart: Int,
    @ColorRes activity: Int,
    @ColorRes oxygen: Int,
    @ColorRes stress: Int,
    @ColorRes onAccent: Int,
) {
    val surface = ColorProvider(surface)
    val track = ColorProvider(track)
    val textPrimary = ColorProvider(textPrimary)
    val textSecondary = ColorProvider(textSecondary)
    val textLabel = ColorProvider(textLabel)
    val sleep = ColorProvider(sleep)
    val heart = ColorProvider(heart)
    val activity = ColorProvider(activity)
    val oxygen = ColorProvider(oxygen)
    val stress = ColorProvider(stress)
    val onAccent = ColorProvider(onAccent)

    fun accent(metric: Metric): ColorProvider = when (metric) {
        Metric.READINESS -> textPrimary
        Metric.SLEEP -> sleep
        Metric.STEPS -> activity
        Metric.HEART_RATE -> heart
        Metric.SPO2 -> oxygen
        Metric.STRESS -> stress
        Metric.BATTERY -> textSecondary
    }

    companion object {
        fun of(theme: ThemeChoice): WidgetPalette = when (theme) {
            ThemeChoice.SYSTEM -> SYSTEM
            ThemeChoice.DARK -> DARK
            ThemeChoice.LIGHT -> LIGHT
        }

        private val SYSTEM = WidgetPalette(
            surface = R.color.widget_surface,
            track = R.color.widget_track,
            textPrimary = R.color.widget_text_primary,
            textSecondary = R.color.widget_text_secondary,
            textLabel = R.color.widget_text_label,
            sleep = R.color.widget_sleep,
            heart = R.color.widget_heart,
            activity = R.color.widget_activity,
            oxygen = R.color.widget_oxygen,
            stress = R.color.widget_stress,
            onAccent = R.color.widget_on_accent,
        )

        private val DARK = WidgetPalette(
            surface = R.color.widget_dark_surface,
            track = R.color.widget_dark_track,
            textPrimary = R.color.widget_dark_text_primary,
            textSecondary = R.color.widget_dark_text_secondary,
            textLabel = R.color.widget_dark_text_label,
            sleep = R.color.widget_dark_sleep,
            heart = R.color.widget_dark_heart,
            activity = R.color.widget_dark_activity,
            oxygen = R.color.widget_dark_oxygen,
            stress = R.color.widget_dark_stress,
            onAccent = R.color.widget_dark_on_accent,
        )

        private val LIGHT = WidgetPalette(
            surface = R.color.widget_light_surface,
            track = R.color.widget_light_track,
            textPrimary = R.color.widget_light_text_primary,
            textSecondary = R.color.widget_light_text_secondary,
            textLabel = R.color.widget_light_text_label,
            sleep = R.color.widget_light_sleep,
            heart = R.color.widget_light_heart,
            activity = R.color.widget_light_activity,
            oxygen = R.color.widget_light_oxygen,
            stress = R.color.widget_light_stress,
            onAccent = R.color.widget_light_on_accent,
        )
    }
}
