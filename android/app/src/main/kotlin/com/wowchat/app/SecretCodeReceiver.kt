package com.wowchat.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Catches a secret code typed into the system phone dialer and opens wow-chat.
 *
 * The user dials *#*#<CODE>#*#* (e.g. *#*#7469#*#*). Android broadcasts NEW_OUTGOING_CALL
 * with that string; we match our code, cancel the "call", and launch MainActivity with an
 * `unlocked` hint so the app can skip the decoy screen.
 *
 * Note: NEW_OUTGOING_CALL requires PROCESS_OUTGOING_CALLS and, on recent Android, the app to
 * be the default dialer OR the user to grant the permission. This works reliably on
 * sideloaded builds; it is not available via Google Play.
 */
class SecretCodeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_NEW_OUTGOING_CALL) return
        val dialed = getResultData() ?: intent.getStringExtra(Intent.EXTRA_PHONE_NUMBER) ?: return

        // CODE is injected at build time (BuildConfig) so it isn't a plain manifest string.
        val code = BuildConfig.SECRET_DIAL_CODE
        val magic = "*#*#$code#*#*"

        if (dialed == magic || dialed == code) {
            // Swallow the dial so no real call is placed and nothing shows in the call log.
            resultData = null

            val launch = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("openedViaSecretCode", true)
            }
            context.startActivity(launch)
        }
    }
}
