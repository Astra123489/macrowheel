import 'package:flutter/material.dart';

import '../../models/configuration.dart';
import '../../services/studio_controller.dart';

/// Studio settings.
///
/// Only values the spec places in the shared JSON are editable here:
/// the shortcut preset path, the wheel and profile-cycle hotkeys, and the
/// script runtime selection (spec 3.1, 11, 13.2).
///
/// Wheel appearance and slice limits are fixed in v1 (spec section 10).
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.controller});

  final StudioController controller;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late final TextEditingController _presetPath;
  late final TextEditingController _customPythonPath;

  @override
  void initState() {
    super.initState();
    _presetPath =
        TextEditingController(text: widget.controller.config.shortcutPresetPath);
    _customPythonPath = TextEditingController(
      text: widget.controller.config.scriptRuntime.customPythonPath ?? '',
    );
  }

  @override
  void dispose() {
    _presetPath.dispose();
    _customPythonPath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final config = widget.controller.config;
        final conflicts = widget.controller.hotkeyConflicts;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle(context, 'DaVinci Resolve'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shortcut preset'),
              subtitle: Text(
                config.shortcutPresetPath.isEmpty
                    ? 'Not set'
                    : config.shortcutPresetPath,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextField(
              controller: _presetPath,
              decoration: const InputDecoration(
                labelText: 'Preset file path',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: _applyPresetPath,
                child: const Text('Apply'),
              ),
            ),
            const Divider(height: 32),

            _sectionTitle(context, 'Hotkeys'),
            _hotkeyField(
              label: 'Wheel activation (press and hold)',
              value: config.interactionSettings.wheelActivationHotkey,
              onChanged: widget.controller.setWheelActivationHotkey,
            ),
            _hotkeyField(
              label: 'Profile cycle',
              value: config.interactionSettings.profileCycleHotkey,
              onChanged: widget.controller.setProfileCycleHotkey,
            ),
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shortcut conflicts with your Resolve preset',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      for (final entry in conflicts.entries)
                        Text(
                          '${entry.key} clashes with '
                          '${entry.value.join(', ')}',
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(height: 32),

            _sectionTitle(context, 'Wheel'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Inner slices'),
              subtitle: const Text('$kMaxInnerSlices (fixed)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Outer commands'),
              subtitle: const Text('$kMaxOuterCommands (fixed)'),
            ),
            const Divider(height: 32),

            _sectionTitle(context, 'Script Runtime'),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'managed',
              groupValue: config.scriptRuntime.mode,
              title: const Text('Macro Wheel Script Runtime'),
              subtitle:
                  const Text('Managed and kept up to date by Macro Wheel.'),
              onChanged: (value) =>
                  widget.controller.setScriptRuntimeMode(value ?? 'managed'),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'custom',
              groupValue: config.scriptRuntime.mode,
              title: const Text('Custom Python'),
              subtitle: const Text(
                'Macro Wheel will not modify or install packages into this '
                'environment.',
              ),
              onChanged: (value) =>
                  widget.controller.setScriptRuntimeMode(value ?? 'managed'),
            ),
            if (config.scriptRuntime.mode == 'custom')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _customPythonPath,
                  decoration: const InputDecoration(
                    labelText: 'Python executable',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) => widget.controller
                      .setScriptRuntimeMode('custom', customPythonPath: value),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'The Command Runtime is owned and locked by Macro Wheel and is '
              'never user-configurable.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _hotkeyField({
    required String label,
    required String value,
    required void Function(String) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: value,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'Ctrl+Alt+Space',
            ),
            onFieldSubmitted: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _applyPresetPath() async {
    final path = _presetPath.text.trim();
    if (path.isEmpty) return;
    await widget.controller.loadShortcutPreset(path);
  }
}