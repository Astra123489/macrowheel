import 'package:flutter/material.dart';

import '../../services/script_discovery.dart';
import '../../services/studio_controller.dart';

/// The Scripts tab of the Studio library (spec 13.1.13).
///
/// Scripts are discovered from the fixed Scripts folder. Studio displays,
/// renames, deletes, and opens them, but never edits their automation logic
/// (spec 13.1.6, Rule 19).
class ScriptLibrary extends StatelessWidget {
  const ScriptLibrary({super.key, required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final scripts = controller.scripts;

        if (scripts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No scripts found.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Drop .py files into the Scripts folder and they appear '
                    'here automatically. No import step is required.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open Scripts folder'),
                    onPressed: controller.openScriptsFolder,
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${scripts.length} script'
                      '${scripts.length == 1 ? '' : 's'}',
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open folder'),
                    onPressed: controller.openScriptsFolder,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: scripts.length,
                itemBuilder: (context, index) {
                  final script = scripts[index];
                  final inUse =
                      controller.referencedScriptIds.contains(script.id);

                  return ListTile(
                    leading: const Icon(Icons.code),
                    title: Text(script.displayName),
                    subtitle: Text(
                      inUse ? 'Used on the wheel' : script.id,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        switch (action) {
                          case 'open':
                            await controller.openScriptExternally(script);
                          case 'rename':
                            await _promptRename(context, script);
                          case 'delete':
                            await _confirmDelete(context, script, inUse);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'open', child: Text('Open externally')),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _promptRename(
    BuildContext context,
    DiscoveredScript script,
  ) async {
    final controller = TextEditingController(text: script.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename script'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Script name',
            helperText: 'The Script ID stays the same.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      await this.controller.renameScript(script, name.trim());
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DiscoveredScript script,
    bool inUse,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${script.displayName}"?'),
        content: Text(
          inUse
              ? 'This script is assigned to at least one wheel slice. '
                  'Deleting the file will leave those slices unable to run. '
                  'Your wheel configuration is not changed.'
              : 'The .py file is removed from the Scripts folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.deleteScript(script);
    }
  }
}