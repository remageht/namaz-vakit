package com.remageht.namazvakit

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/** Launcher entry: opens the Namaz PWA and closes. */
class MainActivity : Activity() {
    override fun onCreate(s: Bundle?) {
        super.onCreate(s)
        startActivity(Intent(Intent.ACTION_VIEW,
            Uri.parse("https://remageht.github.io/namaz-vakit/")))
        finish()
    }
}
