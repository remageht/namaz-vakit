package com.remageht.namazvakit

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.webkit.GeolocationPermissions
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import java.util.Locale

/** JS bridge for Arabic TTS via framework TextToSpeech. */
class TtsBridge(activity: Activity) {
    private var tts: TextToSpeech? = null
    private var pendingLang: String? = null

    init {
        tts = TextToSpeech(activity) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val lang = pendingLang
                if (lang != null) {
                    try {
                        tts?.language = parseLocale(lang)
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    @JavascriptInterface
    fun speak(text: String, lang: String) {
        try {
            val t = tts ?: return
            val locale = parseLocale(lang)
            try {
                t.language = locale
            } catch (_: Exception) {
                pendingLang = lang
            }
            t.speak(text, TextToSpeech.QUEUE_FLUSH, null, "namaz-tts")
        } catch (_: Exception) {
        }
    }

    fun shutdown() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
    }

    companion object {
        private fun parseLocale(lang: String): Locale {
            val clean = lang.trim().replace('_', '-')
            val parts = clean.split('-')
            return when {
                parts.size >= 3 -> Locale(parts[0], parts[1], parts[2])
                parts.size == 2 -> Locale(parts[0], parts[1])
                parts.size == 1 && parts[0].isNotEmpty() -> Locale(parts[0])
                else -> Locale("ar", "SA")
            }
        }
    }
}

/** JS bridge: keeps native widgets in sync with the PWA location. */
class HostBridge(private val activity: Activity) {
    @JavascriptInterface
    fun setLocation(lat: Double, lon: Double) {
        try {
            if (lat.isNaN() || lon.isNaN()) return
            if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return
            activity.getSharedPreferences("loc", Context.MODE_PRIVATE).edit()
                .putFloat("lat", lat.toFloat())
                .putFloat("lon", lon.toFloat())
                .apply()
            WidgetCommon.schedule(activity)
            WidgetCommon.updateAll(activity)
            PanelService.refresh(activity)
        } catch (_: Exception) {
        }
    }

    /** Включение/выключение плашки из настроек PWA. */
    @JavascriptInterface
    fun setPanel(on: Boolean) {
        try {
            if (on) PanelService.enable(activity) else PanelService.hide(activity)
        } catch (_: Exception) {
        }
    }

    /** Текущее состояние плашки для переключателя в PWA. */
    @JavascriptInterface
    fun getPanel(): Boolean = try {
        PanelService.isOn(activity)
    } catch (_: Exception) {
        false
    }
}

/** Fullscreen WebView entry: online PWA with offline asset fallback. */
class MainActivity : Activity() {
    private var webView: WebView? = null
    private var ttsBridge: TtsBridge? = null

    companion object {
        private const val ONLINE_URL = "https://remageht.github.io/namaz-vakit/"
        private const val OFFLINE_URL = "file:///android_asset/namaz/index.html"
        private const val ALLOWED_ORIGIN = "https://remageht.github.io"
        private const val REQ_CODE_NOTIF = 7
        private const val REQ_CODE_LOCATION = 8
        private const val REQ_CODE_CAMERA = 9
    }

    private var pendingGeoOrigin: String? = null
    private var pendingGeoCallback: GeolocationPermissions.Callback? = null
    private var pendingCameraRequest: PermissionRequest? = null

    private fun showLocationSettingsDialog() {
        val lang = Locale.getDefault().language
        val title = when (lang) {
            "tt" -> "Урнашуны билгеләү"
            "en" -> "Location Permission"
            else -> "Разрешение на геолокацию"
        }
        val msg = when (lang) {
            "tt" -> "Намаз вакытларын һәм Кыбла юнәлешен төгәл билгеләү өчен геолокация кирәк. Зинһар, көйләүләрдә рөхсәт итегез."
            "en" -> "Location access is needed to calculate accurate prayer times and Qibla direction. Please enable it in App Settings."
            else -> "Для точного расчёта времени намаза и направления Киблы приложению требуется доступ к геолокации. Пожалуйста, включите разрешение в настройках приложения."
        }
        val btnSettings = when (lang) {
            "tt" -> "Көйләүләр"
            "en" -> "Settings"
            else -> "Настройки"
        }
        val btnCancel = when (lang) {
            "tt" -> "Баш тарту"
            "en" -> "Cancel"
            else -> "Отмена"
        }

        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(msg)
            .setPositiveButton(btnSettings) { _, _ ->
                try {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", packageName, null)
                    }
                    startActivity(intent)
                } catch (_: Exception) {
                }
                pendingGeoCallback?.invoke(pendingGeoOrigin, false, false)
                pendingGeoCallback = null
                pendingGeoOrigin = null
            }
            .setNegativeButton(btnCancel) { _, _ ->
                pendingGeoCallback?.invoke(pendingGeoOrigin, false, false)
                pendingGeoCallback = null
                pendingGeoOrigin = null
            }
            .setOnCancelListener {
                pendingGeoCallback?.invoke(pendingGeoOrigin, false, false)
                pendingGeoCallback = null
                pendingGeoOrigin = null
            }
            .show()
    }

    override fun onCreate(s: Bundle?) {
        super.onCreate(s)

        ttsBridge = TtsBridge(this)

        val wv = WebView(this)
        webView = wv

        val st = wv.settings
        st.javaScriptEnabled = true
        st.domStorageEnabled = true
        st.mediaPlaybackRequiresUserGesture = false
        st.setGeolocationEnabled(true)
        st.allowFileAccess = true
        st.allowContentAccess = true
        try {
            st.allowUniversalAccessFromFileURLs = true
            st.allowFileAccessFromFileURLs = true
        } catch (_: Exception) {
        }
        // Suffix user agent so the PWA can detect the native shell.
        try {
            st.userAgentString = st.userAgentString + " NamazApp"
        } catch (_: Exception) {
        }

        val bridge = ttsBridge
        if (bridge != null) {
            wv.addJavascriptInterface(bridge, "NamazTts")
        }
        wv.addJavascriptInterface(HostBridge(this), "NamazHost")

        wv.webChromeClient = object : WebChromeClient() {
            override fun onGeolocationPermissionsShowPrompt(
                origin: String?,
                callback: GeolocationPermissions.Callback?
            ) {
                // App runs from bundled assets: allow file origin + our site.
                if (origin == null || (!origin.startsWith(ALLOWED_ORIGIN) && !origin.startsWith("file://"))) {
                    callback?.invoke(origin, false, false)
                    return
                }

                val hasFine = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                val hasCoarse = checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                if (hasFine || hasCoarse) {
                    callback?.invoke(origin, true, false)
                    return
                }

                pendingGeoOrigin = origin
                pendingGeoCallback = callback

                val prefs = getSharedPreferences("app_perms", Context.MODE_PRIVATE)
                val requestedBefore = prefs.getBoolean("geo_requested", false)
                val canShowRationale = shouldShowRequestPermissionRationale(android.Manifest.permission.ACCESS_FINE_LOCATION) ||
                        shouldShowRequestPermissionRationale(android.Manifest.permission.ACCESS_COARSE_LOCATION)

                if (requestedBefore && !canShowRationale) {
                    showLocationSettingsDialog()
                } else {
                    prefs.edit().putBoolean("geo_requested", true).apply()
                    requestPermissions(
                        arrayOf(
                            android.Manifest.permission.ACCESS_FINE_LOCATION,
                            android.Manifest.permission.ACCESS_COARSE_LOCATION
                        ),
                        REQ_CODE_LOCATION
                    )
                }
            }

            override fun onPermissionRequest(request: PermissionRequest?) {
                if (request == null) return
                val resources = request.resources ?: return
                if (resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) {
                    if (checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        request.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
                    } else {
                        pendingCameraRequest = request
                        requestPermissions(arrayOf(android.Manifest.permission.CAMERA), REQ_CODE_CAMERA)
                    }
                } else {
                    request.deny()
                }
            }
        }

        wv.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                return false
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                if (request == null || request.isForMainFrame) {
                    val failing = request?.url?.toString() ?: ONLINE_URL
                    if (!failing.startsWith("file:///android_asset")) {
                        view?.loadUrl(OFFLINE_URL)
                    }
                }
            }

            @Suppress("DEPRECATION")
            override fun onReceivedError(
                view: WebView?,
                errorCode: Int,
                description: String?,
                failingUrl: String?
            ) {
                val url = failingUrl ?: ONLINE_URL
                if (!url.startsWith("file:///android_asset")) {
                    view?.loadUrl(OFFLINE_URL)
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                try {
                    view?.evaluateJavascript(
                        "if(navigator.userAgent.indexOf('NamazApp')!==-1){window.speakArabic=(t)=>NamazTts.speak(t,'ar-SA');}",
                        null
                    )
                } catch (_: Exception) {
                }
            }
        }

        setContentView(wv)
        // Standalone app: bundled copy is primary, never redirect to web.
        wv.loadUrl(OFFLINE_URL)

        // Плашка намаза в шторке уведомлений: включена по умолчанию.
        if (PanelService.isOn(this) && Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), REQ_CODE_NOTIF)
        }
        PanelService.refresh(this)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQ_CODE_NOTIF -> {
                PanelService.refresh(this)
            }
            REQ_CODE_LOCATION -> {
                val granted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
                if (granted) {
                    pendingGeoCallback?.invoke(pendingGeoOrigin, true, false)
                } else {
                    pendingGeoCallback?.invoke(pendingGeoOrigin, false, false)
                }
                pendingGeoCallback = null
                pendingGeoOrigin = null
            }
            REQ_CODE_CAMERA -> {
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    pendingCameraRequest?.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
                } else {
                    pendingCameraRequest?.deny()
                }
                pendingCameraRequest = null
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        val wv = webView
        if (wv != null && wv.canGoBack()) {
            wv.goBack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onDestroy() {
        try {
            webView?.destroy()
        } catch (_: Exception) {
        }
        webView = null
        try {
            ttsBridge?.shutdown()
        } catch (_: Exception) {
        }
        ttsBridge = null
        super.onDestroy()
    }
}
