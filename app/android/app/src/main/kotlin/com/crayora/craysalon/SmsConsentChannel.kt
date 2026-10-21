package com.crayora.craysalon

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reading the one-time code from the SMS - WITH the customer's permission,
 * one message at a time (Google's SMS User Consent API).
 *
 * Why this API and not the others:
 *  - READ_SMS / RECEIVE_SMS: Google Play allows them only to the phone's
 *    default SMS app. An app that asks for them is rejected at review.
 *  - The SMS Retriever API reads silently, but only a message that ends with
 *    this app's hash - and the OTP message is Message Central's own template,
 *    which we cannot change (RULES 16).
 *  - User Consent works with any sender's text: when the next SMS arrives,
 *    Android itself asks "Allow Cray Salon to read this message?", showing
 *    the message. Nothing is read unless the customer taps Allow, and no
 *    permission is held afterwards.
 *
 * Listens for one message for up to five minutes (the API's own limit), then
 * stops. Returns the message text, or null if the customer declined, it timed
 * out, or Play services is missing - the code is then typed, as before.
 */
class SmsConsentChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "cray/sms_consent"
        const val REQUEST_CODE = 4721
        private const val GMS = "com.google.android.gms"
    }

    private var pending: MethodChannel.Result? = null
    private var receiver: BroadcastReceiver? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listen" -> listen(result)
            "cancel" -> {
                finish(null)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun listen(result: MethodChannel.Result) {
        // One listener at a time: a second request answers the first with null.
        finish(null)
        pending = result
        try {
            SmsRetriever.getClient(activity).startSmsUserConsent(null)
        } catch (e: Exception) {
            finish(null)
            return
        }
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
                val extras = intent.extras ?: return finish(null)
                @Suppress("DEPRECATION")
                val status = extras.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return finish(null)
                if (status.statusCode != CommonStatusCodes.SUCCESS) return finish(null)
                @Suppress("DEPRECATION")
                val consent = extras.getParcelable<Intent>(SmsRetriever.EXTRA_CONSENT_INTENT)
                    ?: return finish(null)
                // Launch only Google's own consent screen, and grant it nothing:
                // an intent handed to us in a broadcast is not trusted blindly
                // (Play's "intent redirection" check).
                val target = consent.resolveActivity(activity.packageManager)
                if (target == null || target.packageName != GMS) return finish(null)
                consent.flags = consent.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION).inv()
                try {
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(consent, REQUEST_CODE)
                } catch (e: Exception) {
                    finish(null)
                }
            }
        }
        receiver = r
        ContextCompat.registerReceiver(
            activity,
            r,
            IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION),
            SmsRetriever.SEND_PERMISSION,
            null,
            ContextCompat.RECEIVER_EXPORTED,
        )
    }

    /** From MainActivity: the customer answered Android's prompt. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val message = if (resultCode == Activity.RESULT_OK) {
            data?.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE)
        } else {
            null
        }
        finish(message)
        return true
    }

    private fun finish(message: String?) {
        receiver?.let {
            try {
                activity.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already gone.
            }
        }
        receiver = null
        pending?.success(message)
        pending = null
    }
}
