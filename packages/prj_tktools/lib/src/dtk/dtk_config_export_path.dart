/// Lazily resolved export path of a config db.
///
/// An explicit path is always used, and becomes the default of the later calls
/// without one; otherwise the default path ([getDefaultPath], from the global
/// prefs) is read once. [initBuilders] runs once, before the first use.
class DtkConfigExportPath {
  /// Read the default export path, null if not set.
  final Future<String?> Function() getDefaultPath;

  /// Error message when no export path is set.
  final String notSetMessage;

  /// Called once, before the first use.
  final void Function()? initBuilders;

  String? _path;
  var _buildersInitialized = false;

  /// Lazily resolved export path of a config db.
  DtkConfigExportPath({
    required this.getDefaultPath,
    required this.notSetMessage,
    this.initBuilders,
  });

  /// The export path, [configExportPath] if given.
  Future<String> get({String? configExportPath}) async {
    if (!_buildersInitialized) {
      _buildersInitialized = true;
      initBuilders?.call();
    }
    if (configExportPath != null) {
      return _path = configExportPath;
    }
    var path = _path ??= await getDefaultPath();
    if (path == null) {
      throw StateError(notSetMessage);
    }
    return path;
  }
}
