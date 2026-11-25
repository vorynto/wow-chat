package com.wowchat.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI. The app has no launcher icon; this activity is started by
 * SecretCodeReceiver (dial code) or, in dev builds, the DevLauncher alias / adb.
 *
 * Exposes one native hook: whether we were opened via the secret code. FLAG_SECURE
 * (block screenshots / hide from recents) is applied from Dart so it can follow the
 * user's privacy setting.
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
                else -> result.notImplemented()
            }
        }
    }
}
