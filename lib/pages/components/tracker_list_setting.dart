import 'package:flutter/material.dart';

import '../../generated/l10n/l10n.dart';
import 'settings_helpers.dart';

class TrackerListSetting extends StatefulWidget {
  const TrackerListSetting({
    super.key,
    required this.title,
    required this.controller,
    this.onChanged,
  });

  final String title;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  State<TrackerListSetting> createState() => _TrackerListSettingState();
}

class _TrackerListSettingState extends State<TrackerListSetting> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  List<String> _parse(String value) => value
      .split(RegExp(r'[,\r\n]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  void _update(List<String> entries) {
    widget.controller.text = entries.join(',');
    widget.onChanged?.call(widget.controller.text);
  }

  void _add() {
    _update(
      {..._parse(widget.controller.text), ..._parse(_input.text)}.toList(),
    );
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: SettingsPageHelpers.kSettingTilePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, child) {
              final entries = _parse(value.text);
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(entries[index]),
                    trailing: IconButton(
                      tooltip: l10n.delete,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _update([...entries]..removeAt(index)),
                    ),
                  ),
                ),
              );
            },
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: l10n.trackerListInputHint,
                  ),
                ),
              ),
              IconButton(
                onPressed: _add,
                tooltip: l10n.add,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
