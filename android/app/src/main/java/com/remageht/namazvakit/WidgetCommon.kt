package com.remageht.namazvakit

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.SystemClock
import android.widget.RemoteViews
import java.util.Calendar

/** Shared state for 1x1 and 2x2 widgets + adhan chime at prayer start. */
object WidgetCommon {
    const val ACTION_TICK = "com.remageht.namazvakit.TICK"
    const val APP_URL = "https://remageht.github.io/namaz-vakit/"
    private const val DEF_LAT = 45.1342
    private const val DEF_LON = 33.60

    /** Coordinates synced from the app (GPS/city pick); Saki defaults otherwise. */
    fun latOf(context: Context): Double =
        context.getSharedPreferences("loc", Context.MODE_PRIVATE)
            .getFloat("lat", DEF_LAT.toFloat()).toDouble()

    fun lonOf(context: Context): Double =
        context.getSharedPreferences("loc", Context.MODE_PRIVATE)
            .getFloat("lon", DEF_LON.toFloat()).toDouble()

    private val PRAYERS = listOf("Fajr", "Dhuhr", "Asr", "Maghrib", "Isha")
    private val LABELS = listOf("Фаджр 🌅", "Зухр ☀️", "Аср 🌤", "Магриб 🌇", "Иша 🌙")

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

    fun cancelIfEmpty(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val a = mgr.getAppWidgetIds(ComponentName(context, NamazWidgetProvider::class.java))
        val b = mgr.getAppWidgetIds(ComponentName(context, NamazWidget2x2Provider::class.java))
        if (a.isEmpty() && b.isEmpty()) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(tickIntent(context))
        }
    }

    private fun openIntent(context: Context): PendingIntent {
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(APP_URL)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context, 0, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun updateAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val pi = openIntent(context)
        val now = Calendar.getInstance()
        val lat = latOf(context)
        val lon = lonOf(context)
        val n = PrayTimes.next(lat, lon, now)
        val totalMin = (n.inMs / 60000).toInt()
        val cd = String.format("%02d:%02d", totalMin / 60, totalMin % 60)

        val c1 = ComponentName(context, NamazWidgetProvider::class.java)
        for (id in mgr.getAppWidgetIds(c1)) {
            val v = RemoteViews(context.packageName, R.layout.widget_1x1)
            v.setOnClickPendingIntent(R.id.widget_root, pi)
            v.setTextViewText(R.id.widget_prayer_name, n.name)
            v.setTextViewText(R.id.widget_prayer_time, n.time)
            v.setTextViewText(R.id.widget_prayer_sub, "−$cd")
            mgr.updateAppWidget(id, v)
        }

        val c2 = ComponentName(context, NamazWidget2x2Provider::class.java)
        for (id in mgr.getAppWidgetIds(c2)) {
            val v = RemoteViews(context.packageName, R.layout.widget_2x2)
            v.setOnClickPendingIntent(R.id.widget2_root, pi)
            v.setTextViewText(R.id.widget2_header, "🕌 ${n.name} · −$cd")
            val t = PrayTimes.calculate(lat, lon, now)
            val times = listOf(t.fajr, t.dhuhr, t.asr, t.maghrib, t.isha)
            val nameIds = intArrayOf(
                R.id.w2_name_1, R.id.w2_name_2, R.id.w2_name_3,
                R.id.w2_name_4, R.id.w2_name_5
            )
            val timeIds = intArrayOf(
                R.id.w2_time_1, R.id.w2_time_2, R.id.w2_time_3,
                R.id.w2_time_4, R.id.w2_time_5
            )
            val nextKey = keyOf(n.name)
            for (i in 0 until 5) {
                val isNext = PRAYERS[i] == nextKey
                v.setTextViewText(nameIds[i], LABELS[i])
                v.setTextViewText(timeIds[i], times[i])
                v.setTextColor(nameIds[i], if (isNext) 0xFFD4AF37.toInt() else 0xFF86EFAC.toInt())
                v.setTextColor(timeIds[i], if (isNext) 0xFFD4AF37.toInt() else 0xFFFFFFFF.toInt())
            }
            mgr.updateAppWidget(id, v)
        }

        maybeAdhan(context, now)
    }

    private fun keyOf(prayerName: String): String =
        when {
            prayerName.contains("Фаджр") -> "Fajr"
            prayerName.contains("Зухр") -> "Dhuhr"
            prayerName.contains("Аср") -> "Asr"
            prayerName.contains("Магриб") -> "Maghrib"
            else -> "Isha"
        }

    /** Fires the bundled chime once within a minute of any prayer start. */
    private fun maybeAdhan(context: Context, now: Calendar) {
        try {
            val day = now.get(Calendar.DAY_OF_YEAR) * 1000 + now.get(Calendar.YEAR)
            val prefs = context.getSharedPreferences("adhan", Context.MODE_PRIVATE)
            val times = PrayTimes.calculate(latOf(context), lonOf(context), now)
            val list = listOf(
                "Fajr" to times.fajr, "Dhuhr" to times.dhuhr, "Asr" to times.asr,
                "Maghrib" to times.maghrib, "Isha" to times.isha
            )
            for ((key, hhmm) in list) {
                val (h, m) = hhmm.split(":").map { it.toInt() }
                val at = (now.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
                    set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                }
                val dt = now.timeInMillis - at.timeInMillis
                if (dt in 0..65_000) {
                    val firedKey = "$day$key"
                    if (prefs.getString("last", "") != firedKey) {
                        prefs.edit().putString("last", firedKey).apply()
                        playChime(context)
                    }
                    return
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun playChime(context: Context) {
        try {
            val mp = MediaPlayer.create(context, R.raw.adhan) ?: return
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            mp.setOnCompletionListener { it.release() }
            mp.start()
        } catch (_: Exception) {
        }
    }
}
