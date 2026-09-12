import 'package:flutter/material.dart';

import '../../services/shortcut_parser.dart';
import '../../services/studio_controller.dart';

/// First-run setup wizard (spec section 15).
///
/// Flow:
///   Welcome
///     -> select DaVinci Resolve shortcut preset
///     -> validate / import preset
///     -> complete setup
///     -> open Studio
///
/// The wizard never asks the user to create Resolve pages. Initial profiles
/// are supplied as defaults for all seven fixed pages.
class FirstRunWizard extends StatefulWidget {
  const FirstRunWizard({super.key, required this.controller});

  final StudioController controller;

  @override
  State<FirstRunWizard> createState() => _FirstRunWizardState();
}

class _FirstRunWizardState extends State<FirstRunWizard> {
  final _presetController = TextEditingController();
  int _step = 0;
  String? _presetError;
  String? _presetSummary;
  bool _working = false;

  @override
  void dispose() {
    _presetController.dispose();
    super.dispose();
  }

  Future<void> _validatePreset() async {
    final path = _presetController.text.trim();
    if (path.isEmpty) {
      setState(() {
        _presetError = 'Choose your DaVinci Resolve shortcut preset file.';
        _presetSummary = null;
      });
      return;
    }

    try {
      final parser = await ShortcutParser.fromFile(path);
      setState(() {
        _presetError = null;
        _presetSummary = parser.hasSearchEffectsBinding
            ? 'Preset loaded. ${parser.bindings.length} commands found. '
                'Search Effects is bound to "${parser.searchEffectsShortcut}".'
            : 'Preset loaded (${parser.bindings.length} commands), but '
                'editSearchInEffects is not bound. Add Effects commands will '
                'use the built-in default until you bind it in Resolve.';
      });
    } on FormatException catch (e) {
      setState(() {
        _presetError = e.message;
        _presetSummary = null;
      });
    }
  }

  Future<void> _finish() async {
    setState(() => _working = true);
    try {
      await widget.controller.completeFirstRun(
        shortcutPresetPath: _presetController.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: _working
                  ? const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _buildStep(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case 0:
        return _welcome(context);
      case 1:
        return _presetStep(context);
      default:
        return _doneStep(context);
    }
  }

  Widget _welcome(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome to Macro Wheel', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        const Text(
          'Macro Wheel Studio creates the configuration that the Macro Wheel '
          'Menu reads at runtime.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Before you begin, Studio needs your DaVinci Resolve shortcut '
          'preset. It is used to resolve customized Resolve commands and to '
          'warn you about hotkey conflicts.',
        ),
        const SizedBox(height: 12),
        Text(
          'The preset is never used to detect the active Resolve page. That '
          'always comes from Resolve itself.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => setState(() => _step = 1),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _presetStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select your Resolve shortcut preset',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'In DaVinci Resolve, open Preferences, then Keyboard Mapping, and '
          'export your current preset. Paste the path to that .txt file '
          'below.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _presetController,
          decoration: InputDecoration(
            labelText: 'Preset file path',
            hintText: r'C:\Users\you\Documents\My Resolve Keys.txt',
            errorText: _presetError,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_presetError != null || _presetSummary != null) {
              setState(() {
                _presetError = null;
                _presetSummary = null;
              });
            }
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              onPressed: _validatePreset,
              child: const Text('Validate preset'),
            ),
          ],
        ),
        if (_presetSummary != null) ...[
          const SizedBox(height: 12),
          Text(_presetSummary!),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: _presetError == null
                  ? () => setState(() => _step = 2)
                  : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _doneStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Setup complete', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          'Studio will create a default profile for each Resolve page. You '
          'can add more profiles, build your wheel, and manage user scripts '
          'from the main editor.',
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: _finish,
              child: const Text('Open Studio'),
            ),
          ],
        ),
      ],
    );
  }
}