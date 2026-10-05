package com.remageht.namazvakit

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import java.util.Calendar

/**
 * 1x1 Compact Android Home Screen Widget for Namaz Vakit.
 * Displays the upcoming prayer and countdown time.
 * Clicking the widget opens the Namaz PWA / TWA application.
 */
class NamazWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val APP_URL = "https://remageht.github.io/namaz-vakit/"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_1x1)

            // Intent to open Namaz Vakit PWA / TWA on tap
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(APP_URL)).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            // Current mock/cached default prayer calculation display
            val cal = Calendar.getInstance()
            val hour = cal.get(Calendar.HOUR_OF_DAY)
            val (name, time) = when {
                hour < 5 -> Pair("Фаджр 🌅", "05:10")
                hour < 12 -> Pair("Зухр ☀️", "12:30")
                hour < 16 -> Pair("Аср 🌤", "16:05")
                hour < 18 -> Pair("Магриб 🌇", "18:15")
                hour < 20 -> Pair("Иша 🌙", "19:50")
                else -> Pair("Фаджр 🌅", "05:10")
            }

            views.setTextViewText(R.id.widget_prayer_name, name)
            views.setTextViewText(R.id.widget_prayer_time, time)
            views.setTextViewText(R.id.widget_prayer_sub, "следующий")

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
