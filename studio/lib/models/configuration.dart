import 'dart:convert';

/// Resolve pages are fixed concepts supplied by DaVinci Resolve and cannot be
/// created, renamed, or deleted by the user (spec section 2.1).
const List<String> kResolvePages = <String>[
  'media',
  'cut',
  'edit',
  'fusion',
  'color',
  'fairlight',
  'deliver',
];

/// Maximum slice counts, fixed by the product (spec section 8).
const int kMaxInnerSlices = 8;
const int kMaxOuterCommands = 16;

/// Current configuration schema version (spec section 4).
const int kSchemaVersion = 3;

/// A reference to something executable: a built-in command, a custom command,
/// a user script, or an Add Effects automation.
///
/// Only one of [commandId], [scriptId], or [effectPayload] is meaningful,
/// selected by [type].
class CommandRef {
  const CommandRef({
    required this.type,
    this.commandId,
    this.scriptId,
    this.effectPayload,
    this.effectName,
  });

  /// One of: `builtin`, `custom`, `script`, `addEffect`.
  final String type;

  /// Stable built-in ID (e.g. `builtin.effect.gaussian_blur`) or custom UUID.
  final String? commandId;

  /// User script UUID. The script file, not its filename, is the identity.
  final String? scriptId;

  /// Text typed into Resolve's Search Effects field.
  final String? effectPayload;

  /// Display name for an Add Effects command.
  final String? effectName;

  bool get isBuiltin => type == 'builtin';
  bool get isCustom => type == 'custom';
  bool get isScript => type == 'script';
  bool get isAddEffect => type == 'addEffect';

  Map<String, dynamic> toJson() {
    switch (type) {
      case 'builtin':
        return {'type': 'builtin', 'commandId': commandId};
      case 'custom':
        return {'type': 'custom', 'commandId': commandId};
      case 'script':
        return {'type': 'script', 'scriptId': scriptId};
      case 'addEffect':
        return {
          'type': 'addEffect',
          'effectPayload': effectPayload,
          if (effectName != null && effectName!.isNotEmpty) 'name': effectName,
        };
      default:
        throw StateError('Unknown command reference type: $type');
    }
  }

  static CommandRef fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'builtin';
    return CommandRef(
      type: type,
      commandId: json['commandId'] as String?,
      scriptId: json['scriptId'] as String?,
      effectPayload: json['effectPayload'] as String?,
      effectName: json['name'] as String?,
    );
  }

  CommandRef copyWith({
    String? type,
    String? commandId,
    String? scriptId,
    String? effectPayload,
    String? effectName,
  }) {
    return CommandRef(
      type: type ?? this.type,
      commandId: commandId ?? this.commandId,
      scriptId: scriptId ?? this.scriptId,
      effectPayload: effectPayload ?? this.effectPayload,
      effectName: effectName ?? this.effectName,
    );
  }

  /// The label shown on a wheel slice when the slice has no explicit label.
  String get defaultLabel {
    switch (type) {
      case 'addEffect':
        return effectName ?? effectPayload ?? '';
      case 'builtin':
      case 'custom':
        return commandId ?? '';
      case 'script':
        return scriptId ?? '';
      default:
        return '';
    }
  }
}

/// A Macro Wheel category: navigation inside a wheel, not a Studio library
/// grouping (spec 13.3 — the two are independent systems).
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.outerCommands,
  });

  final String id;
  final String name;
  final List<CommandRef> outerCommands;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'outerCommands': outerCommands.map((c) => c.toJson()).toList(),
      };

  static Category fromJson(Map<String, dynamic> json) {
    final outer = (json['outerCommands'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(CommandRef.fromJson)
        .toList();
    return Category(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      outerCommands: outer,
    );
  }

  Category copyWith({
    String? id,
    String? name,
    List<CommandRef>? outerCommands,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      outerCommands: outerCommands ?? this.outerCommands,
    );
  }
}

/// One of the up to eight inner-ring entries. Either a direct command or a
/// category that opens the outer fan (spec section 8.1).
class InnerSlice {
  const InnerSlice({
    required this.id,
    required this.type,
    this.label,
    this.command,
    this.category,
  });

  final String id;

  /// `command` or `category`.
  final String type;

  final String? label;
  final CommandRef? command;
  final Category? category;

  bool get isCategory => type == 'category';
  bool get isCommand => type == 'command';

  Map<String, dynamic> toJson() {
    if (isCategory) {
      if (category == null) {
        throw StateError('Category slice $id has no category definition.');
      }
      return {
        'id': id,
        'type': 'category',
        if (label != null && label!.isNotEmpty) 'label': label,
        'category': category!.toJson(),
      };
    }
    if (command == null) {
      throw StateError('Command slice $id has no command reference.');
    }
    return {
      'id': id,
      'type': 'command',
      if (label != null && label!.isNotEmpty) 'label': label,
      'command': command!.toJson(),
    };
  }

  static InnerSlice fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'command';
    if (type == 'category') {
      return InnerSlice(
        id: json['id'] as String,
        type: 'category',
        label: json['label'] as String?,
        category: Category.fromJson(
          (json['category'] as Map).cast<String, dynamic>(),
        ),
      );
    }
    return InnerSlice(
      id: json['id'] as String,
      type: 'command',
      label: json['label'] as String?,
      command: CommandRef.fromJson(
        (json['command'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  InnerSlice copyWith({
    String? id,
    String? type,
    String? label,
    CommandRef? command,
    Category? category,
  }) {
    return InnerSlice(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      command: command ?? this.command,
      category: category ?? this.category,
    );
  }
}

/// A user-owned configuration belonging to exactly one Resolve page.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.innerRing,
  });

  final String id;
  final String name;
  final bool isDefault;
  final List<InnerSlice> innerRing;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isDefault': isDefault,
        'innerRing': innerRing.map((s) => s.toJson()).toList(),
      };

  static Profile fromJson(Map<String, dynamic> json) {
    final slices = (json['innerRing'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(InnerSlice.fromJson)
        .toList();
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      innerRing: slices,
    );
  }

  Profile copyWith({
    String? id,
    String? name,
    bool? isDefault,
    List<InnerSlice>? innerRing,
  }) {
    return Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      innerRing: innerRing ?? this.innerRing,
    );
  }
}

/// The Profile collection owned by a single Resolve page. There is no global
/// profile pool (spec section 2.6).
class PageConfig {
  const PageConfig({required this.profiles});

  final List<Profile> profiles;

  Map<String, dynamic> toJson() => {
        'profiles': profiles.map((p) => p.toJson()).toList(),
      };

  static PageConfig fromJson(Map<String, dynamic> json) {
    final profiles = (json['profiles'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Profile.fromJson)
        .toList();
    return PageConfig(profiles: profiles);
  }

  PageConfig copyWith({List<Profile>? profiles}) =>
      PageConfig(profiles: profiles ?? this.profiles);
}

class InteractionSettings {
  const InteractionSettings({
    required this.wheelActivationHotkey,
    required this.profileCycleHotkey,
  });

  final String wheelActivationHotkey;
  final String profileCycleHotkey;

  static const InteractionSettings defaults = InteractionSettings(
    wheelActivationHotkey: 'Ctrl+Alt+Space',
    profileCycleHotkey: 'Ctrl+Alt+P',
  );

  Map<String, dynamic> toJson() => {
        'wheelActivationHotkey': wheelActivationHotkey,
        'profileCycleHotkey': profileCycleHotkey,
      };

  static InteractionSettings fromJson(Map<String, dynamic> json) {
    return InteractionSettings(
      wheelActivationHotkey:
          json['wheelActivationHotkey'] as String? ?? 'Ctrl+Alt+Space',
      profileCycleHotkey:
          json['profileCycleHotkey'] as String? ?? 'Ctrl+Alt+P',
    );
  }

  InteractionSettings copyWith({
    String? wheelActivationHotkey,
    String? profileCycleHotkey,
  }) {
    return InteractionSettings(
      wheelActivationHotkey:
          wheelActivationHotkey ?? this.wheelActivationHotkey,
      profileCycleHotkey: profileCycleHotkey ?? this.profileCycleHotkey,
    );
  }
}

class WheelSettings {
  const WheelSettings({
    this.maxInnerSlices = kMaxInnerSlices,
    this.maxOuterCommands = kMaxOuterCommands,
  });

  final int maxInnerSlices;
  final int maxOuterCommands;

  Map<String, dynamic> toJson() => {
        'maxInnerSlices': maxInnerSlices,
        'maxOuterCommands': maxOuterCommands,
      };

  static WheelSettings fromJson(Map<String, dynamic> json) {
    return WheelSettings(
      maxInnerSlices: json['maxInnerSlices'] as int? ?? kMaxInnerSlices,
      maxOuterCommands: json['maxOuterCommands'] as int? ?? kMaxOuterCommands,
    );
  }
}

class ScriptRuntimeSettings {
  const ScriptRuntimeSettings({
    this.mode = 'managed',
    this.customPythonPath,
  });

  /// `managed` (Macro Wheel Script Runtime) or `custom` (user-selected Python).
  final String mode;

  final String? customPythonPath;

  bool get isManaged => mode == 'managed';

  Map<String, dynamic> toJson() => {
        'mode': mode,
        if (customPythonPath != null && customPythonPath!.isNotEmpty)
          'customPythonPath': customPythonPath,
      };

  static ScriptRuntimeSettings fromJson(Map<String, dynamic> json) {
    return ScriptRuntimeSettings(
      mode: json['mode'] as String? ?? 'managed',
      customPythonPath: json['customPythonPath'] as String?,
    );
  }

  ScriptRuntimeSettings copyWith({String? mode, String? customPythonPath}) {
    return ScriptRuntimeSettings(
      mode: mode ?? this.mode,
      customPythonPath: customPythonPath ?? this.customPythonPath,
    );
  }
}

/// The whole shared configuration. Immutable: every edit produces a new
/// instance so undo/redo can hold previous values cheaply.
class Configuration {
  const Configuration({
    this.schemaVersion = kSchemaVersion,
    required this.pages,
    required this.interactionSettings,
    required this.wheelSettings,
    required this.scriptsFolder,
    required this.shortcutPresetPath,
    this.scriptRuntime = const ScriptRuntimeSettings(),
  });

  final int schemaVersion;
  final Map<String, PageConfig> pages;
  final InteractionSettings interactionSettings;
  final WheelSettings wheelSettings;
  final String scriptsFolder;
  final String shortcutPresetPath;
  final ScriptRuntimeSettings scriptRuntime;

  /// A configuration with no pages at all.
  ///
  /// Not publishable on its own: every page present must have at least one
  /// profile. Used as the starting point for undo/redo and for tests that
  /// build only the pages they care about.
  static Configuration empty({required String scriptsFolder}) {
    return Configuration(
      pages: <String, PageConfig>{},
      interactionSettings: InteractionSettings.defaults,
      wheelSettings: const WheelSettings(),
      scriptsFolder: scriptsFolder,
      shortcutPresetPath: '',
    );
  }

  /// A publishable starting configuration: one default profile per Resolve
  /// page, each with an empty wheel. This is what the first-run wizard
  /// writes before the user edits anything (spec section 15).
  static Configuration withDefaultProfiles({required String scriptsFolder}) {
    final pages = <String, PageConfig>{};
    for (final page in kResolvePages) {
      pages[page] = PageConfig(
        profiles: [
          Profile(
            id: 'default-$page',
            name: 'Default',
            isDefault: true,
            innerRing: const <InnerSlice>[],
          ),
        ],
      );
    }
    return Configuration(
      pages: pages,
      interactionSettings: InteractionSettings.defaults,
      wheelSettings: const WheelSettings(),
      scriptsFolder: scriptsFolder,
      shortcutPresetPath: '',
    );
  }

  /// The page names present in this configuration, in the fixed Resolve order.
  List<String> get pageNames =>
      kResolvePages.where(pages.containsKey).toList(growable: false);

  Profile? defaultProfileFor(String page) {
    final config = pages[page];
    if (config == null || config.profiles.isEmpty) return null;
    for (final profile in config.profiles) {
      if (profile.isDefault) return profile;
    }
    return config.profiles.first;
  }

  /// Every script ID referenced anywhere in the configuration. Used to warn
  /// before deleting a script that is still assigned to a wheel slice.
  Set<String> get referencedScriptIds {
    final ids = <String>{};
    for (final page in pages.values) {
      for (final profile in page.profiles) {
        for (final slice in profile.innerRing) {
          final cmd = slice.command;
          if (cmd != null && cmd.isScript && cmd.scriptId != null) {
            ids.add(cmd.scriptId!);
          }
          final cat = slice.category;
          if (cat != null) {
            for (final outer in cat.outerCommands) {
              if (outer.isScript && outer.scriptId != null) {
                ids.add(outer.scriptId!);
              }
            }
          }
        }
      }
    }
    return ids;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'scriptsFolder': scriptsFolder,
        'shortcutPresetPath': shortcutPresetPath,
        'scriptRuntime': scriptRuntime.toJson(),
        'interactionSettings': interactionSettings.toJson(),
        'wheelSettings': wheelSettings.toJson(),
        'pages': pages.map((name, config) => MapEntry(name, config.toJson())),
      };

  String toJsonString({bool pretty = true}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson())
             : jsonEncode(toJson());

  static Configuration fromJson(Map<String, dynamic> json) {
    final rawPages =
        (json['pages'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final pages = <String, PageConfig>{};
    rawPages.forEach((name, value) {
      pages[name] =
          PageConfig.fromJson((value as Map).cast<String, dynamic>());
    });

    return Configuration(
      schemaVersion: json['schemaVersion'] as int? ?? kSchemaVersion,
      pages: pages,
      interactionSettings: InteractionSettings.fromJson(
        (json['interactionSettings'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
      wheelSettings: WheelSettings.fromJson(
        (json['wheelSettings'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
      scriptsFolder: json['scriptsFolder'] as String? ?? '',
      shortcutPresetPath: json['shortcutPresetPath'] as String? ?? '',
      scriptRuntime: ScriptRuntimeSettings.fromJson(
        (json['scriptRuntime'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
    );
  }

  static Configuration fromJsonString(String source) =>
      Configuration.fromJson(
        (jsonDecode(source) as Map).cast<String, dynamic>(),
      );

  Configuration copyWith({
    int? schemaVersion,
    Map<String, PageConfig>? pages,
    InteractionSettings? interactionSettings,
    WheelSettings? wheelSettings,
    String? scriptsFolder,
    String? shortcutPresetPath,
    ScriptRuntimeSettings? scriptRuntime,
  }) {
    return Configuration(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      pages: pages ?? this.pages,
      interactionSettings: interactionSettings ?? this.interactionSettings,
      wheelSettings: wheelSettings ?? this.wheelSettings,
      scriptsFolder: scriptsFolder ?? this.scriptsFolder,
      shortcutPresetPath: shortcutPresetPath ?? this.shortcutPresetPath,
      scriptRuntime: scriptRuntime ?? this.scriptRuntime,
    );
  }

  Configuration withPage(String page, PageConfig config) {
    final next = Map<String, PageConfig>.from(pages);
    next[page] = config;
    return copyWith(pages: next);
  }
}