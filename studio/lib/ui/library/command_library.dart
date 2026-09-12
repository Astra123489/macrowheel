import 'package:flutter/material.dart';

import '../../models/builtin_commands.dart';
import '../../models/configuration.dart';

/// The Studio library panel.
///
/// Built-in and custom commands on one tab, discovered user scripts on the
/// other (spec 13.1.13). Commands and Scripts stay separate concepts.
///
/// Library categories (Add Effects, Edit, ...) organise this panel only.
/// They never become wheel slices automatically (spec 13.3).
class CommandLibrary extends StatefulWidget {
  const CommandLibrary({super.key, required this.onAddCommand});

  /// Called when the user places a command on the current wheel. The caller
  /// decides whether it lands on the inner ring or in the open category.
  final void Function(CommandRef command, String displayName) onAddCommand;

  @override
  State<CommandLibrary> createState() => _CommandLibraryState();
}

class _CommandLibraryState extends State<CommandLibrary> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = builtinsByCategory();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search library',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final category in LibraryCategories.ordered)
                if (grouped[category] != null)
                  _LibraryGroup(
                    title: category,
                    commands: _filter(grouped[category]!),
                    onAdd: widget.onAddCommand,
                  ),
            ],
          ),
        ),
      ],
    );
  }

  List<BuiltinCommand> _filter(List<BuiltinCommand> commands) {
    if (_query.isEmpty) return commands;
    return commands
        .where((c) =>
            c.displayName.toLowerCase().contains(_query) ||
            c.id.toLowerCase().contains(_query))
        .toList();
  }
}

class _LibraryGroup extends StatelessWidget {
  const _LibraryGroup({
    required this.title,
    required this.commands,
    required this.onAdd,
  });

  final String title;
  final List<BuiltinCommand> commands;
  final void Function(CommandRef command, String displayName) onAdd;

  @override
  Widget build(BuildContext context) {
    if (commands.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(title),
      children: [
        for (final command in commands)
          ListTile(
            dense: true,
            title: Text(command.displayName),
            subtitle: Text(
              command.effectPayload ?? command.keySequence ?? command.id,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add to wheel',
              onPressed: () =>
                  onAdd(command.toCommandRef(), command.displayName),
            ),
          ),
      ],
    );
  }
}