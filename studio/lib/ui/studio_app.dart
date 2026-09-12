import 'package:flutter/material.dart';

import '../services/studio_controller.dart';
import 'main_shell.dart';
import 'wizard/first_run_wizard.dart';

/// Root of Macro Wheel Studio.
///
/// Studio owns configuration authoring only. It never changes the active
/// Resolve page and never edits user script logic.
///
/// Startup decides between three states:
///   - still loading
///   - first run, or a configuration that failed to load  -> wizard
///   - a valid configuration                              -> main shell
class StudioApp extends StatefulWidget {
  const StudioApp({super.key});

  @override
  State<StudioApp> createState() => _StudioAppState();
}

class _StudioAppState extends State<StudioApp> {
  late final StudioController _controller;

  @override
  void initState() {
    super.initState();
    _controller = StudioController();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Macro Wheel Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFF),
          brightness: Brightness.dark,
        ),
      ),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (!_controller.isReady) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (_controller.needsFirstRun) {
            return FirstRunWizard(controller: _controller);
          }
          return MainShell(controller: _controller);
        },
      ),
    );
  }
}