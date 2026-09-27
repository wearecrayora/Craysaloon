package com.crayora.craysalon

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The pinned home-screen shortcut (ARCHITECTURE 7.3).
 *
 * This is the Tier 1 answer to "the app should look like the salon's app" on
 * Android. It is NOT a launcher-icon swap: the launcher icon is compiled into
 * the APK and cannot be replaced at runtime. Android itself shows the
 * confirmation dialog, so nothing here can add an icon behind the customer's
 * back - `pin` returns whether the request was accepted, not whether an icon
 * exists.
 *
 * There is deliberately no iOS counterpart. iOS has no API for this at all, so
 * the Dart side reports unsupported and the app never offers it.
 */
class HomeShortcutChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "cray/home_shortcut"
        private const val SHORTCUT_ID = "cray_salon_home"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(ShortcutManagerCompat.isRequestPinShortcutSupported(context))

            "pin" -> {
                // Not every launcher supports pinning; check before offering,
                // so the UI can hide an offer it cannot honour.
                if (!ShortcutManagerCompat.isRequestPinShortcutSupported(context)) {
                    result.success(false)
                    return
                }

                val label = call.argument<String>("label")
                if (label.isNullOrBlank()) {
                    result.success(false)
                    return
                }

                val icon = call.argument<ByteArray>("logo")?.let { bytes ->
                    // An adaptive icon so launchers mask it to their own shape
                    // instead of drawing a square badge on a round grid.
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        ?.let { IconCompat.createWithAdaptiveBitmap(it) }
                } ?: IconCompat.createWithResource(context, R.mipmap.ic_launcher)

                val intent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                }

                val shortcut = ShortcutInfoCompat.Builder(context, SHORTCUT_ID)
                    .setShortLabel(label)
                    .setLongLabel(label)
                    .setIcon(icon)
                    .setIntent(intent)
                    .build()

                result.success(ShortcutManagerCompat.requestPinShortcut(context, shortcut, null))
            }

            else -> result.notImplemented()
        }
    }
}
