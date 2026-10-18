package com.remageht.namazvakit

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent

/**
 * 1x1 home-screen widget: next prayer + countdown, offline calculation.
 * Tap opens the Namaz app. Ticks every minute via AlarmManager.
 */
class NamazWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        WidgetCommon.schedule(context)
        WidgetCommon.updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetCommon.ACTION_TICK, AppWidgetManager.ACTION_APPWIDGET_UPDATE ->
                WidgetCommon.updateAll(context)
            Intent.ACTION_BOOT_COMPLETED -> {
                WidgetCommon.schedule(context)
                WidgetCommon.updateAll(context)
                PanelService.refresh(context)
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        WidgetCommon.cancelIfEmpty(context)
    }

    override fun onDisabled(context: Context) {
        WidgetCommon.cancelIfEmpty(context)
    }
}
