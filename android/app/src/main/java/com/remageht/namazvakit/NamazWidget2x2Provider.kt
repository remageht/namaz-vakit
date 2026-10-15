package com.remageht.namazvakit

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent

/**
 * 2x2 home-screen widget: full day schedule (5 prayers) with the next one
 * highlighted. Shares the minute tick and adhan chime with the 1x1 widget.
 */
class NamazWidget2x2Provider : AppWidgetProvider() {

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
