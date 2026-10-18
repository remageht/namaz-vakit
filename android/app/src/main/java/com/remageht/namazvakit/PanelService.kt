package com.remageht.namazvakit

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.widget.RemoteViews
import java.util.Calendar

/**
 * Плашка намаза в шторке уведомлений: постоянное уведомление с живым
 * Chronometer-счётчиком до следующего намаза (тикает без обновлений приложения),
 * названием намаза, временем и расписанием дня. Аналог плашки на десктопе.
 */
class PanelService : Service() {

    companion object {
        private const val ACTION_HIDE = "com.remageht.namazvakit.PANEL_HIDE"
        private const val CHANNEL_ID = "namaz_panel"
        private const val NOTIF_ID = 7
        private const val PREFS = "panel"
        private const val KEY_ON = "on"

        fun isOn(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ON, true)

        /** Включает плашку и поднимает сервис. */
        fun enable(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_ON, true).apply()
            startCompat(context)
        }

        /** Убирает плашку и останавливает сервис. */
        fun hide(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_ON, false).apply()
            try {
                context.stopService(Intent(context, PanelService::class.java))
            } catch (_: Exception) {
            }
        }

        /** Обновляет плашку, если она включена (после смены локации и т.п.). */
        fun refresh(context: Context) {
            if (isOn(context)) startCompat(context)
        }

        private fun startCompat(context: Context) {
            try {
                val i = Intent(context, PanelService::class.java)
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(i)
                } else {
                    context.startService(i)
                }
            } catch (_: Exception) {
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            update()
            handler.postDelayed(this, 30_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIF_ID, buildNotification())
        handler.post(ticker)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HIDE) {
            hide(this)
            return START_NOT_STICKY
        }
        update()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(ticker)
        super.onDestroy()
    }

    private fun createChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // DEFAULT + без звука/вибрации: значок видно в статус-баре у часов,
        // но уведомление не издаёт звуков.
        val ch = NotificationChannel(CHANNEL_ID, "Плашка намаза", NotificationManager.IMPORTANCE_DEFAULT)
        ch.description = "Время и обратный отсчёт до следующего намаза"
        ch.setShowBadge(false)
        ch.enableVibration(false)
        ch.setSound(null, null)
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(): Notification {
        val now = Calendar.getInstance()
        val lat = WidgetCommon.latOf(this)
        val lon = WidgetCommon.lonOf(this)
        val n = PrayTimes.next(lat, lon, now)
        val t = PrayTimes.calculate(lat, lon, now)

        val night = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
        val gold = if (night) 0xFFD4AF37.toInt() else 0xFF8A6D1A.toInt()
        val main = if (night) 0xFFFFFFFF.toInt() else 0xFF1F2430.toInt()
        val dim = if (night) 0xFF9CA3AF.toInt() else 0xFF6B7280.toInt()

        val v = RemoteViews(packageName, R.layout.panel_notification)
        v.setImageViewResource(R.id.panel_icon, R.mipmap.ic_launcher)
        v.setTextViewText(R.id.panel_title, "${n.name} · ${n.time}")
        v.setTextColor(R.id.panel_title, gold)
        v.setTextColor(R.id.panel_countdown, main)
        v.setChronometer(R.id.panel_countdown, SystemClock.elapsedRealtime() + n.inMs, "-%s", true)
        v.setChronometerCountDown(R.id.panel_countdown, true)
        v.setTextViewText(
            R.id.panel_schedule,
            "Фаджр ${t.fajr} · Зухр ${t.dhuhr} · Аср ${t.asr} · Магриб ${t.maghrib} · Иша ${t.isha}"
        )
        v.setTextColor(R.id.panel_schedule, dim)

        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val hidePi = PendingIntent.getService(
            this, 1,
            Intent(this, PanelService::class.java).setAction(ACTION_HIDE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val mins = (n.inMs / 60_000).toInt()
        val left = String.format("осталось %d ч %02d мин", mins / 60, mins % 60)

        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_namaz)
            .setContentTitle("Намаз · ${n.name} ${n.time}")
            .setContentText(left)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(false)
            .setCustomBigContentView(v)
            .addAction(0, "Убрать", hidePi)
            .build()
    }

    private fun update() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, buildNotification())
        } catch (_: Exception) {
        }
    }
}
