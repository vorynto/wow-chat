import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

/// Access to the device's real photo/video assets, so we can import originals into the vault
/// and then delete them.
///
/// Silent deletion (no per-file system dialog) requires "All files access"
/// (MANAGE_EXTERNAL_STORAGE) — a one-time grant the user enables in system settings. Android
/// provides no way for the app to grant it itself; without it, Android 11+ forces a
/// confirmation dialog on every delete.
class DeviceMediaService {
  /// Request read access to media (needed to list + import).
  Future<bool> ensureReadPermission() async {
    final ps = await PhotoManager.requestPermissionExtend();
    return ps.isAuth || ps.hasAccess;
  }

  Future<bool> hasAllFilesAccess() => Permission.manageExternalStorage.isGranted;

  /// Opens the system "All files access" screen for a one-time grant. Returns whether granted.
  Future<bool> requestAllFilesAccess() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  /// Most-recent device assets (images + videos).
  Future<List<AssetEntity>> recentAssets({int limit = 300}) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );
    if (paths.isEmpty) return [];
    return paths.first.getAssetListPaged(page: 0, size: limit);
  }

  /// Delete originals by asset id. With All-files access this is silent; otherwise the OS
  /// shows a confirmation dialog. Returns the ids actually deleted.
  Future<List<String>> deleteOriginals(List<String> ids) async {
    if (ids.isEmpty) return const [];
    return PhotoManager.editor.deleteWithIds(ids);
  }
}
