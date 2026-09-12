import 'package:flutter/material.dart';

import '../../models/builtin_commands.dart';
import '../../models/configuration.dart';
import '../../services/studio_controller.dart';

/// Wheel editor for one profile.
///
/// Left: the eight inner-ring slots. Right: the outer commands of whichever
/// category slice is selected. Both reorder by drag; both show their limits.
///
/// This edits semantic configuration only. No angles, radii, or pixel
/// positions are ever stored (spec section 9.2 / Rule 7).
class WheelEditor extends StatefulWidget {
  const WheelEditor({
    super.key,
    required this.controller,
    required this.page,
    required this.profile,
    required this.onStatus,
  });

  final StudioController controller;
  final String page;
  final Profile? profile;
  final void Function(String message, {bool isError}) onStatus;

  @override
  State<WheelEditor> createState() => _WheelEditorState();
}

class _WheelEditorState extends State<WheelEditor> {
  String? _selectedCategorySliceId;

  @override
  void didUpdateWidget(covariant WheelEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching profiles invalidates the selected category.
    if (oldWidget.profile?.id != widget.profile?.id) {
      _selectedCategorySliceId = null;
    }
  }

  InnerSlice? get _selectedCategorySlice {
    final profile = widget.profile;
    if (profile == null || _selectedCategorySliceId == null) return null;
    for (final slice in profile.innerRing) {
      if (slice.id == _selectedCategorySliceId && slice.isCategory) {
        return slice;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    if (profile == null) {
      return const Center(child: Text('Select a profile to edit its wheel'));
    }

    final category = _selectedCategorySlice;

    return Row(
      children: [
        Expanded(flex: 3, child: _innerRing(context, profile)),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: category == null
              ? _noCategoryHint(context)
              : _outerRing(context, profile, category),
        ),
      ],
    );
  }

  // --- Inner ring -----------------------------------------------------------

  Widget _innerRing(BuildContext context, Profile profile) {
    final slices = profile.innerRing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          'Inner ring',
          '${slices.length} / $kMaxInnerSlices',
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.category_outlined, size: 18),
              label: const Text('Category'),
              onPressed: slices.length >= kMaxInnerSlices
                  ? null
                  : () => _promptNewCategory(context),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: slices.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'The wheel is empty. Add commands from the Commands '
                      'tab, or add a category to group them.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: slices.length,
                  onReorderItem: (oldIndex, newIndex) {
                    widget.controller.reorderSlices(
                      widget.page,
                      profile.id,
                      oldIndex,
                      newIndex,
                    );
                  },
                  itemBuilder: (context, index) =>
                      _sliceTile(context, profile, slices[index]),
                ),
        ),
      ],
    );
  }

  Widget _sliceTile(BuildContext context, Profile profile, InnerSlice slice) {
    final isSelected = slice.id == _selectedCategorySliceId;
    final title = slice.label?.isNotEmpty == true
        ? slice.label!
        : slice.isCategory
            ? slice.category?.name ?? 'Category'
            : displayNameForCommand(slice.command!);

    return ListTile(
      key: ValueKey(slice.id),
      selected: isSelected,
      leading: Icon(
        slice.isCategory ? Icons.folder_outlined : Icons.play_arrow_outlined,
      ),
      title: Text(title),
      subtitle: Text(
        slice.isCategory
            ? '${slice.category?.outerCommands.length ?? 0} '
                'command${(slice.category?.outerCommands.length ?? 0) == 1 ? '' : 's'}'
            : _commandSubtitle(slice.command!),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: slice.isCategory
          ? () => setState(() => _selectedCategorySliceId = slice.id)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _promptRenameSlice(context, profile, slice, title),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              widget.controller.removeSlice(widget.page, profile.id, slice.id);
              if (isSelected) {
                setState(() => _selectedCategorySliceId = null);
              }
            },
          ),
        ],
      ),
    );
  }

  String _commandSubtitle(CommandRef command) {
    switch (command.type) {
      case 'addEffect':
        return 'Add Effect: ${command.effectPayload}';
      case 'script':
        return 'Script: ${command.scriptId}';
      case 'builtin':
        return command.commandId ?? '';
      case 'custom':
        return 'Custom command';
      default:
        return command.type;
    }
  }

  // --- Outer ring -----------------------------------------------------------

  Widget _outerRing(BuildContext context, Profile profile, InnerSlice slice) {
    final category = slice.category!;
    final commands = category.outerCommands;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          category.name,
          '${commands.length} / $kMaxOuterCommands',
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _selectedCategorySliceId = null),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: commands.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No outer commands yet. Add them from the Commands tab '
                      'while this category is selected.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: commands.length,
                  onReorderItem: (oldIndex, newIndex) {
                    widget.controller.reorderOuterCommands(
                      widget.page,
                      profile.id,
                      slice.id,
                      oldIndex,
                      newIndex,
                    );
                  },
                  itemBuilder: (context, index) {
                    final command = commands[index];
                    return ListTile(
                      key: ValueKey('${slice.id}_$index'),
                      dense: true,
                      leading: const Icon(Icons.circle, size: 10),
                      title: Text(displayNameForCommand(command)),
                      subtitle: Text(
                        _commandSubtitle(command),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => widget.controller.removeOuterCommand(
                          widget.page,
                          profile.id,
                          slice.id,
                          index,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _noCategoryHint(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Select a category on the left to edit its outer commands.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  // --- Chrome ---------------------------------------------------------------

  Widget _header(
    BuildContext context,
    String title,
    String count, {
    List<Widget> actions = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text(count, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }

  // --- Dialogs --------------------------------------------------------------

  Future<void> _promptNewCategory(BuildContext context) async {
    final textController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Category name',
            hintText: 'Effects',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    textController.dispose();

    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty && widget.profile != null) {
      widget.controller.addCategory(widget.page, widget.profile!.id, trimmed);
    }
  }

  Future<void> _promptRenameSlice(
    BuildContext context,
    Profile profile,
    InnerSlice slice,
    String current,
  ) async {
    final textController = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename slice'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Label'),
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

    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      widget.controller
          .setSliceLabel(widget.page, profile.id, slice.id, trimmed);
    }
  }
}