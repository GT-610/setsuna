import 'package:flutter/material.dart';

import '../../../generated/l10n/l10n.dart';
import '../enums.dart';

class TaskToolbar extends StatelessWidget {
  const TaskToolbar({
    super.key,
    required this.onAddTask,
    required this.onPauseAll,
    required this.onResumeAll,
    required this.onDeleteAll,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.sortOption,
    required this.sortDescending,
    required this.onSortChanged,
    required this.onSortDirectionChanged,
  });

  final VoidCallback onAddTask;
  final VoidCallback? onPauseAll;
  final VoidCallback? onResumeAll;
  final VoidCallback? onDeleteAll;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final TaskSortOption sortOption;
  final bool sortDescending;
  final ValueChanged<TaskSortOption> onSortChanged;
  final ValueChanged<bool> onSortDirectionChanged;

  String _sortLabel(AppLocalizations l10n, TaskSortOption option) {
    return switch (option) {
      TaskSortOption.name => l10n.name,
      TaskSortOption.progress => l10n.progress,
      TaskSortOption.size => l10n.size,
      TaskSortOption.speed => l10n.speed,
      TaskSortOption.instance => l10n.instance,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: onAddTask,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.addTask),
          ),
          const SizedBox(width: 6),
          _ToolbarIconButton(
            tooltip: l10n.pauseAll,
            icon: Icons.pause_outlined,
            onPressed: onPauseAll,
          ),
          _ToolbarIconButton(
            tooltip: l10n.resumeAll,
            icon: Icons.play_arrow_outlined,
            onPressed: onResumeAll,
          ),
          _ToolbarIconButton(
            tooltip: l10n.deleteAll,
            icon: Icons.delete_outline,
            onPressed: onDeleteAll,
            foregroundColor: colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TextField(
                key: const ValueKey('task-search-field'),
                controller: searchController,
                focusNode: searchFocusNode,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 19),
                  prefixIconConstraints: const BoxConstraints(minWidth: 38),
                  hintText: l10n.searchTasksHint,
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.clear,
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                            searchFocusNode.requestFocus();
                          },
                          icon: const Icon(Icons.close, size: 17),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<TaskSortOption>(
            tooltip: '${l10n.sortTasks}: ${_sortLabel(l10n, sortOption)}',
            onSelected: onSortChanged,
            itemBuilder: (context) => TaskSortOption.values
                .map(
                  (option) => PopupMenuItem<TaskSortOption>(
                    value: option,
                    child: Row(
                      children: [
                        Icon(
                          option == sortOption ? Icons.check : null,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(_sortLabel(l10n, option)),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
            child: _ToolbarButtonSurface(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _sortLabel(l10n, sortOption),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          _ToolbarIconButton(
            tooltip: sortDescending ? l10n.descending : l10n.ascending,
            icon: sortDescending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            onPressed: () => onSortDirectionChanged(!sortDescending),
          ),
        ],
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: foregroundColor,
      icon: Icon(icon, size: 20),
    );
  }
}

class _ToolbarButtonSurface extends StatelessWidget {
  const _ToolbarButtonSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 150, minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
