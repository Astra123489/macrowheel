import 'package:flutter/material.dart';

import '../../services/studio_controller.dart';
import 'page_sidebar.dart';

/// Profile list for the selected Resolve page.
///
/// A Profile belongs to exactly one page; there is no global pool
/// (spec section 2.6). Users create, duplicate, rename, delete, reorder, and
/// set defaults here.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel({
    super.key,
    required this.controller,
    required this.page,
    required this.selectedProfileId,
    required this.onSelect,
  });

  final StudioController controller;
  final String page;
  final String? selectedProfileId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final pageConfig = controller.config.pages[page];
    final profiles = pageConfig?.profiles ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  PageSidebar.labelFor(page),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Add profile',
                icon: const Icon(Icons.add),
                onPressed: () => _promptNewProfile(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: profiles.isEmpty
              ? const Center(child: Text('No profiles'))
              : ReorderableListView.builder(
                  itemCount: profiles.length,
                  // onReorderItem reports newIndex already adjusted for the
                  // removed item, so it must not be decremented here.
                  onReorderItem: (oldIndex, newIndex) {
                    controller.reorderProfiles(page, oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final selected = profile.id == selectedProfileId;

                    return ListTile(
                      key: ValueKey(profile.id),
                      selected: selected,
                      title: Text(profile.name),
                      subtitle: profile.isDefault
                          ? const Text('Default')
                          : null,
                      onTap: () => onSelect(profile.id),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          switch (action) {
                            case 'rename':
                              _promptRename(context, profile.id, profile.name);
                            case 'duplicate':
                              controller.duplicateProfile(page, profile.id);
                            case 'default':
                              controller.setDefaultProfile(page, profile.id);
                            case 'delete':
                              controller.deleteProfile(page, profile.id);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate'),
                          ),
                          if (!profile.isDefault)
                            const PopupMenuItem(
                              value: 'default',
                              child: Text('Set as default'),
                            ),
                          PopupMenuItem(
                            value: 'delete',
                            // A page always keeps at least one profile.
                            enabled: profiles.length > 1,
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _promptNewProfile(BuildContext context) async {
    final name = await _promptName(context, title: 'New profile');
    if (name != null) controller.addProfile(page, name);
  }

  Future<void> _promptRename(
    BuildContext context,
    String profileId,
    String current,
  ) async {
    final name = await _promptName(
      context,
      title: 'Rename profile',
      initial: current,
    );
    if (name != null) controller.renameProfile(page, profileId, name);
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String initial = '',
  }) async {
    final textController = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Profile name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    textController.dispose();
    final trimmed = result?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}