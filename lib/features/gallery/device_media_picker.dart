import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// A minimal multi-select grid over the device's photos/videos. Returns the chosen assets.
class DeviceMediaPicker extends StatefulWidget {
  const DeviceMediaPicker({super.key, required this.assets});
  final List<AssetEntity> assets;

  @override
  State<DeviceMediaPicker> createState() => _DeviceMediaPickerState();
}

class _DeviceMediaPickerState extends State<DeviceMediaPicker> {
  final _selected = <AssetEntity>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? 'Select media' : '${_selected.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
          ),
        ],
      ),
      body: widget.assets.isEmpty
          ? const Center(child: Text('No media found on this device.'))
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
              itemCount: widget.assets.length,
              itemBuilder: (_, i) {
                final asset = widget.assets[i];
                final isSel = _selected.contains(asset);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isSel) {
                      _selected.remove(asset);
                    } else {
                      _selected.add(asset);
                    }
                  }),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<Uint8List?>(
                        future: asset.thumbnailDataWithSize(const ThumbnailSize.square(200)),
                        builder: (_, snap) => snap.data == null
                            ? Container(color: Colors.grey.shade900)
                            : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
                      ),
                      if (asset.type == AssetType.video)
                        const Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.videocam, size: 18, color: Colors.white),
                          ),
                        ),
                      if (isSel)
                        Container(
                          color: Colors.teal.withValues(alpha: 0.4),
                          child: const Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.check_circle, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
