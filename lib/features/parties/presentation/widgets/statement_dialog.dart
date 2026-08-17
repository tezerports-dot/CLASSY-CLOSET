import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/services/reports.dart';
import '../../../../core/services/retail_store.dart';
import '../../../../core/services/statements.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/statement_document.dart';

/// Shows a party's account over a period, and gets it onto paper or into a
/// spreadsheet.
class StatementDialog extends StatefulWidget {
  const StatementDialog({
    super.key,
    required this.store,
    required this.kind,
    required this.partyId,
    required this.partyName,
  });

  final RetailStore store;
  final PartyKind kind;
  final int partyId;
  final String partyName;

  @override
  State<StatementDialog> createState() => _StatementDialogState();
}

class _StatementDialogState extends State<StatementDialog> {
  final _ranges = <DateRange>[
    DateRange.thisMonth(),
    DateRange.lastMonth(),
    DateRange.thisFinancialYear(),
  ];
  late DateRange _range = _ranges.last;
  StatementBundle? _statement;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statement = await widget.store.buildStatement(
        kind: widget.kind,
        partyId: widget.partyId,
        range: _range,
      );
      if (!mounted) return;
      setState(() {
        _statement = statement;
        _loading = false;
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;

    return AlertDialog(
      title: Text('Statement — ${widget.partyName}'),
      content: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<DateRange>(
              initialValue: _range,
              decoration: const InputDecoration(labelText: 'Period'),
              items: [
                for (final range in _ranges)
                  DropdownMenuItem(value: range, child: Text(range.label)),
              ],
              onChanged: (range) {
                if (range == null) return;
                setState(() => _range = range);
                _load();
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    )
                  : _body(statement!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: statement == null ? null : () => _exportCsv(statement),
          icon: const Icon(Icons.download),
          label: const Text('Save as CSV'),
        ),
        FilledButton.icon(
          onPressed: statement == null ? null : () => _print(statement),
          icon: const Icon(Icons.print),
          label: const Text('Print'),
        ),
      ],
    );
  }

  Widget _body(StatementBundle statement) {
    if (statement.isEmpty) {
      return Center(
        child: Text(
          'Nothing moved on this account during ${statement.range.label}. '
          'The balance stands at '
          '${AppFormatters.currency(statement.closingBalance)}.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Reference')),
                DataColumn(label: Text('Particulars')),
                DataColumn(label: Text('Debit'), numeric: true),
                DataColumn(label: Text('Credit'), numeric: true),
                DataColumn(label: Text('Balance'), numeric: true),
              ],
              rows: [
                DataRow(
                  cells: [
                    DataCell(Text(AppFormatters.date(statement.range.from))),
                    const DataCell(Text('')),
                    const DataCell(Text('Opening balance')),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(
                      Text(AppFormatters.amount(statement.openingBalance)),
                    ),
                  ],
                ),
                for (final line in statement.lines)
                  DataRow(
                    cells: [
                      DataCell(Text(AppFormatters.date(line.date))),
                      DataCell(Text(line.reference)),
                      DataCell(Text(line.description)),
                      DataCell(
                        Text(
                          line.debit == 0
                              ? ''
                              : AppFormatters.amount(line.debit),
                        ),
                      ),
                      DataCell(
                        Text(
                          line.credit == 0
                              ? ''
                              : AppFormatters.amount(line.credit),
                        ),
                      ),
                      DataCell(Text(AppFormatters.amount(line.balance))),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${statement.kind.balanceLabel}: '
              '${AppFormatters.currency(statement.closingBalance)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _print(StatementBundle statement) async {
    final bytes = await buildStatementPdf(
      statement: statement,
      profile: widget.store.storeProfile,
    );
    await Printing.layoutPdf(
      name: 'Statement ${statement.partyName}',
      onLayout: (_) => bytes,
    );
  }

  Future<void> _exportCsv(StatementBundle statement) async {
    final safeName = statement.partyName.replaceAll(RegExp(r'[^\w\s-]'), '');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save the statement',
      fileName: 'statement-$safeName.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path == null) return;
    // Excel needs the byte-order mark to read the file as UTF-8; without it
    // the rupee sign arrives as mojibake.
    await File(path).writeAsString('﻿${statement.csv()}');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved to $path')));
  }
}
