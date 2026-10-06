import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/l10n.dart';
import '../../../services/auto_hide_window_service.dart';
import '../../../utils/logging.dart';

/// Reusable directory picker component.
/// Used to select a save location with both text editing and browsing.
class DirectoryPicker extends StatefulWidget {
  final String initialDirectory;
  final String labelText;
  final String hintText;
  final String dialogTitle;
  final ValueChanged<String> onDirectoryChanged;
  final ValueChanged<String>? onError;

  const DirectoryPicker({
    super.key,
    required this.initialDirectory,
    this.labelText = '',
    this.hintText = '',
    this.dialogTitle = '',
    required this.onDirectoryChanged,
    this.onError,
  });

  @override
  State<DirectoryPicker> createState() => _DirectoryPickerState();
}

class _DirectoryPickerState extends State<DirectoryPicker> with Loggable {
  late final TextEditingController _directoryController;

  @override
  void initState() {
    super.initState();
    _directoryController = TextEditingController(text: widget.initialDirectory);
  }

  @override
  void dispose() {
    _directoryController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DirectoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDirectory != widget.initialDirectory) {
      _setDirectoryText(widget.initialDirectory);
    }
  }

  /// Replaces the field text while keeping a valid caret position.
  ///
  /// The `text` setter resets the selection to an invalid range, which the
  /// focused single-line field then repairs by selecting all of its content.
  /// Writing `value` with an explicit collapsed caret avoids that, and the
  /// equality guard keeps self-inflicted writes from disturbing the selection
  /// the user is editing with.
  void _setDirectoryText(String newDirectory) {
    if (_directoryController.text == newDirectory) {
      return;
    }
    _directoryController.value = TextEditingValue(
      text: newDirectory,
      selection: TextSelection.collapsed(offset: newDirectory.length),
    );
  }

  Future<void> _selectDirectory() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final selectedDirectory = await AutoHideWindowService()
          .runWithSuppressedAutoHide(
            () => FilePicker.platform.getDirectoryPath(
              dialogTitle: widget.dialogTitle.isNotEmpty
                  ? widget.dialogTitle
                  : l10n.chooseSaveLocation,
              initialDirectory: _directoryController.text.isNotEmpty
                  ? _directoryController.text
                  : null,
            ),
          );

      if (selectedDirectory != null) {
        _updateDirectory(selectedDirectory);
      }
    } catch (err) {
      e('Failed to select directory', error: err);
      if (widget.onError != null) {
        widget.onError!(l10n.failedToSelectDirectory('$err'));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToSelectDirectory('$err'))),
        );
      }
    }
  }

  void _updateDirectory(String newDirectory) {
    // The field already holds this text when the user is typing, so only
    // external updates (e.g. a picked directory) need to touch the controller.
    _setDirectoryText(newDirectory);
    widget.onDirectoryChanged(newDirectory);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _directoryController,
            decoration: InputDecoration(
              labelText: widget.labelText.isEmpty ? null : widget.labelText,
              hintText: widget.hintText.isNotEmpty
                  ? widget.hintText
                  : l10n.useInstanceDefaultDirectory,
              border: const OutlineInputBorder(),
            ),
            onChanged: _updateDirectory,
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _selectDirectory,
          child: const Icon(Icons.folder_open),
        ),
      ],
    );
  }
}
