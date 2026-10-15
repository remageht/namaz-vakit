package com.remageht.namazvakit

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.webkit.GeolocationPermissions
import android.webkit.JavascriptInterface
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
        } catch (_: Exception) {
        }
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
                if (origin != null && (origin.startsWith(ALLOWED_ORIGIN) || origin.startsWith("file://"))) {
                    callback?.invoke(origin, true, false)
                } else {
                    callback?.invoke(origin, false, false)
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
