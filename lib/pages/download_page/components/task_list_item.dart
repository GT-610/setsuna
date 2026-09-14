import 'package:flutter/material.dart';

import '../../../generated/l10n/l10n.dart';
import '../enums.dart';
import '../models/download_task.dart';
import '../services/download_task_service.dart';
import '../utils/task_utils.dart';

enum _TaskMenuAction {
  details,
  pause,
  resume,
  stop,
  retry,
  delete,
  removeFailed,
  openDirectory,
}

class TaskListItem extends StatelessWidget {
  const TaskListItem({
    super.key,
    required this.task,
    required this.instanceNames,
    required this.onTap,
    required this.onSelectionToggle,
    this.onLongPress,
    this.isSelected = false,
    this.showProgressBar = true,
    required this.onTaskUpdated,
    required this.onOpenDirectory,
  });

  final DownloadTask task;
  final Map<String, String> instanceNames;
  final VoidCallback onTap;
  final VoidCallback onSelectionToggle;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool showProgressBar;
  final VoidCallback onTaskUpdated;
  final ValueChanged<DownloadTask> onOpenDirectory;

  String _getInstanceName(BuildContext context, String instanceId) {
    return instanceNames[instanceId] ??
        AppLocalizations.of(context)!.unknownInstance;
  }

  Future<void> _handlePauseTask(BuildContext context) async {
    await DownloadTaskService.pauseTask(context, task, onTaskUpdated);
  }

  Future<void> _handleStopTask(BuildContext context) async {
    await DownloadTaskService.stopTask(context, task, onTaskUpdated);
  }

  Future<void> _handleStopSeedingTask(BuildContext context) async {
    await DownloadTaskService.stopSeedingTask(context, task, onTaskUpdated);
  }

  Future<void> _handleResumeTask(BuildContext context) async {
    await DownloadTaskService.resumeTask(context, task, onTaskUpdated);
  }

  Future<void> _handleRemoveFailedTask(BuildContext context) async {
    await DownloadTaskService.removeFailedTask(context, task, onTaskUpdated);
  }

  Future<void> _handleDeleteTask(BuildContext context) async {
    await DownloadTaskService.stopTask(context, task, onTaskUpdated);
  }

  Future<void> _handleRetryTask(BuildContext context) async {
    await DownloadTaskService.retryTask(context, task, onTaskUpdated);
  }

  bool get _canRetry =>
      (task.uris ?? const <String>[]).any((uri) => uri.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSeeding = DownloadTaskService.isSeedingTask(task);
    final isBtTask =
        task.bittorrentInfo != null && task.bittorrentInfo!.isNotEmpty;
    final (statusText, statusColor) = DownloadTaskService.getStatusInfo(
      context,
      task,
      colorScheme,
    );

    return Card(
      key: ValueKey(task.key),
      margin: const EdgeInsets.only(bottom: 6),
      color: isSelected
          ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
          : colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 9, 8, 9),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useCompactActions = constraints.maxWidth < 540;
              return Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => onSelectionToggle(),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  DownloadTaskService.getStatusIcon(task, statusColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusLabel(label: statusText, color: statusColor),
                          ],
                        ),
                        if (showProgressBar) ...[
                          const SizedBox(height: 7),
                          LinearProgressIndicator(
                            value: task.progress,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            color: statusColor,
                          ),
                        ],
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 14,
                          runSpacing: 5,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Metadata(
                              icon: Icons.dns_outlined,
                              label: _getInstanceName(context, task.instanceId),
                            ),
                            _Metadata(
                              icon: Icons.data_usage_outlined,
                              label:
                                  task.status == DownloadStatus.active &&
                                      !isSeeding
                                  ? '${task.completedSize} / ${task.size} · '
                                        '${TaskUtils.calculateRemainingTime(task)}'
                                  : '${task.completedSize} / ${task.size}',
                            ),
                            if (task.status == DownloadStatus.active)
                              _Metadata(
                                icon: Icons.arrow_upward,
                                label: task.uploadSpeed,
                              ),
                            if (task.status == DownloadStatus.active &&
                                !isSeeding)
                              _Metadata(
                                icon: Icons.arrow_downward,
                                label: task.downloadSpeed,
                                color: colorScheme.primary,
                              ),
                            if (isBtTask)
                              _Metadata(
                                icon: Icons.people_outline,
                                label:
                                    '${task.numSeeders ?? 0} / ${task.connections ?? 0}',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!useCompactActions) ...[
                    ..._buildPrimaryActions(context, isSeeding: isSeeding),
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.openDownloadDir,
                      onPressed: () => onOpenDirectory(task),
                      icon: const Icon(Icons.folder_open_outlined, size: 19),
                    ),
                  ],
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: PopupMenuButton<_TaskMenuAction>(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).moreButtonTooltip,
                      padding: const EdgeInsets.all(6),
                      onSelected: (action) =>
                          _handleMenuAction(context, action),
                      itemBuilder: _buildMenuItems,
                      icon: const Icon(Icons.more_horiz, size: 20),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPrimaryActions(
    BuildContext context, {
    required bool isSeeding,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return switch (task.status) {
      DownloadStatus.active => [
        IconButton(
          tooltip: isSeeding ? l10n.stop : l10n.pause,
          onPressed: () => isSeeding
              ? _handleStopSeedingTask(context)
              : _handlePauseTask(context),
          icon: Icon(
            isSeeding ? Icons.stop_outlined : Icons.pause_outlined,
            size: 19,
          ),
        ),
      ],
      DownloadStatus.waiting => [
        IconButton(
          tooltip: l10n.resume,
          onPressed: () => _handleResumeTask(context),
          icon: const Icon(Icons.play_arrow_outlined, size: 20),
        ),
      ],
      DownloadStatus.stopped => [
        if (_canRetry)
          IconButton(
            tooltip: l10n.retry,
            onPressed: () => _handleRetryTask(context),
            icon: const Icon(Icons.refresh, size: 19),
          ),
      ],
    };
  }

  List<PopupMenuEntry<_TaskMenuAction>> _buildMenuItems(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSeeding = DownloadTaskService.isSeedingTask(task);
    return [
      PopupMenuItem(
        value: _TaskMenuAction.details,
        child: _MenuLabel(icon: Icons.info_outline, label: l10n.taskDetails),
      ),
      if (task.status == DownloadStatus.active && !isSeeding)
        PopupMenuItem(
          value: _TaskMenuAction.pause,
          child: _MenuLabel(icon: Icons.pause_outlined, label: l10n.pause),
        ),
      if (task.status == DownloadStatus.waiting)
        PopupMenuItem(
          value: _TaskMenuAction.resume,
          child: _MenuLabel(
            icon: Icons.play_arrow_outlined,
            label: l10n.resume,
          ),
        ),
      if (task.status != DownloadStatus.stopped)
        PopupMenuItem(
          value: _TaskMenuAction.stop,
          child: _MenuLabel(icon: Icons.stop_outlined, label: l10n.stop),
        ),
      if (task.status == DownloadStatus.stopped && _canRetry)
        PopupMenuItem(
          value: _TaskMenuAction.retry,
          child: _MenuLabel(icon: Icons.refresh, label: l10n.retry),
        ),
      PopupMenuItem(
        value: _TaskMenuAction.openDirectory,
        child: _MenuLabel(
          icon: Icons.folder_open_outlined,
          label: l10n.openDownloadDir,
        ),
      ),
      const PopupMenuDivider(),
      if (task.status == DownloadStatus.stopped &&
          task.taskStatus != 'complete')
        PopupMenuItem(
          value: _TaskMenuAction.removeFailed,
          child: _MenuLabel(
            icon: Icons.delete_outline,
            label: l10n.removeFailedTask,
          ),
        )
      else
        PopupMenuItem(
          value: _TaskMenuAction.delete,
          child: _MenuLabel(icon: Icons.delete_outline, label: l10n.delete),
        ),
    ];
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<_TaskMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: _buildMenuItems(context),
    );
    if (action != null && context.mounted) {
      await _handleMenuAction(context, action);
    }
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    _TaskMenuAction action,
  ) async {
    switch (action) {
      case _TaskMenuAction.details:
        onTap();
        return;
      case _TaskMenuAction.pause:
        await _handlePauseTask(context);
        return;
      case _TaskMenuAction.resume:
        await _handleResumeTask(context);
        return;
      case _TaskMenuAction.stop:
        if (DownloadTaskService.isSeedingTask(task)) {
          await _handleStopSeedingTask(context);
        } else {
          await _handleStopTask(context);
        }
        return;
      case _TaskMenuAction.retry:
        await _handleRetryTask(context);
        return;
      case _TaskMenuAction.delete:
        await _handleDeleteTask(context);
        return;
      case _TaskMenuAction.removeFailed:
        await _handleRemoveFailedTask(context);
        return;
      case _TaskMenuAction.openDirectory:
        onOpenDirectory(task);
        return;
    }
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: foreground),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: foreground),
        ),
      ],
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}
