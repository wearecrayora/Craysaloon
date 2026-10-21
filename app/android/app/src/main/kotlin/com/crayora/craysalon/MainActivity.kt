package com.crayora.craysalon

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var smsConsent: SmsConsentChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Android-only, by necessity: the pinned shortcut has no iOS
        // counterpart (ARCHITECTURE 7.3). The Dart side is written against an
        // interface, so iOS simply reports it unsupported.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HomeShortcutChannel.CHANNEL)
            .setMethodCallHandler(HomeShortcutChannel(applicationContext))

        // The salon's notification channel (ARCHITECTURE 7.4). iOS has no
        // channels, so the Dart side no-ops there.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SalonNotificationChannel.CHANNEL)
            .setMethodCallHandler(SalonNotificationChannel(applicationContext))

        // The one-time code, read from the SMS only after Android asks the
        // customer and they allow it (SMS User Consent API). iOS fills the code
        // from the keyboard instead, so the Dart side asks nothing there.
        val consent = SmsConsentChannel(this)
        smsConsent = consent
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SmsConsentChannel.CHANNEL)
            .setMethodCallHandler(consent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (smsConsent?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
