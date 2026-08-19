import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../../core/services/escpos.dart';
import '../../../../core/services/printer_service.dart';
import '../../../../core/services/receipt_logo.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/brand_mark.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../data/invoice_document.dart';
import '../../data/thermal_receipt.dart';

/// What the bill will look like, before it uses any paper.
///
/// The roll preview is not a second layout: it decodes the very ESC/POS bytes
/// that would be sent, so what is on screen and what comes out of the printer
/// cannot drift apart. Changing the paper toggle rebuilds the job at that
/// width, which is how a 58 mm roll shows fewer columns than an 80 mm one.
class BillPreviewDialog extends StatefulWidget {
  const BillPreviewDialog({
    super.key,
    required this.invoice,
    required this.settings,
    this.logo,
    this.onPrint,
  });

  final InvoiceData invoice;
  final PrinterSettings settings;
  final ReceiptLogo? logo;

  /// Prints for real. Null when there is nothing to print to.
  final Future<void> Function(InvoicePaper paper)? onPrint;

  @override
  State<BillPreviewDialog> createState() => _BillPreviewDialogState();
}

class _BillPreviewDialogState extends State<BillPreviewDialog> {
  late InvoicePaper _paper = switch (widget.settings.paper) {
    ThermalPaper.mm58 => InvoicePaper.roll58,
    ThermalPaper.mm80 => InvoicePaper.roll80,
  };
  bool _printing = false;

  ThermalPaper get _roll =>
      _paper == InvoicePaper.roll58 ? ThermalPaper.mm58 : ThermalPaper.mm80;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const Divider(height: 1),
            Flexible(
              child: Container(
                width: double.infinity,
                color: AppColors.bg,
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: SingleChildScrollView(
                  child: Center(
                    child: _paper == InvoicePaper.a4
                        ? _sheetNote(context)
                        : _rollPaper(context),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Icon(
                    widget.settings.isThermal
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 16,
                    color: widget.settings.isThermal
                        ? AppColors.success
                        : AppColors.inkFaint,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.settings.isThermal
                          ? 'Ready to print straight to the roll.'
                          : 'Will open the Windows print dialog.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                  SecondaryButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AccentButton(
                    label: 'Print now',
                    icon: Icons.print_rounded,
                    busy: _printing,
                    onPressed: widget.onPrint == null ? null : _print,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.xl,
      AppSpacing.base,
      AppSpacing.lg,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bill preview',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Exactly what will be printed.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
        SegmentedButton<InvoicePaper>(
          segments: const [
            ButtonSegment(value: InvoicePaper.roll58, label: Text('58 mm')),
            ButtonSegment(value: InvoicePaper.roll80, label: Text('80 mm')),
            ButtonSegment(value: InvoicePaper.a4, label: Text('A4')),
          ],
          selected: {_paper},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _paper = s.first),
        ),
      ],
    ),
  );

  /// The roll, rendered from the real job.
  Widget _rollPaper(BuildContext context) {
    final graphics = <EscPosGraphic>[];
    final job = buildThermalReceipt(
      data: widget.invoice,
      settings: widget.settings.copyWith(paper: _roll),
      logo: widget.logo,
    );
    final text = renderEscPosAsText(job, onGraphic: graphics.add);
    final lines = text.split('\n');

    return Container(
      width: _roll == ThermalPaper.mm58 ? 250 : 340,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [AppColors.panelShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The head of the bill is drawn, so it is drawn here too rather than
          // shown as an empty gap.
          if (widget.settings.printLogoOnReceipt && widget.logo != null) ...[
            const Center(child: BrandMark(size: 46, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final line in lines)
            Text(
              line.isEmpty ? ' ' : line,
              style: AppTypography.receipt.copyWith(
                color: AppColors.ink,
                fontSize: _roll == ThermalPaper.mm58 ? 9.5 : 10.5,
              ),
            ),
          for (final graphic in graphics)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _graphicPlaceholder(context, graphic),
            ),
        ],
      ),
    );
  }

  Widget _graphicPlaceholder(BuildContext context, EscPosGraphic graphic) {
    final (icon, label) = switch (graphic) {
      EscPosGraphic.image => (Icons.image_outlined, 'Shop logo'),
      EscPosGraphic.barcode => (Icons.barcode_reader, 'Bill barcode'),
      EscPosGraphic.qr => (Icons.qr_code_2, 'UPI QR to pay'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderSoft),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: AppColors.ink),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTypography.receipt.copyWith(
              fontSize: 9,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  /// A4 is a laid-out PDF rather than a character grid, so it is shown by the
  /// PDF renderer itself instead of being approximated in text.
  Widget _sheetNote(BuildContext context) => SizedBox(
    width: 400,
    height: 560,
    child: PdfPreview(
      build: (format) =>
          buildInvoicePdf(data: widget.invoice, paper: InvoicePaper.a4),
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      allowPrinting: false,
      allowSharing: false,
      useActions: false,
      scrollViewDecoration: const BoxDecoration(color: AppColors.bg),
    ),
  );

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      await widget.onPrint!(_paper);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }
}
