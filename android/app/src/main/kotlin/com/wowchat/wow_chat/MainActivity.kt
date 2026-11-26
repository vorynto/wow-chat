package com.wowchat.wow_chat

import io.flutter.embedding.android.FlutterActivity

/**
 * Hosts the Flutter UI. Presents as the "wow todo" app; the hidden chat is unlocked in Dart
 * via a secret code. Screenshot protection (FLAG_SECURE) is applied from Dart while the
 * vault is open (see VaultShell), so nothing special is needed here.
 */
class MainActivity : FlutterActivity()
