import 'configuration.dart';

/// A Macro Wheel-owned library command.
///
/// Built-in commands are application-owned and read-only to users
/// (spec 13.6). They are addressed by stable IDs so that library updates in
/// future releases never break existing wheel assignments (spec 13.7).
///
/// This table mirrors the runtime registry in
/// `menu/src/commands/CommandRegistry.cpp`. Keeping the two in sync is what
/// makes a built-in ID resolvable on both sides.
class BuiltinCommand {
  const BuiltinCommand({
    required this.id,
    required this.displayName,
    required this.libraryCategory,
    this.effectPayload,
    this.keySequence,
  });

  /// Stable ID, e.g. `builtin.effect.gaussian_blur`.
  final String id;

  /// Studio-facing name.
  final String displayName;

  /// Library grouping (spec 13.3 — unrelated to wheel categories).
  final String libraryCategory;

  /// Search payload for Add Effects commands; null for key-sequence commands.
  final String? effectPayload;

  /// Key sequence for non-effect commands; null for Add Effects.
  final String? keySequence;

  bool get isAddEffect => effectPayload != null;

  /// Builds the command reference to store in a wheel slice.
  CommandRef toCommandRef() {
    if (isAddEffect) {
      return CommandRef(
        type: 'addEffect',
        effectPayload: effectPayload,
        effectName: displayName,
      );
    }
    return CommandRef(type: 'builtin', commandId: id);
  }
}

/// Library category names. These organise the Studio library only; they never
/// become wheel slices automatically (spec 13.3).
class LibraryCategories {
  static const String addEffects = 'Add Effects';
  static const String edit = 'Edit';
  static const String color = 'Color';
  static const String fusion = 'Fusion';

  static const List<String> ordered = <String>[
    addEffects,
    edit,
    color,
    fusion,
  ];
}

/// The built-in command library shipped with this release.
///
/// Add Effects entries all share one fixed automation; only the search payload
/// differs (spec 13.3 / 13.4).
const List<BuiltinCommand> kBuiltinCommands = <BuiltinCommand>[
  // --- Add Effects (starter set) ---
  BuiltinCommand(
    id: 'builtin.effect.gaussian_blur',
    displayName: 'Gaussian Blur',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Gaussian Blur OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.sharpen',
    displayName: 'Sharpen',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Sharpen OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.glow',
    displayName: 'Glow',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Glow OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.directional_blur',
    displayName: 'Directional Blur',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Directional Blur OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.film_grain',
    displayName: 'Film Grain',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Film Grain OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.chromatic_aberration',
    displayName: 'Chromatic Aberration',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Chromatic Aberration OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.vignette',
    displayName: 'Vignette',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Vignette OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.letterbox',
    displayName: 'Letterbox',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Letterbox OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.motion_blur',
    displayName: 'Motion Blur',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Motion Blur OFX',
  ),
  BuiltinCommand(
    id: 'builtin.effect.lens_flare',
    displayName: 'Lens Flare',
    libraryCategory: LibraryCategories.addEffects,
    effectPayload: 'Lens Flare OFX',
  ),

  // --- Edit ---
  BuiltinCommand(
    id: 'builtin.edit.blade',
    displayName: 'Blade',
    libraryCategory: LibraryCategories.edit,
    keySequence: 'B',
  ),
  BuiltinCommand(
    id: 'builtin.edit.ripple_delete',
    displayName: 'Ripple Delete',
    libraryCategory: LibraryCategories.edit,
    keySequence: 'Shift+Backspace',
  ),
  BuiltinCommand(
    id: 'builtin.edit.add_transition',
    displayName: 'Add Transition',
    libraryCategory: LibraryCategories.edit,
    keySequence: 'Ctrl+T',
  ),

  // --- Color ---
  BuiltinCommand(
    id: 'builtin.color.add_node',
    displayName: 'Add Serial Node',
    libraryCategory: LibraryCategories.color,
    keySequence: 'Alt+S',
  ),

  // --- Fusion ---
  BuiltinCommand(
    id: 'builtin.fusion.add_tool',
    displayName: 'Add Tool',
    libraryCategory: LibraryCategories.fusion,
    keySequence: 'Shift+Space',
  ),
];

/// Looks up a built-in command by ID.
BuiltinCommand? builtinCommandById(String id) {
  for (final command in kBuiltinCommands) {
    if (command.id == id) return command;
  }
  return null;
}

/// Display name for any command reference, resolving built-in IDs to their
/// friendly names and falling back to whatever the reference carries.
String displayNameForCommand(CommandRef ref) {
  if (ref.isBuiltin && ref.commandId != null) {
    return builtinCommandById(ref.commandId!)?.displayName ?? ref.commandId!;
  }
  return ref.defaultLabel;
}

/// Built-in commands grouped by library category.
Map<String, List<BuiltinCommand>> builtinsByCategory() {
  final grouped = <String, List<BuiltinCommand>>{};
  for (final command in kBuiltinCommands) {
    grouped.putIfAbsent(command.libraryCategory, () => []).add(command);
  }
  return grouped;
}