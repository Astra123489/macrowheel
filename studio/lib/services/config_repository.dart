import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/configuration.dart';
import '../utils/paths.dart';
import 'configuration_validator.dart';

/// Raised when a configuration cannot be loaded or safely published.
class ConfigRepositoryException implements Exception {
  ConfigRepositoryException(this.message, {this.issues = const []});

  final String message;
  final List<ValidationIssue> issues;

  @override
  String toString() {
    if (issues.isEmpty) return message;
    final detail = issues.map((i) => '  - $i').join('\n');
    return '$message\n$detail';
  }
}

/// Reads and publishes `configuration.json`.
///
/// Publishing is atomic (spec section 5):
///
///   validate in memory
///     -> write `<name>.tmp`
///     -> validate the temporary file on disk
///     -> rename over the active file
///
/// A crash or power loss can therefore never leave a half-written file where
/// the Menu would read it.
class ConfigRepository {
  ConfigRepository({File? configFile}) : _overrideFile = configFile;

  final File? _overrideFile;

  Future<File> _file() async =>
      _overrideFile ?? await AppPaths.configurationFile();

  /// Loads and validates the configuration.
  ///
  /// Returns null when the file does not exist yet (first run).
  /// Throws [ConfigRepositoryException] when the file exists but is invalid.
  Future<Configuration?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;

    final source = await file.readAsString();
    Configuration config;
    try {
      config = Configuration.fromJsonString(source);
    } on FormatException catch (e) {
      throw ConfigRepositoryException('Configuration is not valid JSON: ${e.message}');
    }

    final issues = ConfigurationValidator.errors(config);
    if (issues.isNotEmpty) {
      throw ConfigRepositoryException(
        'Configuration failed validation.',
        issues: issues,
      );
    }
    return config;
  }

  /// Atomically publishes [config].
  ///
  /// Throws [ConfigRepositoryException] when the configuration is invalid;
  /// nothing is written in that case.
  Future<void> save(Configuration config) async {
    final issues = ConfigurationValidator.errors(config);
    if (issues.isNotEmpty) {
      throw ConfigRepositoryException(
        'Refusing to publish an invalid configuration.',
        issues: issues,
      );
    }

    final file = await _file();
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final tempPath = p.join(dir.path, '${p.basename(file.path)}.tmp');
    final tempFile = File(tempPath);

    await tempFile.writeAsString(config.toJsonString(), flush: true);

    // Validate what actually landed on disk before replacing the active file.
    final written = Configuration.fromJsonString(await tempFile.readAsString());
    final writtenIssues = ConfigurationValidator.errors(written);
    if (writtenIssues.isNotEmpty) {
      await tempFile.delete();
      throw ConfigRepositoryException(
        'Published file failed validation; active configuration unchanged.',
        issues: writtenIssues,
      );
    }

    // Atomic replace. On Windows a plain rename fails when the destination
    // exists, so delete first; the window is acceptable because the temp file
    // is already complete and the Menu validates before adopting anything.
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }
}