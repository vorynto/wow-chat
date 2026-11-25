package com.wowchat.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Opens the (iconless) wow-chat app when the user enters the secret code in the phone dialer.
 *
 * Two mechanisms are handled for the widest device coverage:
 *
 *  1. SECRET_CODE — the user dials *#*#<CODE>#*#*. Android broadcasts
 *     android.provider.Telephony.SECRET_CODE with data android_secret_code://<CODE>.
 *     Reliable on Android <= 8; on Android 9+ this is a system-only broadcast and a
 *     sideloaded app will NOT receive it.
 *
 *  2. NEW_OUTGOING_CALL — the user types <CODE> as a number and presses call. We match it,
 *     cancel the call, and open the app. Deprecated on Android 10+ and needs the restricted
 *     PROCESS_OUTGOING_CALLS permission; reliability varies by OEM/version.
 *
 * For robust entry on modern Android, make wow-chat the default dialer (see docs/STEALTH.md).
 */
class SecretCodeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val code = BuildConfig.SECRET_DIAL_CODE
        when (intent.action) {
            "android.provider.Telephony.SECRET_CODE" -> {
                // Data looks like android_secret_code://7469
                if (intent.data?.host == code) openApp(context)
            }
            Intent.ACTION_NEW_OUTGOING_CALL -> {
                val dialed = resultData
                    ?: intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER)
                    ?: return
                if (dialed == code || dialed == "*#*#$code#*#*") {
                    resultData = null // swallow the dial: no call placed, nothing in the call log
                    openApp(context)
                }
            }
        }
    }

    private fun openApp(context: Context) {
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("openedViaSecretCode", true)
        }
        context.startActivity(launch)
    }
}
