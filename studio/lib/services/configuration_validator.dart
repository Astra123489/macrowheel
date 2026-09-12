import '../models/configuration.dart';

/// A single validation problem found in a configuration.
class ValidationIssue {
  const ValidationIssue(this.path, this.message, {this.isError = true});

  /// Dotted location, e.g. `pages.edit.profiles[0].innerRing[2]`.
  final String path;
  final String message;
  final bool isError;

  @override
  String toString() => '${isError ? 'ERROR' : 'WARN'} $path: $message';
}

/// Validates the invariants the runtime Menu depends on. Studio runs this
/// before every publish so a partially valid file is never handed to the
/// runtime (spec section 5).
class ConfigurationValidator {
  const ConfigurationValidator._();

  static List<ValidationIssue> validate(Configuration config) {
    final issues = <ValidationIssue>[];

    if (config.schemaVersion != kSchemaVersion) {
      issues.add(ValidationIssue(
        'schemaVersion',
        'Expected $kSchemaVersion but found ${config.schemaVersion}.',
      ));
    }

    if (config.pages.isEmpty) {
      issues.add(const ValidationIssue('pages', 'No pages defined.'));
      return issues;
    }

    config.pages.forEach((page, pageConfig) {
      final pagePath = 'pages.$page';

      if (!kResolvePages.contains(page)) {
        issues.add(ValidationIssue(
          pagePath,
          'Not a Resolve page. Pages are fixed and cannot be added.',
        ));
      }

      if (pageConfig.profiles.isEmpty) {
        issues.add(ValidationIssue(
          pagePath,
          'Every page must have at least one profile.',
        ));
        return;
      }

      final defaultCount =
          pageConfig.profiles.where((p) => p.isDefault).length;
      if (defaultCount != 1) {
        issues.add(ValidationIssue(
          pagePath,
          'Exactly one default profile is required (found $defaultCount).',
        ));
      }

      final seenProfileIds = <String>{};
      for (var i = 0; i < pageConfig.profiles.length; i++) {
        final profile = pageConfig.profiles[i];
        final profilePath = '$pagePath.profiles[$i]';

        if (profile.id.isEmpty) {
          issues.add(ValidationIssue(profilePath, 'Profile has no id.'));
        } else if (!seenProfileIds.add(profile.id)) {
          issues.add(ValidationIssue(
            profilePath,
            'Duplicate profile id: ${profile.id}.',
          ));
        }

        if (profile.name.trim().isEmpty) {
          issues.add(ValidationIssue(profilePath, 'Profile name is empty.'));
        }

        if (profile.innerRing.length > kMaxInnerSlices) {
          issues.add(ValidationIssue(
            profilePath,
            'More than $kMaxInnerSlices inner slices.',
          ));
        }

        final seenSliceIds = <String>{};
        for (var j = 0; j < profile.innerRing.length; j++) {
          final slice = profile.innerRing[j];
          final slicePath = '$profilePath.innerRing[$j]';

          if (!seenSliceIds.add(slice.id)) {
            issues.add(ValidationIssue(
              slicePath,
              'Duplicate slice id: ${slice.id}.',
            ));
          }

          if (slice.isCommand && slice.command == null) {
            issues.add(ValidationIssue(
              slicePath,
              'Command slice has no command reference.',
            ));
          }

          if (slice.isCategory) {
            final category = slice.category;
            if (category == null) {
              issues.add(ValidationIssue(
                slicePath,
                'Category slice has no category definition.',
              ));
            } else {
              if (category.outerCommands.length > kMaxOuterCommands) {
                issues.add(ValidationIssue(
                  slicePath,
                  'Category has more than $kMaxOuterCommands commands.',
                ));
              }
              for (var k = 0; k < category.outerCommands.length; k++) {
                if (category.outerCommands[k].isAddEffect &&
                    (category.outerCommands[k].effectPayload ?? '').isEmpty) {
                  issues.add(ValidationIssue(
                    '$slicePath.category.outerCommands[$k]',
                    'Add Effect command has no search payload.',
                  ));
                }
              }
            }
          } else if (slice.command != null && slice.command!.isAddEffect) {
            if ((slice.command!.effectPayload ?? '').isEmpty) {
              issues.add(ValidationIssue(
                slicePath,
                'Add Effect command has no search payload.',
              ));
            }
          }
        }
      }
    });

    if (config.interactionSettings.wheelActivationHotkey.isEmpty) {
      issues.add(const ValidationIssue(
        'interactionSettings.wheelActivationHotkey',
        'Wheel activation hotkey is not set.',
      ));
    }

    return issues;
  }

  static List<ValidationIssue> errors(Configuration config) =>
      validate(config).where((i) => i.isError).toList(growable: false);

  static bool isValid(Configuration config) => errors(config).isEmpty;
}