import 'dart:convert';
import 'dart:typed_data';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:cryptography/cryptography.dart';

/// End-to-end message + media encryption.
///
/// Text messages use the Signal Double Ratchet (via libsignal). Large media is encrypted
/// with a random symmetric key (XChaCha20-Poly1305); that key travels inside the ratcheted
/// message, and only the ciphertext blob goes to Supabase Storage.
///
/// The Signal protocol stores (identity/prekey/session/sender-key) should be backed by
/// SQLCipher in production. In-memory stores are shown here for the skeleton; replace with
/// persistent implementations before shipping so sessions survive restarts.
class E2EService {
  E2EService(this._stores);
  final SignalProtocolStore _stores;

  /// Establish a session with a recipient using their published prekey bundle.
  Future<void> startSession({
    required SignalProtocolAddress remote,
    required PreKeyBundle bundle,
  }) async {
    final builder = SessionBuilder.fromSignalStore(_stores, remote);
    await builder.processPreKeyBundle(bundle);
  }

  /// Encrypt plaintext for a recipient. Returns a base64 envelope to store in messages.body_enc.
  Future<String> encryptText(SignalProtocolAddress remote, String plaintext) async {
    final cipher = SessionCipher.fromStore(_stores, remote);
    final msg = await cipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    return jsonEncode({'t': msg.getType(), 'b': base64.encode(msg.serialize())});
  }

  /// Decrypt an envelope from messages.body_enc.
  Future<String> decryptText(SignalProtocolAddress remote, String envelope) async {
    final j = jsonDecode(envelope) as Map<String, dynamic>;
    final type = j['t'] as int;
    final bytes = base64.decode(j['b'] as String);
    final cipher = SessionCipher.fromStore(_stores, remote);
    final Uint8List plain;
    if (type == CiphertextMessage.prekeyType) {
      plain = await cipher.decrypt(PreKeySignalMessage(bytes));
    } else {
      plain = await cipher.decryptFromSignal(SignalMessage.fromSerialized(bytes));
    }
    return utf8.decode(plain);
  }

  // ───────────────────── media encryption ─────────────────────
  static final _aead = Xchacha20.poly1305Aead();

  /// Encrypts [data] with a fresh key. Returns (ciphertext, keyMaterial). Upload the
  /// ciphertext to Storage; send keyMaterial (base64 key+nonce+mac) inside the E2E message.
  static Future<(List<int> ciphertext, String keyMaterial)> encryptMedia(List<int> data) async {
    final key = await _aead.newSecretKey();
    final box = await _aead.encrypt(data, secretKey: key);
    final keyBytes = await key.extractBytes();
    final material = jsonEncode({
      'k': base64.encode(keyBytes),
      'n': base64.encode(box.nonce),
      'm': base64.encode(box.mac.bytes),
    });
    return (box.cipherText, material);
  }

  /// Reverse of [encryptMedia].
  static Future<List<int>> decryptMedia(List<int> ciphertext, String keyMaterial) async {
    final j = jsonDecode(keyMaterial) as Map<String, dynamic>;
    final box = SecretBox(
      ciphertext,
      nonce: base64.decode(j['n'] as String),
      mac: Mac(base64.decode(j['m'] as String)),
    );
    final key = SecretKey(base64.decode(j['k'] as String));
    return _aead.decrypt(box, secretKey: key);
  }
}
