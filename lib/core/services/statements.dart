import '../utils/formatters.dart';
import 'reports.dart';

/// Which side of the ledger a party sits on.
enum PartyKind {
  customer,
  supplier;

  String get label => this == PartyKind.customer ? 'Customer' : 'Supplier';

  /// What the column of money owed to the shop is called for this party.
  /// A customer owes the shop; the shop owes a supplier.
  String get balanceLabel =>
      this == PartyKind.customer ? 'Owed to the shop' : 'Owed by the shop';
}

/// How money changed hands.
enum PaymentMethod {
  cash('Cash'),
  card('Card'),
  upi('UPI'),
  bank('Bank transfer'),
  cheque('Cheque');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod fromName(String? name) => PaymentMethod.values
      .firstWhere((m) => m.name == name, orElse: () => PaymentMethod.cash);
}

/// One settled amount against a party's balance.
class PartyPaymentRecord {
  const PartyPaymentRecord({
    required this.id,
    required this.kind,
    required this.partyId,
    required this.partyName,
    required this.reference,
    required this.amount,
    required this.method,
    required this.paidAt,
    this.notes = '',
    this.userName = '',
  });

  final int id;
  final PartyKind kind;
  final int partyId;
  final String partyName;
  final String reference;
  final double amount;
  final PaymentMethod method;
  final DateTime paidAt;
  final String notes;
  final String userName;
}

/// One line of a statement of account.
///
/// [debit] is what increases the balance owed — a credit sale to a customer, a
/// delivery from a supplier — and [credit] is what settles it. Keeping both
/// columns rather than one signed number is what makes the printed statement
/// look like the ledger a shopkeeper already reads.
class StatementLine {
  const StatementLine({
    required this.date,
    required this.reference,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final DateTime date;
  final String reference;
  final String description;
  final double debit;
  final double credit;

  /// Running balance after this line.
  final double balance;
}

/// A party's account over a period, ready to print or export.
class StatementBundle {
  const StatementBundle({
    required this.kind,
    required this.partyId,
    required this.partyName,
    required this.range,
    required this.openingBalance,
    required this.lines,
    this.phone = '',
    this.address = '',
    this.gstin = '',
  });

  final PartyKind kind;
  final int partyId;
  final String partyName;
  final DateRange range;

  /// Balance carried in at the start of [range].
  final double openingBalance;
  final List<StatementLine> lines;
  final String phone;
  final String address;
  final String gstin;

  double get closingBalance =>
      lines.isEmpty ? openingBalance : lines.last.balance;
  double get totalDebit => lines.fold(0.0, (sum, l) => sum + l.debit);
  double get totalCredit => lines.fold(0.0, (sum, l) => sum + l.credit);
  bool get isEmpty => lines.isEmpty;

  /// Spreadsheet form of the same statement.
  String csv() => toCsv(
    const ['Date', 'Reference', 'Description', 'Debit', 'Credit', 'Balance'],
    [
      [
        AppFormatters.date(range.from),
        '',
        'Opening balance',
        '',
        '',
        openingBalance.toStringAsFixed(2),
      ],
      for (final line in lines)
        [
          AppFormatters.date(line.date),
          line.reference,
          line.description,
          line.debit == 0 ? '' : line.debit.toStringAsFixed(2),
          line.credit == 0 ? '' : line.credit.toStringAsFixed(2),
          line.balance.toStringAsFixed(2),
        ],
      [
        AppFormatters.date(range.to.subtract(const Duration(days: 1))),
        '',
        'Closing balance',
        totalDebit.toStringAsFixed(2),
        totalCredit.toStringAsFixed(2),
        closingBalance.toStringAsFixed(2),
      ],
    ],
  );
}

/// Builds the running balance down a list of movements.
///
/// Kept separate from the database read so the arithmetic — the part that is
/// actually easy to get wrong — can be tested on its own.
List<StatementLine> runningBalance(
  double openingBalance,
  List<StatementMovement> movements,
) {
  final sorted = [...movements]..sort((a, b) => a.date.compareTo(b.date));
  var balance = openingBalance;
  return [
    for (final movement in sorted)
      () {
        balance += movement.debit - movement.credit;
        return StatementLine(
          date: movement.date,
          reference: movement.reference,
          description: movement.description,
          debit: movement.debit,
          credit: movement.credit,
          balance: _round(balance),
        );
      }(),
  ];
}

/// A movement before the running balance has been worked out.
class StatementMovement {
  const StatementMovement({
    required this.date,
    required this.reference,
    required this.description,
    this.debit = 0,
    this.credit = 0,
  });

  final DateTime date;
  final String reference;
  final String description;
  final double debit;
  final double credit;
}

double _round(double value) => (value * 100).round() / 100;
