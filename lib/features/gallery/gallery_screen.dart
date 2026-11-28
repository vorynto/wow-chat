import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../core/providers.dart';
import 'device_media_picker.dart';
import 'device_media_service.dart';
import 'gallery_repository.dart';

/// The hidden gallery: a grid of encrypted photos/videos stored only inside the vault.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});
  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  List<GalleryItem> _items = [];
  bool _loading = true;
  bool _importing = false;

  GalleryRepository get _repo => ref.read(galleryRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repo.list();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  final _media = DeviceMediaService();

  Future<void> _import() async {
    if (!await _media.ensureReadPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Media permission is required to import.')),
        );
      }
      return;
    }
    final assets = await _media.recentAssets();
    if (!mounted) return;
    final selected = await Navigator.of(context).push<List<AssetEntity>>(
      MaterialPageRoute(builder: (_) => DeviceMediaPicker(assets: assets)),
    );
    if (selected == null || selected.isEmpty) return;

    setState(() => _importing = true);
    try {
      // One-time "All files access" so originals can be deleted with no per-photo dialog.
      final canDelete = await _media.requestAllFilesAccess();

      final importedIds = <String>[];
      for (final a in selected) {
        final bytes = await a.originBytes;
        if (bytes == null) continue;
        final title = await a.titleAsync;
        await _repo.importBytes(
          name: title.isEmpty ? '${a.id}.bin' : title,
          bytes: bytes,
          type: a.type == AssetType.video ? 'video' : 'image',
        );
        importedIds.add(a.id);
      }

      // Delete the originals from the device gallery.
      if (canDelete) {
        await _media.deleteOriginals(importedIds); // silent, no confirmation
      }

      await _load();
      if (mounted && !canDelete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Imported. Originals were kept — enable "All files access" in settings to '
              'delete them automatically.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmDelete(GalleryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from vault?'),
        content: Text('“${item.name}” will be permanently removed from the hidden gallery.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.delete(item);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gallery')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No hidden media yet. Tap + to import.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _Viewer(item: item, repo: _repo),
                      )),
                      onLongPress: () => _confirmDelete(item),
                      child: _Thumb(item: item, repo: _repo),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importing ? null : _import,
        child: _importing
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate),
      ),
    );
  }
}

/// Grid thumbnail: decrypts image bytes (downscaled) in memory; videos show a placeholder.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.repo});
  final GalleryItem item;
  final GalleryRepository repo;

  @override
  Widget build(BuildContext context) {
    if (item.isVideo) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(child: Icon(Icons.play_circle_outline, size: 36)),
      );
    }
    return FutureBuilder<Uint8List>(
      future: repo.bytes(item),
      builder: (_, snap) {
        if (!snap.hasData) return Container(color: Colors.grey.shade900);
        return Image.memory(snap.data!, fit: BoxFit.cover, cacheWidth: 300,
            gaplessPlayback: true);
      },
    );
  }
}

/// Full-screen viewer: zoomable image or in-app video player.
class _Viewer extends StatefulWidget {
  const _Viewer({required this.item, required this.repo});
  final GalleryItem item;
  final GalleryRepository repo;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  VideoPlayerController? _video;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    _tempPath = await widget.repo.decryptToTemp(widget.item);
    final c = VideoPlayerController.file(File(_tempPath!));
    await c.initialize();
    await c.setLooping(true);
    await c.play();
    if (mounted) setState(() => _video = c);
  }

  @override
  void dispose() {
    _video?.dispose();
    // Remove the decrypted temp file so plaintext doesn't linger.
    if (_tempPath != null) {
      try {
        File(_tempPath!).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.item.name)),
      body: Center(
        child: widget.item.isVideo
            ? (_video == null
                ? const CircularProgressIndicator()
                : AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!)))
            : FutureBuilder<Uint8List>(
                future: widget.repo.bytes(widget.item),
                builder: (_, snap) => snap.hasData
                    ? InteractiveViewer(child: Image.memory(snap.data!))
                    : const CircularProgressIndicator(),
              ),
      ),
    );
  }
}
