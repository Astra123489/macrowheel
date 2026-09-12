import 'package:flutter/material.dart';

import '../../models/configuration.dart';

/// Fixed Resolve page navigation (spec section 19).
///
/// These seven pages are supplied by DaVinci Resolve. Studio has no controls
/// to add, delete, rename, or switch them: selecting a page here only changes
/// the configuration context being edited. It never changes the page that is
/// actually active in Resolve.
class PageSidebar extends StatelessWidget {
  const PageSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  static const Map<String, IconData> _icons = {
    'media': Icons.perm_media_outlined,
    'cut': Icons.content_cut_outlined,
    'edit': Icons.movie_outlined,
    'fusion': Icons.auto_awesome_outlined,
    'color': Icons.color_lens_outlined,
    'fairlight': Icons.graphic_eq,
    'deliver': Icons.rocket_launch_outlined,
  };

  static String labelFor(String page) =>
      page.isEmpty ? page : page[0].toUpperCase() + page.substring(1);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final page in kResolvePages)
          _PageButton(
            page: page,
            icon: _icons[page] ?? Icons.circle_outlined,
            selected: page == selected,
            onTap: () => onSelect(page),
          ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.page,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String page;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color:
                      selected ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
                const SizedBox(height: 4),
                Text(
                  PageSidebar.labelFor(page),
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}