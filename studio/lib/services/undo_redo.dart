import '../models/configuration.dart';

/// A single reversible edit applied to Studio's in-memory configuration.
///
/// Studio's undo/redo operates on the in-memory model only. Publishing the
/// JSON does not itself create an undo step (spec section 16).
abstract class EditCommand {
  /// Human-readable name shown in the UI, e.g. "Add Blade to Edit/Default".
  String get label;

  /// Applies the edit and returns the resulting configuration.
  Configuration apply(Configuration current);

  /// Reverts the edit and returns the resulting configuration.
  Configuration revert(Configuration current);
}

/// Generic command backed by two functions, used for the many edits that are
/// simple value replacements.
class FunctionalEdit extends EditCommand {
  FunctionalEdit({
    required this.label,
    required Configuration Function(Configuration) apply,
    required Configuration Function(Configuration) revert,
  })  : _apply = apply,
        _revert = revert;

  @override
  final String label;

  final Configuration Function(Configuration) _apply;
  final Configuration Function(Configuration) _revert;

  @override
  Configuration apply(Configuration current) => _apply(current);

  @override
  Configuration revert(Configuration current) => _revert(current);
}

/// Undo/redo stack over immutable configuration snapshots.
class UndoRedoStack {
  UndoRedoStack(Configuration initial) : _current = initial;

  Configuration _current;
  final List<EditCommand> _undo = <EditCommand>[];
  final List<EditCommand> _redo = <EditCommand>[];

  /// Depth limit; the oldest steps are dropped when exceeded.
  static const int maxDepth = 200;

  Configuration get current => _current;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get nextUndoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get nextRedoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// Applies [command] and pushes it onto the undo stack.
  ///
  /// Making a new edit discards any redo branch (spec section 16).
  void push(EditCommand command) {
    _current = command.apply(_current);
    _undo.add(command);
    _redo.clear();
    if (_undo.length > maxDepth) {
      _undo.removeAt(0);
    }
  }

  /// Reverts the most recent edit. Returns the new current configuration.
  Configuration undo() {
    if (_undo.isEmpty) return _current;
    final command = _undo.removeLast();
    _current = command.revert(_current);
    _redo.add(command);
    return _current;
  }

  /// Re-applies the most recently undone edit.
  Configuration redo() {
    if (_redo.isEmpty) return _current;
    final command = _redo.removeLast();
    _current = command.apply(_current);
    _undo.add(command);
    return _current;
  }

  /// Replaces the current configuration and clears all history.
  ///
  /// Used when a file is loaded or reloaded from disk, which is not itself an
  /// undoable edit.
  void reset(Configuration config) {
    _current = config;
    _undo.clear();
    _redo.clear();
  }
}