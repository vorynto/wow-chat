import 'package:flutter/material.dart';
import 'giphy_service.dart';

/// Search Giphy and return the chosen GIF's URL (the caller downloads + sends it encrypted).
class GifPickerScreen extends StatefulWidget {
  const GifPickerScreen({super.key});
  @override
  State<GifPickerScreen> createState() => _GifPickerScreenState();
}

class _GifPickerScreenState extends State<GifPickerScreen> {
  final _svc = GiphyService();
  final _query = TextEditingController();
  List<GiphyGif> _gifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    final gifs = await _svc.search(q);
    if (mounted) setState(() { _gifs = gifs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_svc.enabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('GIFs')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('GIF search is disabled. Build with --dart-define=GIPHY_API_KEY=... to enable it.',
                textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _run,
          decoration: const InputDecoration(hintText: 'Search GIFs', border: InputBorder.none),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 4, crossAxisSpacing: 4),
              itemCount: _gifs.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => Navigator.of(context).pop(_gifs[i].fullUrl),
                child: Image.network(_gifs[i].previewUrl, fit: BoxFit.cover),
              ),
            ),
    );
  }
}
