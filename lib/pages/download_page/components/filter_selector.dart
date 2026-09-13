import 'package:flutter/material.dart';

import '../../../generated/l10n/l10n.dart';
import '../enums.dart';

class FilterSelector extends StatelessWidget {
  const FilterSelector({
    super.key,
    required this.currentCategoryType,
    required this.selectedFilter,
    required this.selectedInstanceId,
    required this.instanceNames,
    required this.instanceIds,
    required this.onCategoryChanged,
    required this.onFilterChanged,
    required this.onInstanceSelected,
  });

  final CategoryType currentCategoryType;
  final FilterOption selectedFilter;
  final String? selectedInstanceId;
  final Map<String, String> instanceNames;
  final List<String> instanceIds;
  final ValueChanged<CategoryType> onCategoryChanged;
  final ValueChanged<FilterOption> onFilterChanged;
  final ValueChanged<String?> onInstanceSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 190,
      child: ColoredBox(
        color: colorScheme.surfaceContainerLowest,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
          children: [
            _FilterItem(
              icon: Icons.inbox_outlined,
              label: l10n.allTasksLabel,
              selected: currentCategoryType == CategoryType.all,
              onTap: () => onCategoryChanged(CategoryType.all),
            ),
            _FilterSectionLabel(label: l10n.byStatus),
            _FilterItem(
              icon: Icons.downloading_outlined,
              label: l10n.downloading,
              selected:
                  currentCategoryType == CategoryType.byStatus &&
                  selectedFilter == FilterOption.active,
              onTap: () =>
                  _selectFilter(CategoryType.byStatus, FilterOption.active),
            ),
            _FilterItem(
              icon: Icons.schedule_outlined,
              label: l10n.waiting,
              selected:
                  currentCategoryType == CategoryType.byStatus &&
                  selectedFilter == FilterOption.waiting,
              onTap: () =>
                  _selectFilter(CategoryType.byStatus, FilterOption.waiting),
            ),
            _FilterItem(
              icon: Icons.task_alt_outlined,
              label: l10n.stoppedCompleted,
              selected:
                  currentCategoryType == CategoryType.byStatus &&
                  selectedFilter == FilterOption.stopped,
              onTap: () =>
                  _selectFilter(CategoryType.byStatus, FilterOption.stopped),
            ),
            _FilterSectionLabel(label: l10n.byType),
            _FilterItem(
              icon: Icons.computer_outlined,
              label: l10n.builtin,
              selected:
                  currentCategoryType == CategoryType.byType &&
                  selectedFilter == FilterOption.local,
              onTap: () =>
                  _selectFilter(CategoryType.byType, FilterOption.local),
            ),
            _FilterItem(
              icon: Icons.cloud_outlined,
              label: l10n.remote,
              selected:
                  currentCategoryType == CategoryType.byType &&
                  selectedFilter == FilterOption.remote,
              onTap: () =>
                  _selectFilter(CategoryType.byType, FilterOption.remote),
            ),
            _FilterSectionLabel(label: l10n.byInstance),
            _FilterItem(
              icon: Icons.dns_outlined,
              label: l10n.allInstances,
              selected:
                  currentCategoryType == CategoryType.byInstance &&
                  selectedInstanceId == null,
              onTap: () => _selectInstance(null),
            ),
            ...instanceIds.map((instanceId) {
              final name = instanceNames[instanceId] ?? l10n.unknownInstance;
              return _FilterItem(
                icon: Icons.circle,
                iconSize: 8,
                label: name,
                tooltip: name,
                selected:
                    currentCategoryType == CategoryType.byInstance &&
                    selectedInstanceId == instanceId,
                onTap: () => _selectInstance(instanceId),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _selectFilter(CategoryType category, FilterOption filter) {
    if (currentCategoryType != category) {
      onCategoryChanged(category);
    }
    onFilterChanged(filter);
  }

  void _selectInstance(String? instanceId) {
    if (currentCategoryType != CategoryType.byInstance) {
      onCategoryChanged(CategoryType.byInstance);
    }
    onInstanceSelected(instanceId);
  }
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 5),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FilterItem extends StatelessWidget {
  const _FilterItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconSize = 18,
    this.tooltip,
  });

  final IconData icon;
  final double iconSize;
  final String label;
  final String? tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final item = Material(
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Icon(icon, size: iconSize, color: foreground),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip == null) {
      return item;
    }
    return Tooltip(message: tooltip!, child: item);
  }
}
