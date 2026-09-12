import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the per-OS application data directories used by both Studio and
/// the runtime Menu.
///
/// Windows : %APPDATA%\MacroWheel\
/// macOS   : ~/Library/Application Support/MacroWheel/
/// Linux   : $XDG_CONFIG_HOME/macrowheel/  (defaults to ~/.config/macrowheel)
class AppPaths {
  AppPaths._();

  static const String appFolderName = 'MacroWheel';

  static Future<Directory> _baseDir() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw StateError('APPDATA environment variable is not set.');
      }
      return Directory(p.join(appData, appFolderName));
    }
    if (Platform.isMacOS) {
      return Directory(
        p.join(
          Platform.environment['HOME'] ?? '',
          'Library',
          'Application Support',
          appFolderName,
        ),
      );
    }
    // Linux / other unix.
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final home = Platform.environment['HOME'] ?? '';
    final root = (xdg != null && xdg.isNotEmpty) ? xdg : p.join(home, '.config');
    return Directory(p.join(root, appFolderName.toLowerCase()));
  }

  /// Directory containing `configuration.json` and the fixed `scripts/` folder.
  static Future<Directory> baseDir() async {
    final dir = await _baseDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Shared configuration file consumed by the Menu.
  static Future<File> configurationFile() async =>
      File(p.join((await baseDir()).path, 'configuration.json'));

  /// Fixed, application-owned user script folder. Users may drop `.py` files
  /// in here; Studio renames and deletes them, but never edits their contents.
  static Future<Directory> scriptsDir() async {
    final dir = Directory(p.join((await baseDir()).path, 'scripts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Studio-local state (window geometry, last-used paths, undo history
  /// checkpoints). Deliberately separate from `configuration.json`.
  static Future<File> studioStateFile() async {
    final support = await getApplicationSupportDirectory();
    if (!await support.exists()) {
      await support.create(recursive: true);
    }
    return File(p.join(support.path, 'studio_state.json'));
  }
}