package com.crayora.craysalon

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
