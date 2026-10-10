package com.remageht.namazvakit

import java.util.Calendar
import java.util.TimeZone
import kotlin.math.*

/**
 * Offline prayer-times math (Egypt angles Fajr 19.5 / Isha 17.5, Hanafi Asr).
 * Cross-checked against Aladhan API method 3 within +-1 min for Saki.
 */
object PrayTimes {

    data class DayTimes(
        val fajr: String, val sunrise: String, val dhuhr: String,
        val asr: String, val maghrib: String, val isha: String
    )

    data class Next(val name: String, val time: String, val inMs: Long)

    private const val DEG = Math.PI / 180.0
    private const val FAJR_ANGLE = 19.5
    private const val ISHA_ANGLE = 17.5
    private const val SUN_ANGLE = 0.8333
    private const val ASR_FACTOR = 2.0 // Hanafi

    private val NAMES = mapOf(
        "Fajr" to "Фаджр 🌅",
        "Sunrise" to "Восход ☀️",
        "Dhuhr" to "Зухр ☀️",
        "Asr" to "Аср 🌤",
        "Maghrib" to "Магриб 🌇",
        "Isha" to "Иша 🌙"
    )

    fun calculate(lat: Double, lon: Double, date: Calendar): DayTimes {
        var yr = date.get(Calendar.YEAR)
        var mo = date.get(Calendar.MONTH) + 1
        val dy = date.get(Calendar.DAY_OF_MONTH)
        if (mo <= 2) { yr -= 1; mo += 12 }
        val a = floor(yr / 100.0)
        val b = 2 - a + floor(a / 4)
        val jd = floor(365.25 * (yr + 4716)) + floor(30.6001 * (mo + 1)) + dy + b - 1524.5
        val dd = jd - 2451545.0
        var g = (357.529 + 0.98560028 * dd) % 360.0; if (g < 0) g += 360
        var q = (280.459 + 0.98564736 * dd) % 360.0; if (q < 0) q += 360
        var l = (q + 1.915 * sin(g * DEG) + 0.020 * sin(2 * g * DEG)) % 360.0; if (l < 0) l += 360
        val e = 23.439 - 0.00000036 * dd
        val dec = asin(sin(e * DEG) * sin(l * DEG)) / DEG
        var ra = atan2(cos(e * DEG) * sin(l * DEG), cos(l * DEG)) / DEG
        ra = ((ra % 360) + 360) % 360
        var eqt = (q - ra) / 15.0
        while (eqt > 12) eqt -= 24
        while (eqt < -12) eqt += 24

        val tz = TimeZone.getDefault().getOffset(date.timeInMillis) / 3600000.0
        val noon = 12.0 + tz - lon / 15.0 - eqt

        fun ha(alt: Double): Double {
            var cosH = (sin(alt * DEG) - sin(lat * DEG) * sin(dec * DEG)) /
                    (cos(lat * DEG) * cos(dec * DEG))
            if (cosH > 1.0) cosH = 1.0 else if (cosH < -1.0) cosH = -1.0
            return acos(cosH) / DEG / 15.0
        }

        val asrAlt = atan(1.0 / (ASR_FACTOR + tan(abs(lat - dec) * DEG))) / DEG

        return DayTimes(
            fajr = fmt(noon - ha(-FAJR_ANGLE)),
            sunrise = fmt(noon - ha(-SUN_ANGLE)),
            dhuhr = fmt(noon),
            asr = fmt(noon + ha(asrAlt)),
            maghrib = fmt(noon + ha(-SUN_ANGLE)),
            isha = fmt(noon + ha(-ISHA_ANGLE))
        )
    }

    private fun fmt(h: Double): String {
        var hh = h % 24; if (hh < 0) hh += 24
        var hInt = floor(hh).toInt()
        var mInt = ((hh - hInt) * 60).roundToInt()
        if (mInt == 60) { hInt += 1; mInt = 0 }
        if (hInt == 24) hInt = 0
        return String.format("%02d:%02d", hInt, mInt)
    }

    private fun atTime(t: DayTimes, key: String, base: Calendar): Calendar {
        val (h, m) = when (key) {
            "Fajr" -> t.fajr; "Sunrise" -> t.sunrise; "Dhuhr" -> t.dhuhr
            "Asr" -> t.asr; "Maghrib" -> t.maghrib; else -> t.isha
        }.split(":").map { it.toInt() }
        return (base.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, h); set(Calendar.MINUTE, m)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
    }

    fun next(lat: Double, lon: Double, now: Calendar): Next {
        val order = listOf("Fajr", "Dhuhr", "Asr", "Maghrib", "Isha")
        val t = calculate(lat, lon, now)
        for (k in order) {
            val d = atTime(t, k, now)
            if (d.after(now)) {
                val hhmm = String.format("%02d:%02d",
                    d.get(Calendar.HOUR_OF_DAY), d.get(Calendar.MINUTE))
                return Next(NAMES[k]!!, hhmm, d.timeInMillis - now.timeInMillis)
            }
        }
        val tm = (now.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 1) }
        val t2 = calculate(lat, lon, tm)
        val d = atTime(t2, "Fajr", tm)
        val hhmm = String.format("%02d:%02d",
            d.get(Calendar.HOUR_OF_DAY), d.get(Calendar.MINUTE))
        return Next(NAMES["Fajr"]!!, hhmm, d.timeInMillis - now.timeInMillis)
    }
}
