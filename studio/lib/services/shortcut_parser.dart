import 'dart:io';

/// A single parsed entry from a DaVinci Resolve shortcut preset.
class ShortcutBinding {
  const ShortcutBinding({
    required this.commandId,
    required this.sequences,
  });

  final String commandId;

  /// Every key sequence bound to the command, in preset order. Resolve allows
  /// alternatives separated by `|`.
  final List<String> sequences;
}

/// Parses the DaVinci Resolve shortcut preset `.txt` format:
///
/// ```
/// editBlade := B
/// fileSaveProject := Ctrl+S
/// FusionWidget.fuHotkey_... := Ctrl+R | Alt+R
/// ```
///
/// Lines with an empty right-hand side mean the command is unbound. Blank
/// lines and lines starting with `#` are ignored.
///
/// Used by Studio for two purposes:
///   1. Resolving shortcut-dependent wheel commands (spec 11).
///   2. Detecting conflicts between wheel hotkeys and Resolve commands
///      (spec 12).
class ShortcutParser {
  ShortcutParser._(this._bindings);

  final Map<String, List<String>> _bindings;

  static const String searchEffectsCommandId = 'editSearchInEffects';

  /// Parses [contents]. Throws [FormatException] when the text is empty.
  static ShortcutParser parse(String contents) {
    if (contents.trim().isEmpty) {
      throw const FormatException('Shortcut preset is empty.');
    }

    final bindings = <String, List<String>>{};
    for (final rawLine in contents.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final sep = line.indexOf(':=');
      if (sep < 0) continue;

      final commandId = line.substring(0, sep).trim();
      final rhs = line.substring(sep + 2).trim();
      if (commandId.isEmpty || rhs.isEmpty) continue;

      final alternatives = rhs
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (alternatives.isEmpty) continue;

      // A later line overrides an earlier one for the same command.
      bindings[commandId] = alternatives;
    }

    if (bindings.isEmpty) {
      throw const FormatException(
        'Shortcut preset contains no parseable bindings.',
      );
    }
    return ShortcutParser._(bindings);
  }

  /// Reads and parses the preset file at [path].
  static Future<ShortcutParser> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FormatException('Shortcut preset not found: $path');
    }
    return ShortcutParser.parse(await file.readAsString());
  }

  /// All commands in the preset.
  Iterable<ShortcutBinding> get bindings => _bindings.entries.map(
        (e) => ShortcutBinding(commandId: e.key, sequences: e.value),
      );

  /// Key sequences bound to [commandId], or an empty list when unbound.
  List<String> sequencesFor(String commandId) =>
      _bindings[commandId] ?? const <String>[];

  /// True when the preset binds `editSearchInEffects`.
  bool get hasSearchEffectsBinding =>
      (_bindings[searchEffectsCommandId] ?? const <String>[]).isNotEmpty;

  /// The key sequence bound to `editSearchInEffects`, or null when unbound.
  String? get searchEffectsShortcut {
    final list = _bindings[searchEffectsCommandId];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  /// Every command ID that shares [sequence]. Empty when there is no clash.
  List<String> commandsUsing(String sequence) {
    final hits = <String>[];
    _bindings.forEach((commandId, sequences) {
      if (sequences.contains(sequence)) hits.add(commandId);
    });
    hits.sort();
    return hits;
  }

  /// Finds every pair where a Studio-owned hotkey sequence collides with a
  /// Resolve command.
  ///
  /// [studioHotkeys] maps a Studio-side label (e.g. "Wheel activation") to the
  /// key sequence assigned to it. The returned map is keyed by that label.
  Map<String, List<String>> conflictsWith(
    Map<String, String> studioHotkeys,
  ) {
    final result = <String, List<String>>{};
    studioHotkeys.forEach((label, sequence) {
      if (sequence.isEmpty) return;
      final clashes = commandsUsing(sequence);
      if (clashes.isNotEmpty) result[label] = clashes;
    });
    return result;
  }
}