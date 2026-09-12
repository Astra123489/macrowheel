import 'dart:async';
import 'dart:io';

// Only ChangeNotifier is required. Importing foundation.dart wholesale also
// brings in dart:ui's `Category`, which shadows the model class of the same
// name declared in configuration.dart.
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:uuid/uuid.dart';

import '../models/configuration.dart';
import '../utils/paths.dart';
import 'config_repository.dart';
import 'configuration_validator.dart';
import 'script_discovery.dart';
import 'shortcut_parser.dart';
import 'undo_redo.dart';

/// Application state for Macro Wheel Studio.
///
/// Holds the in-memory configuration, the undo/redo stack, discovered user
/// scripts, and the parsed Resolve shortcut preset. Every mutation goes
/// through an [EditCommand] so undo/redo stays consistent (spec section 16).
class StudioController extends ChangeNotifier {
  StudioController({
    ConfigRepository? repository,
    Uuid? uuid,
  })  : _repository = repository ?? ConfigRepository(),
        _uuid = uuid ?? const Uuid();

  final ConfigRepository _repository;
  final Uuid _uuid;

  UndoRedoStack? _undoStack;
  ScriptDiscovery? _scriptDiscovery;
  StreamSubscription<List<DiscoveredScript>>? _scriptSub;

  List<DiscoveredScript> _scripts = const [];
  ShortcutParser? _shortcutParser;
  String? _loadError;
  bool _busy = false;
  bool _ready = false;

  // --- Read-only state ------------------------------------------------------

  /// True once [initialize] has finished, regardless of outcome.
  bool get isReady => _ready;

  /// True when no configuration has been loaded, so the wizard is required.
  bool get needsFirstRun => _undoStack == null;

  bool get isBusy => _busy;

  Configuration get config =>
      _undoStack?.current ?? Configuration.empty(scriptsFolder: '');

  bool get canUndo => _undoStack?.canUndo ?? false;
  bool get canRedo => _undoStack?.canRedo ?? false;
  String? get nextUndoLabel => _undoStack?.nextUndoLabel;
  String? get nextRedoLabel => _undoStack?.nextRedoLabel;

  List<DiscoveredScript> get scripts => _scripts;
  ShortcutParser? get shortcutParser => _shortcutParser;
  String? get loadError => _loadError;

  /// Scripts currently assigned to at least one wheel slice.
  Set<String> get referencedScriptIds => config.referencedScriptIds;

  /// Validation problems in the current configuration.
  List<ValidationIssue> get issues => ConfigurationValidator.validate(config);

  bool get isValid => issues.every((i) => !i.isError);

  List<ValidationIssue> get errors =>
      issues.where((i) => i.isError).toList(growable: false);

  /// Conflict report between Studio hotkeys and the imported Resolve preset.
  ///
  /// Empty when no preset has been imported (spec section 12).
  Map<String, List<String>> get hotkeyConflicts {
    final parser = _shortcutParser;
    if (parser == null) return const {};
    return parser.conflictsWith({
      'Wheel activation': config.interactionSettings.wheelActivationHotkey,
      'Profile cycle': config.interactionSettings.profileCycleHotkey,
    });
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Loads the configuration and the scripts folder.
  ///
  /// A missing configuration file is not an error: it means the first-run
  /// wizard should be shown. A present-but-invalid file is reported through
  /// [loadError] so the wizard can be offered as recovery.
  Future<void> initialize() async {
    _busy = true;
    _loadError = null;
    notifyListeners();

    try {
      final loaded = await _repository.load();
      if (loaded != null) {
        _undoStack = UndoRedoStack(loaded);
      }

      final scriptsDir = await AppPaths.scriptsDir();
      _scriptDiscovery = ScriptDiscovery(scriptsDir, uuid: _uuid);
      _scripts = await _scriptDiscovery!.scan();
      _scriptSub = _scriptDiscovery!.changes.listen((list) {
        _scripts = list;
        notifyListeners();
      });
      _scriptDiscovery!.startWatching();

      final presetPath = loaded?.shortcutPresetPath ?? '';
      if (presetPath.isNotEmpty) {
        await loadShortcutPreset(presetPath, persist: false);
      }
    } on ConfigRepositoryException catch (e) {
      _loadError = e.toString();
    } finally {
      _busy = false;
      _ready = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _scriptSub?.cancel();
    _scriptDiscovery?.dispose();
    super.dispose();
  }

  // --- Shortcut preset ------------------------------------------------------

  /// Parses the Resolve shortcut preset at [path].
  ///
  /// When [persist] is true the path is also written into the configuration,
  /// which is what the runtime Menu reads to resolve `editSearchInEffects`.
  Future<void> loadShortcutPreset(String path, {bool persist = true}) async {
    try {
      _shortcutParser = await ShortcutParser.fromFile(path);
    } on FormatException catch (e) {
      _loadError = 'Shortcut preset could not be parsed: ${e.message}';
      notifyListeners();
      return;
    }

    if (persist && _undoStack != null) {
      final previous = config.shortcutPresetPath;
      _push(FunctionalEdit(
        label: 'Set shortcut preset',
        apply: (c) => c.copyWith(shortcutPresetPath: path),
        revert: (c) => c.copyWith(shortcutPresetPath: previous),
      ));
    }
    notifyListeners();
  }

  // --- First run ------------------------------------------------------------

  /// Creates a publishable starting configuration: one default profile per
  /// Resolve page, plus the fixed scripts folder (spec section 15).
  Future<void> completeFirstRun({required String shortcutPresetPath}) async {
    final scriptsDir = await AppPaths.scriptsDir();
    final presetPath = shortcutPresetPath.trim();

    Configuration initial = Configuration.withDefaultProfiles(
      scriptsFolder: scriptsDir.path,
    );
    if (presetPath.isNotEmpty) {
      initial = initial.copyWith(shortcutPresetPath: presetPath);
    }

    _undoStack = UndoRedoStack(initial);
    if (presetPath.isNotEmpty) {
      await loadShortcutPreset(presetPath, persist: true);
    }
    await publish();
  }

  // --- Editing --------------------------------------------------------------

  void undo() {
    final stack = _undoStack;
    if (stack == null || !stack.canUndo) return;
    stack.undo();
    notifyListeners();
  }

  void redo() {
    final stack = _undoStack;
    if (stack == null || !stack.canRedo) return;
    stack.redo();
    notifyListeners();
  }

  /// Applies an edit as a single undoable step.
  void edit(EditCommand command) => _push(command);

  void _push(EditCommand command) {
    final stack = _undoStack;
    if (stack == null) return;
    stack.push(command);
    notifyListeners();
  }

  /// Replaces the whole configuration and clears history. Used by the wizard
  /// and by recovery from a bad file, neither of which is an undoable edit.
  void replaceConfiguration(Configuration next) {
    if (_undoStack == null) {
      _undoStack = UndoRedoStack(next);
    } else {
      _undoStack!.reset(next);
    }
    notifyListeners();
  }

  // --- Profiles -------------------------------------------------------------

  Profile? profileFor(String page, String profileId) {
    final pageConfig = config.pages[page];
    if (pageConfig == null) return null;
    for (final profile in pageConfig.profiles) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  void addProfile(String page, String name) {
    final pageConfig = config.pages[page];
    if (pageConfig == null || name.trim().isEmpty) return;

    final profile = Profile(
      id: _uuid.v4(),
      name: name.trim(),
      isDefault: pageConfig.profiles.isEmpty,
      innerRing: const [],
    );

    final previous = pageConfig;
    _push(FunctionalEdit(
      label: 'Add profile "${profile.name}"',
      apply: (c) => c.withPage(
        page,
        previous.copyWith(profiles: [...previous.profiles, profile]),
      ),
      revert: (c) => c.withPage(page, previous),
    ));
  }

  void duplicateProfile(String page, String profileId) {
    final pageConfig = config.pages[page];
    final source = profileFor(page, profileId);
    if (pageConfig == null || source == null) return;

    final copy = Profile(
      id: _uuid.v4(),
      name: '${source.name} Copy',
      isDefault: false,
      innerRing: [
        for (final slice in source.innerRing)
          slice.copyWith(
            id: _uuid.v4(),
            category: _reIdCategory(slice.category),
          ),
      ],
    );

    final previous = pageConfig;
    _push(FunctionalEdit(
      label: 'Duplicate profile "${source.name}"',
      apply: (c) => c.withPage(
        page,
        previous.copyWith(profiles: [...previous.profiles, copy]),
      ),
      revert: (c) => c.withPage(page, previous),
    ));
  }

  void renameProfile(String page, String profileId, String newName) {
    final pageConfig = config.pages[page];
    final index =
        pageConfig?.profiles.indexWhere((p) => p.id == profileId) ?? -1;
    if (pageConfig == null || index < 0 || newName.trim().isEmpty) return;

    final previous = pageConfig;
    final profiles = [...pageConfig.profiles];
    profiles[index] = profiles[index].copyWith(name: newName.trim());

    _push(FunctionalEdit(
      label: 'Rename profile to "${newName.trim()}"',
      apply: (c) => c.withPage(page, previous.copyWith(profiles: profiles)),
      revert: (c) => c.withPage(page, previous),
    ));
  }

  void deleteProfile(String page, String profileId) {
    final pageConfig = config.pages[page];
    // A page must always keep at least one profile (spec section 2.3).
    if (pageConfig == null || pageConfig.profiles.length <= 1) return;

    final index = pageConfig.profiles.indexWhere((p) => p.id == profileId);
    if (index < 0) return;

    final previous = pageConfig;
    final profiles = [...pageConfig.profiles]..removeAt(index);
    // Never leave a page without a default profile.
    if (!profiles.any((p) => p.isDefault) && profiles.isNotEmpty) {
      profiles[0] = profiles[0].copyWith(isDefault: true);
    }

    _push(FunctionalEdit(
      label: 'Delete profile',
      apply: (c) => c.withPage(page, previous.copyWith(profiles: profiles)),
      revert: (c) => c.withPage(page, previous),
    ));
  }

  void setDefaultProfile(String page, String profileId) {
    final pageConfig = config.pages[page];
    if (pageConfig == null) return;
    final previous = pageConfig;

    final profiles = [
      for (final p in pageConfig.profiles)
        p.copyWith(isDefault: p.id == profileId),
    ];

    _push(FunctionalEdit(
      label: 'Set default profile',
      apply: (c) => c.withPage(page, previous.copyWith(profiles: profiles)),
      revert: (c) => c.withPage(page, previous),
    ));
  }

  void reorderProfiles(String page, int oldIndex, int newIndex) {
    final pageConfig = config.pages[page];
    if (pageConfig == null) return;
    if (oldIndex < 0 || oldIndex >= pageConfig.profiles.length) return;

    final previous = pageConfig;
    final profiles = _reorder(pageConfig.profiles, oldIndex, newIndex);

    _push(FunctionalEdit(
      label: 'Reorder profiles',
      apply: (c) => c.withPage(page, previous.copyWith(profiles: profiles)),
      revert: (c) => c.withPage(page, previous),
    ));
  }

  // --- Wheel slices ---------------------------------------------------------

  void addSlice(
    String page,
    String profileId,
    CommandRef command, {
    String? label,
  }) {
    _mutateProfile(page, profileId, 'Add slice', (profile) {
      if (profile.innerRing.length >= kMaxInnerSlices) return profile;
      return profile.copyWith(
        innerRing: [
          ...profile.innerRing,
          InnerSlice(
            id: _uuid.v4(),
            type: 'command',
            label: label,
            command: command,
          ),
        ],
      );
    });
  }

  void addCategory(String page, String profileId, String name) {
    if (name.trim().isEmpty) return;
    _mutateProfile(page, profileId, 'Add category "${name.trim()}"', (profile) {
      if (profile.innerRing.length >= kMaxInnerSlices) return profile;
      return profile.copyWith(
        innerRing: [
          ...profile.innerRing,
          InnerSlice(
            id: _uuid.v4(),
            type: 'category',
            label: name.trim(),
            category: Category(
              id: _uuid.v4(),
              name: name.trim(),
              outerCommands: const [],
            ),
          ),
        ],
      );
    });
  }

  void removeSlice(String page, String profileId, String sliceId) {
    _mutateProfile(page, profileId, 'Remove slice', (profile) {
      return profile.copyWith(
        innerRing: profile.innerRing.where((s) => s.id != sliceId).toList(),
      );
    });
  }

  void setSliceLabel(
    String page,
    String profileId,
    String sliceId,
    String label,
  ) {
    _mutateProfile(page, profileId, 'Rename slice', (profile) {
      return profile.copyWith(
        innerRing: [
          for (final s in profile.innerRing)
            s.id == sliceId ? s.copyWith(label: label) : s,
        ],
      );
    });
  }

  void reorderSlices(
    String page,
    String profileId,
    int oldIndex,
    int newIndex,
  ) {
    _mutateProfile(page, profileId, 'Reorder slices', (profile) {
      if (oldIndex < 0 || oldIndex >= profile.innerRing.length) return profile;
      return profile.copyWith(
        innerRing: _reorder(profile.innerRing, oldIndex, newIndex),
      );
    });
  }

  void addOuterCommand(
    String page,
    String profileId,
    String sliceId,
    CommandRef command, {
    String? label,
  }) {
    _mutateProfile(page, profileId, 'Add outer command', (profile) {
      return profile.copyWith(
        innerRing: [
          for (final slice in profile.innerRing)
            slice.id == sliceId ? _appendOuter(slice, command) : slice,
        ],
      );
    });
  }

  void removeOuterCommand(
    String page,
    String profileId,
    String sliceId,
    int outerIndex,
  ) {
    _mutateProfile(page, profileId, 'Remove outer command', (profile) {
      return profile.copyWith(
        innerRing: [
          for (final slice in profile.innerRing)
            if (slice.id == sliceId && slice.category != null)
              slice.copyWith(
                category: slice.category!.copyWith(
                  outerCommands: [...slice.category!.outerCommands]
                    ..removeAt(outerIndex),
                ),
              )
            else
              slice,
        ],
      );
    });
  }

  void reorderOuterCommands(
    String page,
    String profileId,
    String sliceId,
    int oldIndex,
    int newIndex,
  ) {
    _mutateProfile(page, profileId, 'Reorder outer commands', (profile) {
      return profile.copyWith(
        innerRing: [
          for (final slice in profile.innerRing)
            if (slice.id == sliceId && slice.category != null)
              slice.copyWith(
                category: slice.category!.copyWith(
                  outerCommands: _reorder(
                    slice.category!.outerCommands,
                    oldIndex,
                    newIndex,
                  ),
                ),
              )
            else
              slice,
        ],
      );
    });
  }

  // --- Settings -------------------------------------------------------------

  void setWheelActivationHotkey(String sequence) {
    final previous = config.interactionSettings;
    _push(FunctionalEdit(
      label: 'Change wheel activation hotkey',
      apply: (c) => c.copyWith(
        interactionSettings:
            previous.copyWith(wheelActivationHotkey: sequence),
      ),
      revert: (c) => c.copyWith(interactionSettings: previous),
    ));
  }

  void setProfileCycleHotkey(String sequence) {
    final previous = config.interactionSettings;
    _push(FunctionalEdit(
      label: 'Change profile cycle hotkey',
      apply: (c) => c.copyWith(
        interactionSettings: previous.copyWith(profileCycleHotkey: sequence),
      ),
      revert: (c) => c.copyWith(interactionSettings: previous),
    ));
  }

  void setScriptRuntimeMode(String mode, {String? customPythonPath}) {
    final previous = config.scriptRuntime;
    _push(FunctionalEdit(
      label: 'Change script runtime',
      apply: (c) => c.copyWith(
        scriptRuntime: ScriptRuntimeSettings(
          mode: mode,
          customPythonPath: customPythonPath ?? previous.customPythonPath,
        ),
      ),
      revert: (c) => c.copyWith(scriptRuntime: previous),
    ));
  }

  // --- Scripts --------------------------------------------------------------

  Future<void> renameScript(DiscoveredScript script, String newName) async {
    final discovery = _scriptDiscovery;
    if (discovery == null) return;
    await discovery.rename(script, newName);
    _scripts = await discovery.scan();
    notifyListeners();
  }

  Future<void> deleteScript(DiscoveredScript script) async {
    final discovery = _scriptDiscovery;
    if (discovery == null) return;
    await discovery.delete(script);
    _scripts = await discovery.scan();
    notifyListeners();
  }

  /// Opens a script in the operating system's associated editor. Studio never
  /// edits script contents itself (spec 13.1.6).
  Future<void> openScriptExternally(DiscoveredScript script) async {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', script.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [script.path]);
    } else {
      await Process.run('xdg-open', [script.path]);
    }
  }

  /// Reveals the fixed Scripts folder in the operating system's file manager.
  Future<void> openScriptsFolder() async {
    final dir = _scriptDiscovery?.scriptsDir;
    if (dir == null) return;
    if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else {
      await Process.run('xdg-open', [dir.path]);
    }
  }

  // --- Publishing -----------------------------------------------------------

  /// Atomically publishes the current configuration.
  ///
  /// Throws [ConfigRepositoryException] when the configuration is invalid;
  /// the previously published file is left untouched in that case.
  Future<void> publish() async {
    _busy = true;
    notifyListeners();
    try {
      await _repository.save(config);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // --- Internals ------------------------------------------------------------

  void _mutateProfile(
    String page,
    String profileId,
    String label,
    Profile Function(Profile) transform,
  ) {
    final pageConfig = config.pages[page];
    final index =
        pageConfig?.profiles.indexWhere((p) => p.id == profileId) ?? -1;
    if (pageConfig == null || index < 0) return;

    final previous = pageConfig;
    final profiles = [...pageConfig.profiles];
    profiles[index] = transform(profiles[index]);

    _push(FunctionalEdit(
      label: label,
      apply: (c) => c.withPage(page, previous.copyWith(profiles: profiles)),
      revert: (c) => c.withPage(page, previous),
    ));
  }

  InnerSlice _appendOuter(InnerSlice slice, CommandRef command) {
    final category = slice.category;
    if (category == null) return slice;
    if (category.outerCommands.length >= kMaxOuterCommands) return slice;
    return slice.copyWith(
      category: category.copyWith(
        outerCommands: [...category.outerCommands, command],
      ),
    );
  }

  /// Re-IDs a duplicated category so a copy never shares identity with its
  /// source (the same principle spec 13.1.10 applies to scripts).
  Category? _reIdCategory(Category? category) {
    if (category == null) return null;
    return category.copyWith(id: _uuid.v4());
  }

  static List<T> _reorder<T>(List<T> list, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= list.length) return list;
    final copy = [...list];
    final moved = copy.removeAt(oldIndex);
    copy.insert(newIndex.clamp(0, copy.length), moved);
    return copy;
  }
}