import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

class GiphyGif {
  const GiphyGif({required this.previewUrl, required this.fullUrl});
  final String previewUrl;
  final String fullUrl;
}

/// Giphy GIF search. The chosen GIF is downloaded here and then sent as encrypted media, so
/// recipients get the actual bytes end-to-end (no third-party link in the chat). The search
/// query itself is sent to Giphy — a metadata leak the user should be aware of.
class GiphyService {
  static const _base = 'https://api.giphy.com/v1/gifs';
  String get _key => AppConfig.giphyApiKey;
  bool get enabled => _key.isNotEmpty;

  Future<List<GiphyGif>> search(String query) async {
    if (!enabled) return [];
    final uri = query.trim().isEmpty
        ? Uri.parse('$_base/trending?api_key=$_key&limit=24&rating=pg')
        : Uri.parse('$_base/search?api_key=$_key&q=${Uri.encodeQueryComponent(query)}&limit=24&rating=pg');
    final res = await http.get(uri);
    if (res.statusCode != 200) return [];
    final data = (jsonDecode(res.body)['data'] as List?) ?? [];
    return data.map((g) {
      final images = g['images'] as Map<String, dynamic>;
      final preview = (images['fixed_width'] ?? images['downsized']) as Map<String, dynamic>;
      final full = (images['downsized'] ?? images['original']) as Map<String, dynamic>;
      return GiphyGif(previewUrl: preview['url'] as String, fullUrl: full['url'] as String);
    }).toList();
  }

  Future<Uint8List> download(String url) async {
    final res = await http.get(Uri.parse(url));
    return res.bodyBytes;
  }
}
