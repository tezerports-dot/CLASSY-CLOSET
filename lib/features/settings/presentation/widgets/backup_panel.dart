import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Directory? _dataFolder;

  @override
  void initState() {
    super.initState();
    widget.service.dataDirectory().then((folder) {
      if (mounted) setState(() => _dataFolder = folder);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The app now keeps live Excel and automatic zip backups in Documents '
          'while it is open. The zip backup holds your database, shop logo and '
          'product photos in one file, so a reinstall or app update can be '
          'restored from that folder.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _dataFolderCard(theme),
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
            OutlinedButton.icon(
              onPressed: _busy ? null : _excelBackupNow,
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text('Update Excel now'),
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
          'Excel files are saved under Documents/Classy Closet Automatic Excel '
          'Backup. Automatic restore zip files are saved under Documents/Classy '
          'Closet Automatic Zip Backup. Keep the Documents folder or sync it '
          'with OneDrive/Google Drive if this PC is replaced.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Names where the shop's data actually lives.
  ///
  /// It sits outside the program folder, so uninstalling Classy Closet does
  /// not touch it — which is why an upgrade keeps the staff logins, the
  /// settings and the books, and why reinstalling is not a way to start over.
  /// That surprises people, so it is written down here rather than left to be
  /// discovered.
  Widget _dataFolderCard(ThemeData theme) {
    final path = _dataFolder?.path;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_outlined, size: 16),
              const SizedBox(width: 8),
              Text(
                'Where your shop data lives',
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              if (path != null)
                TextButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: path));
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Folder path copied.')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            path ?? 'Working it out…',
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 6),
          Text(
            'This folder is outside the program folder, so uninstalling does '
            'not delete it — an update keeps your logins, settings and books. '
            'Reinstalling is therefore not a way to start fresh: use '
            'Settings → Reset for that.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _backup() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Classy Closet backup',
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

  Future<void> _excelBackupNow() async {
    setState(() => _busy = true);
    final result = await widget.service.writeAutomaticExcelBackup();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = result;
    });
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a Classy Closet backup',
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
          'You will need to close and reopen Classy Closet afterwards.',
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
