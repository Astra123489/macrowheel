import 'package:flutter/material.dart';

import '../models/configuration.dart';
import '../services/studio_controller.dart';
import 'editor/page_sidebar.dart';
import 'editor/profile_panel.dart';
import 'editor/wheel_editor.dart';
import 'library/command_library.dart';
import 'scripts/script_library.dart';
import 'settings/settings_panel.dart';

/// The main Studio shell: pages, profiles, wheel editor, library, settings.
///
/// Layout:
///   [ page rail ] [ profile panel ] [ wheel editor ] [ inspector ]
///
/// The inspector is a tabbed panel holding the Library (Commands / Scripts)
/// and Settings. Keeping the library beside the wheel editor is what makes
/// "pick a command, place it on the wheel" a single gesture.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.controller});

  final StudioController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  String _page = kResolvePages.first;
  String? _profileId;
  int _inspectorTab = 0;
  String? _statusMessage;

  StudioController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _selectFirstProfile();
    _controller.addListener(_syncProfileSelection);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncProfileSelection);
    super.dispose();
  }

  void _selectFirstProfile() {
    final pageConfig = _controller.config.pages[_page];
    if (pageConfig != null && pageConfig.profiles.isNotEmpty) {
      _profileId = _controller.config.defaultProfileFor(_page)?.id ??
          pageConfig.profiles.first.id;
    }
  }

  /// Keeps the selected profile valid when profiles are deleted or the file
  /// is replaced. Falls back to the page default rather than crashing.
  void _syncProfileSelection() {
    final pageConfig = _controller.config.pages[_page];
    if (pageConfig == null || pageConfig.profiles.isEmpty) {
      if (_profileId != null) setState(() => _profileId = null);
      return;
    }
    final stillExists = pageConfig.profiles.any((p) => p.id == _profileId);
    if (!stillExists) {
      setState(() {
        _profileId = _controller.config.defaultProfileFor(_page)?.id ??
            pageConfig.profiles.first.id;
      });
    }
  }

  Profile? get _profile =>
      _profileId == null ? null : _controller.profileFor(_page, _profileId!);

  Future<void> _publish() async {
    try {
      await _controller.publish();
      _showStatus('Published to configuration.json');
    } on Exception catch (e) {
      _showStatus('Could not publish: $e', isError: true);
    }
  }

  void _showStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final errors = _controller.errors;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Macro Wheel Studio'),
            actions: [
              IconButton(
                tooltip: _controller.nextUndoLabel ?? 'Undo',
                icon: const Icon(Icons.undo),
                onPressed: _controller.canUndo ? _controller.undo : null,
              ),
              IconButton(
                tooltip: _controller.nextRedoLabel ?? 'Redo',
                icon: const Icon(Icons.redo),
                onPressed: _controller.canRedo ? _controller.redo : null,
              ),
              const SizedBox(width: 8),
              if (errors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Chip(
                    avatar: const Icon(Icons.error_outline, size: 18),
                    label: Text('${errors.length} issue'
                        '${errors.length == 1 ? '' : 's'}'),
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer,
                  ),
                ),
              FilledButton.icon(
                icon: const Icon(Icons.publish),
                label: const Text('Publish'),
                onPressed: _controller.isValid && !_controller.isBusy
                    ? _publish
                    : null,
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Row(
            children: [
              SizedBox(
                width: 96,
                child: PageSidebar(
                  selected: _page,
                  onSelect: (page) {
                    setState(() {
                      _page = page;
                      _selectFirstProfile();
                    });
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 260,
                child: ProfilePanel(
                  controller: _controller,
                  page: _page,
                  selectedProfileId: _profileId,
                  onSelect: (id) => setState(() => _profileId = id),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: WheelEditor(
                  controller: _controller,
                  page: _page,
                  profile: _profile,
                  onStatus: _showStatus,
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 320,
                child: _inspector(),
              ),
            ],
          ),
          bottomNavigationBar: _statusMessage == null
              ? null
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _statusMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
        );
      },
    );
  }

  Widget _inspector() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            onTap: (index) => setState(() => _inspectorTab = index),
            tabs: const [
              Tab(text: 'Commands'),
              Tab(text: 'Scripts'),
              Tab(text: 'Settings'),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _inspectorTab,
              children: [
                CommandLibrary(
                  onAddCommand: (command, displayName) {
                    final profile = _profile;
                    if (profile == null) {
                      _showStatus('Select a profile first.', isError: true);
                      return;
                    }
                    _controller.addSlice(
                      _page,
                      profile.id,
                      command,
                      label: displayName,
                    );
                  },
                ),
                ScriptLibrary(controller: _controller),
                SettingsPanel(controller: _controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}