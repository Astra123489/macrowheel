import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Marker written into a user script so its identity survives renames.
/// The filename is only the display name; the ID is the identity
/// (spec section 13.1.3).
const String kScriptIdMarker = '# MacroWheel ID:';

/// One discovered user script.
class DiscoveredScript {
  const DiscoveredScript({
    required this.id,
    required this.file,
    required this.displayName,
  });

  /// Stable UUID read from, or written into, the script header.
  final String id;

  final File file;

  /// Filename without the `.py` extension.
  final String displayName;

  String get path => file.path;
}

/// Filesystem-based discovery of user scripts in the fixed Scripts folder
/// (spec section 13.1.4). There is no import or registration step: any `.py`
/// file placed directly in the folder is a Macro Wheel user script.
///
/// Studio generates a Script ID when a discovered file does not already have
/// one, and regenerates it for a duplicate so every script keeps a unique
/// identity (spec section 13.1.10).
class ScriptDiscovery {
  ScriptDiscovery(this.scriptsDir, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Directory scriptsDir;
  final Uuid _uuid;
  final _controller = StreamController<List<DiscoveredScript>>.broadcast();
  StreamSubscription<FileSystemEvent>? _watchSub;
  Timer? _debounce;

  /// Emits the full script list whenever the folder changes.
  Stream<List<DiscoveredScript>> get changes => _controller.stream;

  /// Scans the folder, assigning IDs where required, and returns the result.
  Future<List<DiscoveredScript>> scan() async {
    if (!await scriptsDir.exists()) {
      await scriptsDir.create(recursive: true);
    }

    final entries = await scriptsDir
        .list()
        .where((e) => e is File && p.extension(e.path).toLowerCase() == '.py')
        .cast<File>()
        .toList();

    final result = <DiscoveredScript>[];
    final seenIds = <String>{};

    for (final file in entries) {
      String id = await _readId(file) ?? '';

      if (id.isEmpty) {
        id = _uuid.v4();
        await _writeId(file, id);
      } else if (seenIds.contains(id)) {
        // A copied script carries the source's ID. Give the copy a fresh one
        // so both files remain distinct; the original is untouched.
        id = _uuid.v4();
        await _writeId(file, id);
      }

      seenIds.add(id);
      result.add(DiscoveredScript(
        id: id,
        file: file,
        displayName: p.basenameWithoutExtension(file.path),
      ));
    }

    result.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return result;
  }

  /// Starts watching the folder and pushes updates through [changes].
  void startWatching() {
    _watchSub ??= scriptsDir.watch(events: FileSystemEvent.all).listen((_) {
      // Coalesce bursts of filesystem events into a single rescan.
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () async {
        _controller.add(await scan());
      });
    });
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    await _watchSub?.cancel();
    _watchSub = null;
    await _controller.close();
  }

  /// Renames the underlying `.py` file. The Script ID is preserved, so every
  /// wheel assignment keeps referencing the same script (spec 13.1.7).
  Future<DiscoveredScript> rename(
    DiscoveredScript script,
    String newDisplayName,
  ) async {
    final trimmed = newDisplayName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Script name cannot be empty.');
    }
    final target = File(p.join(scriptsDir.path, '$trimmed.py'));
    if (await target.exists() && target.path != script.path) {
      throw const FileSystemException(
        'A script with that name already exists.',
      );
    }
    final moved = await script.file.rename(target.path);
    final id = await _readId(moved) ?? script.id;
    return DiscoveredScript(
      id: id,
      file: moved,
      displayName: p.basenameWithoutExtension(moved.path),
    );
  }

  /// Deletes the underlying `.py` file. Callers must warn first when the
  /// script is still referenced by wheel configuration (spec 13.1.8).
  Future<void> delete(DiscoveredScript script) async {
    if (await script.file.exists()) {
      await script.file.delete();
    }
  }

  /// Reads the ID from the file header, or null when absent.
  Future<String?> _readId(File file) async {
    try {
      final lines = await file.readAsLines();
      for (final line in lines.take(5)) {
        final index = line.indexOf(kScriptIdMarker);
        if (index >= 0) {
          final value = line.substring(index + kScriptIdMarker.length).trim();
          if (value.isNotEmpty) return value;
        }
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  /// Writes or replaces the ID line at the top of the file.
  Future<void> _writeId(File file, String id) async {
    String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException {
      contents = '';
    }

    final lines = contents.isEmpty ? <String>[] : contents.split('\n');
    var replaced = false;
    for (var i = 0; i < lines.length && i < 5; i++) {
      if (lines[i].contains(kScriptIdMarker)) {
        lines[i] = '$kScriptIdMarker $id';
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      lines.insert(0, '$kScriptIdMarker $id');
    }
    await file.writeAsString(lines.join('\n'), flush: true);
  }
}