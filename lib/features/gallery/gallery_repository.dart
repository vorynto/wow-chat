import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/crypto/e2e_service.dart';
import '../../core/storage/encrypted_db.dart';

class GalleryItem {
  GalleryItem({
    required this.id,
    required this.name,
    required this.type, // 'image' | 'video'
    required this.size,
    required this.createdAt,
    required this.path,
    required this.keymat,
  });
  final String id;
  final String name;
  final String type;
  final int size;
  final DateTime createdAt;
  final String path;
  final String keymat;

  bool get isVideo => type == 'video';

  factory GalleryItem.fromRow(Map<String, Object?> r) => GalleryItem(
        id: r['id'] as String,
        name: r['name'] as String,
        type: r['type'] as String,
        size: r['size'] as int? ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
        path: r['path'] as String,
        keymat: r['keymat'] as String,
      );
}

/// A local, encrypted hidden gallery. Imported photos/videos are encrypted client-side and
/// stored as ciphertext in app-private storage; keys live in the encrypted SQLCipher DB.
/// Nothing is uploaded anywhere. Decryption happens on demand, in memory for images.
class GalleryRepository {
  final Map<String, Uint8List> _memCache = {};

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};
  static const _videoExts = {'mp4', 'mov', 'mkv', 'webm', 'avi', '3gp', 'm4v'};

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/gallery');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _typeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (_videoExts.contains(ext)) return 'video';
    if (_imageExts.contains(ext)) return 'image';
    return 'image'; // default to image rendering
  }

  /// Import a file from disk: encrypt its bytes, store ciphertext + metadata.
  Future<void> importFile({required String sourcePath, required String name}) async {
    final bytes = await File(sourcePath).readAsBytes();
    final (cipher, keymat) = await E2EService.encryptMedia(bytes);

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final dir = await _dir();
    final outPath = '${dir.path}/$id.enc';
    await File(outPath).writeAsBytes(cipher, flush: true);

    final db = await EncryptedDb.instance();
    await db.insert('gallery_items', {
      'id': id,
      'path': outPath,
      'name': name,
      'type': _typeFor(name),
      'keymat': keymat,
      'size': bytes.length,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<GalleryItem>> list() async {
    final db = await EncryptedDb.instance();
    final rows = await db.query('gallery_items', orderBy: 'created_at DESC');
    return rows.map(GalleryItem.fromRow).toList();
  }

  /// Decrypt an item's bytes into memory (cached for the session).
  Future<Uint8List> bytes(GalleryItem item) async {
    final cached = _memCache[item.id];
    if (cached != null) return cached;
    final cipher = await File(item.path).readAsBytes();
    final plain = await E2EService.decryptMedia(cipher, item.keymat);
    final out = Uint8List.fromList(plain);
    _memCache[item.id] = out;
    return out;
  }

  /// Decrypt a video to a temporary file for playback; caller deletes it when done.
  Future<String> decryptToTemp(GalleryItem item) async {
    final tmp = await getTemporaryDirectory();
    final out = File('${tmp.path}/${item.id}_${item.name}');
    await out.writeAsBytes(await bytes(item), flush: true);
    return out.path;
  }

  Future<void> delete(GalleryItem item) async {
    final db = await EncryptedDb.instance();
    await db.delete('gallery_items', where: 'id = ?', whereArgs: [item.id]);
    _memCache.remove(item.id);
    try {
      await File(item.path).delete();
    } catch (_) {}
  }
}
