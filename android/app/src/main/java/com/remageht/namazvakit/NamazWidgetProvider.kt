package com.remageht.namazvakit

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.widget.RemoteViews
import java.util.Calendar

/**
 * 1x1 home-screen widget: next prayer + countdown, offline calculation.
 * Tap opens the Namaz PWA. Ticks every minute via AlarmManager.
 */
class NamazWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        schedule(context)
        for (id in appWidgetIds) updateOne(context, appWidgetManager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TICK, AppWidgetManager.ACTION_APPWIDGET_UPDATE -> updateAll(context)
            Intent.ACTION_BOOT_COMPLETED -> {
                schedule(context)
                updateAll(context)
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        cancel(context)
    }

    override fun onDisabled(context: Context) {
        cancel(context)
    }

    companion object {
        const val ACTION_TICK = "com.remageht.namazvakit.TICK"
        private const val APP_URL = "https://remageht.github.io/namaz-vakit/"
        private const val LAT = 45.1342
        private const val LON = 33.60

        private fun tickIntent(context: Context): PendingIntent {
            val i = Intent(context, NamazWidgetProvider::class.java).apply {
                action = ACTION_TICK
            }
            return PendingIntent.getBroadcast(
                context, 0, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        fun schedule(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + 60_000,
                60_000,
                tickIntent(context)
            )
        }

        fun cancel(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(tickIntent(context))
        }

        fun updateAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val cn = ComponentName(context, NamazWidgetProvider::class.java)
            for (id in mgr.getAppWidgetIds(cn)) updateOne(context, mgr, id)
        }

        fun updateOne(
            context: Context,
            mgr: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_1x1)

            val open = Intent(Intent.ACTION_VIEW, Uri.parse(APP_URL)).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pi = PendingIntent.getActivity(
                context, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pi)

            val now = Calendar.getInstance()
            val n = PrayTimes.next(LAT, LON, now)
            val totalMin = (n.inMs / 60000).toInt()
            val cd = String.format("%02d:%02d", totalMin / 60, totalMin % 60)

            views.setTextViewText(R.id.widget_prayer_name, n.name)
            views.setTextViewText(R.id.widget_prayer_time, n.time)
            views.setTextViewText(R.id.widget_prayer_sub, "−$cd")

            mgr.updateAppWidget(appWidgetId, views)
        }
    }
}
