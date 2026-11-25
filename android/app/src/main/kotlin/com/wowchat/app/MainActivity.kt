package com.wowchat.app

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and exposes the native stealth bridge:
 *  - openedViaSecretCode: was the activity launched by the dial-code receiver?
 *  - setDisguise: toggle the decoy vs real launcher icon at runtime.
 *
 * FLAG_SECURE (block screenshots / hide from recents) is applied from Dart via
 * flutter_windowmanager_plus so it can follow the user's privacy setting.
 */
class MainActivity : FlutterActivity() {
    private val channel = "wowchat/stealth"
    private var openedViaSecretCode = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openedViaSecretCode = intent?.getBooleanExtra("openedViaSecretCode", false) ?: false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "openedViaSecretCode" -> result.success(openedViaSecretCode)
                "setDisguise" -> {
                    val decoy = call.argument<Boolean>("decoy") ?: true
                    setDisguise(decoy)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Enable the decoy (Calculator) launcher or the real one; only one is active at a time. */
    private fun setDisguise(decoy: Boolean) {
        val pm = packageManager
        val decoyComp = ComponentName(this, "com.wowchat.app.DecoyLauncher")
        val realComp = ComponentName(this, "com.wowchat.app.RealLauncher")
        pm.setComponentEnabledSetting(
            decoyComp,
            if (decoy) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        pm.setComponentEnabledSetting(
            realComp,
            if (decoy) PackageManager.COMPONENT_ENABLED_STATE_DISABLED else PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
