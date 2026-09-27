package com.crayora.craysalon

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * One notification channel, named for the salon (ARCHITECTURE 7.4).
 *
 * The id is stable and the NAME is the salon's, so a customer who is later
 * transferred sees the new salon in Settings rather than two entries - Android
 * updates the name of an existing channel, and only the name, on re-creation.
 *
 * Importance is IMPORTANCE_DEFAULT, not HIGH: reminders are useful, not urgent,
 * and a salon does not get to buzz a phone for an offer.
 */
class SalonNotificationChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "cray/notifications"
        const val CHANNEL_ID = "cray_salon"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "ensureChannel") {
            result.notImplemented()
            return
        }

        // Channels exist from Android 8. Below that, notifications simply have
        // no channel and nothing here is needed.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(null)
            return
        }

        val name = call.argument<String>("name")
        if (name.isNullOrBlank()) {
            result.success(null)
            return
        }

        val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT)
        call.argument<Number>("accent")?.let {
            channel.enableLights(true)
            channel.lightColor = it.toInt()
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
        result.success(null)
    }
}
