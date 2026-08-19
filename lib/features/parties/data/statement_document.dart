import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/retail_store.dart';
import '../../../core/services/statements.dart';
import '../../../core/utils/formatters.dart';

/// Renders a statement of account onto A4, for handing to a customer chasing
/// what they owe or sending to a supplier to agree the balance.
Future<Uint8List> buildStatementPdf({
  required StatementBundle statement,
  required StoreProfile? profile,
}) async {
  final document = pw.Document();
  final logo = await _loadLogo(profile?.logoPath);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (context) => [
        _header(statement, profile, logo),
        pw.SizedBox(height: 14),
        _partyBlock(statement),
        pw.SizedBox(height: 14),
        _table(statement),
        pw.SizedBox(height: 14),
        _summary(statement),
        pw.SizedBox(height: 24),
        pw.Text(
          'This statement is computer generated. Please report any difference '
          'within 7 days.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  return document.save();
}

Future<pw.MemoryImage?> _loadLogo(String? path) async {
  if (path == null || path.trim().isEmpty) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  return pw.MemoryImage(await file.readAsBytes());
}

pw.Widget _header(
  StatementBundle statement,
  StoreProfile? profile,
  pw.MemoryImage? logo,
) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    if (logo != null)
      pw.Container(
        width: 56,
        height: 56,
        margin: const pw.EdgeInsets.only(right: 12),
        child: pw.Image(logo, fit: pw.BoxFit.contain),
      ),
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            profile?.storeName ?? 'Classy Closet',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          if ((profile?.address ?? '').isNotEmpty)
            pw.Text(profile!.address!, style: const pw.TextStyle(fontSize: 9)),
          if ((profile?.phone ?? '').isNotEmpty)
            pw.Text(
              'Ph: ${profile!.phone!}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          if ((profile?.gstin ?? '').isNotEmpty)
            pw.Text(
              'GSTIN: ${profile!.gstin!}',
              style: const pw.TextStyle(fontSize: 9),
            ),
        ],
      ),
    ),
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          'STATEMENT OF ACCOUNT',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(statement.range.label, style: const pw.TextStyle(fontSize: 9)),
        pw.Text(
          '${AppFormatters.date(statement.range.from)} to '
          '${AppFormatters.date(statement.range.to.subtract(const Duration(days: 1)))}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  ],
);

pw.Widget _partyBlock(StatementBundle statement) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.all(8),
  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        '${statement.kind.label}: ${statement.partyName}',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      if (statement.phone.isNotEmpty)
        pw.Text(
          'Phone: ${statement.phone}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      if (statement.address.isNotEmpty)
        pw.Text(statement.address, style: const pw.TextStyle(fontSize: 9)),
      if (statement.gstin.isNotEmpty)
        pw.Text(
          'GSTIN: ${statement.gstin}',
          style: const pw.TextStyle(fontSize: 9),
        ),
    ],
  ),
);

pw.Widget _table(StatementBundle statement) => pw.TableHelper.fromTextArray(
  headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
  cellStyle: const pw.TextStyle(fontSize: 9),
  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
  cellAlignments: {
    0: pw.Alignment.centerLeft,
    1: pw.Alignment.centerLeft,
    2: pw.Alignment.centerLeft,
    3: pw.Alignment.centerRight,
    4: pw.Alignment.centerRight,
    5: pw.Alignment.centerRight,
  },
  headers: const [
    'Date',
    'Reference',
    'Particulars',
    'Debit',
    'Credit',
    'Balance',
  ],
  data: [
    [
      AppFormatters.date(statement.range.from),
      '',
      'Opening balance',
      '',
      '',
      AppFormatters.amount(statement.openingBalance),
    ],
    for (final line in statement.lines)
      [
        AppFormatters.date(line.date),
        line.reference,
        line.description,
        line.debit == 0 ? '' : AppFormatters.amount(line.debit),
        line.credit == 0 ? '' : AppFormatters.amount(line.credit),
        AppFormatters.amount(line.balance),
      ],
  ],
);

pw.Widget _summary(StatementBundle statement) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.end,
  children: [
    pw.Container(
      width: 240,
      child: pw.Column(
        children: [
          _summaryRow('Total debits', statement.totalDebit),
          _summaryRow('Total credits', statement.totalCredit),
          pw.Divider(height: 8),
          _summaryRow(
            statement.kind.balanceLabel,
            statement.closingBalance,
            bold: true,
          ),
        ],
      ),
    ),
  ],
);

pw.Widget _summaryRow(String label, double value, {bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            AppFormatters.currency(value),
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
