import 'package:flutter/material.dart';

class DesktopPageHeader extends StatelessWidget {
  const DesktopPageHeader({
    super.key,
    required this.title,
    this.actions = const [],
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 16),
            ..._separateActions(actions),
          ],
        ],
      ),
    );
  }

  List<Widget> _separateActions(List<Widget> widgets) {
    return [
      for (var index = 0; index < widgets.length; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        widgets[index],
      ],
    ];
  }
}
