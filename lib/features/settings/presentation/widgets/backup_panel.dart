import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/backup_service.dart';

/// Save the shop's data to a zip, and put it back from one.
class BackupPanel extends StatefulWidget {
  const BackupPanel({required this.service, super.key});

  final BackupService service;

  @override
  State<BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends State<BackupPanel> {
  bool _busy = false;
  BackupResult? _last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A backup holds your sales, products, customers, the shop logo and '
          'every product photo, in one zip file. Keep it somewhere other than '
          'this computer — a pen drive or an external disk.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _backup,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              label: const Text('Back up now'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.settings_backup_restore),
              label: const Text('Restore from a backup'),
            ),
          ],
        ),
        if (_last != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _last!.success
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _last!.success ? Icons.check_circle : Icons.error_outline,
                  color: _last!.success
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _last!.message,
                        style: TextStyle(
                          color: _last!.success
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      if (_last!.success && _last!.path != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SelectableText(
                            _last!.path!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Do this at the end of every trading day. Restoring replaces '
          'everything currently in the app.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _backup() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save RetailPro backup',
      fileName: widget.service.suggestedFileName(),
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (path == null) return;

    setState(() => _busy = true);
    final result = await widget.service.backupTo(
      path.toLowerCase().endsWith('.zip') ? path : '$path.zip',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = result;
    });
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a RetailPro backup',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    // Check the zip before showing a confirmation, so the shopkeeper is not
    // asked to confirm something that was never going to work.
    final check = await widget.service.inspect(path);
    if (!mounted) return;
    if (!check.success) {
      setState(() => _last = check);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything with this backup?'),
        content: const Text(
          'All products, sales and customers currently in the app will be '
          'replaced by what is in the backup file.\n\n'
          'A copy of the current data is kept alongside it first, so this can '
          'be undone.\n\n'
          'You will need to close and reopen RetailPro afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result = await widget.service.restoreFrom(path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = result;
    });
  }
}
