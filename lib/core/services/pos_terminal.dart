/// Talking to the card machine on the counter.
///
/// The shop's Paytm EDC terminal is a separate device that already knows how to
/// take a card or show a UPI QR. What it cannot do on its own is know what the
/// bill came to, and what the till cannot do on its own is know whether the
/// customer actually paid. This is the wire between the two: the till pushes an
/// amount, the customer taps or scans, and the terminal hands back the bank's
/// reference — which then goes on the bill and into the sale row, so a charge
/// disputed three weeks later can be matched to the garment it bought.
///
/// It is deliberately a plain HTTP client with an injectable transport rather
/// than a vendor SDK. Paytm's EDC devices expose a local ordering API on the
/// shop's own network, and every other Indian terminal that supports counter
/// integration exposes something the same shape: POST a JSON order, poll a JSON
/// status. Keeping it at that level means the counter PC needs no driver, the
/// whole flow can be tested without a terminal in the room, and swapping to
/// another vendor is a matter of the two field names below.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Which rail the terminal should present to the customer.
enum PosTenderKind {
  /// Swipe, dip or tap a card.
  card,

  /// Show a UPI QR for the customer to scan.
  upi;

  String get label => this == PosTenderKind.card ? 'Card' : 'UPI QR';
}

/// Where a push to the terminal ended up.
enum PosTerminalOutcome {
  /// The bank approved it. [PosTerminalResult.reference] is filled in.
  approved,

  /// The customer or the cashier backed out at the terminal.
  cancelled,

  /// The bank said no — wrong PIN, no funds, expired card.
  declined,

  /// The terminal never answered: switched off, wrong address, LAN down.
  unreachable,

  /// It answered, but not in time. The safest reading of a timeout is "we do
  /// not know", so the till must not print a paid bill on the strength of it.
  timedOut;

  bool get isApproved => this == PosTerminalOutcome.approved;
}

/// What came back from the machine.
@immutable
class PosTerminalResult {
  const PosTerminalResult({
    required this.outcome,
    required this.message,
    this.reference = '',
    this.terminalId = '',
    this.authCode = '',
    this.cardLast4 = '',
  });

  const PosTerminalResult.approved({
    required this.reference,
    this.terminalId = '',
    this.authCode = '',
    this.cardLast4 = '',
    this.message = 'Payment approved.',
  }) : outcome = PosTerminalOutcome.approved;

  final PosTerminalOutcome outcome;
  final String message;

  /// The bank's own reference — Paytm's transaction ID, the card RRN, the UPI
  /// reference. This is what gets printed and stored.
  final String reference;
  final String terminalId;
  final String authCode;
  final String cardLast4;

  bool get isApproved => outcome.isApproved && reference.trim().isNotEmpty;
}

/// How the counter reaches the terminal.
@immutable
class PosTerminalSettings {
  const PosTerminalSettings({
    this.enabled = false,
    this.host = '',
    this.port = 8080,
    this.merchantId = '',
    this.terminalId = '',
    this.timeoutSeconds = 120,
  });

  /// Off by default. A shop that takes card payments on a standalone machine
  /// and types the reference in by hand is a perfectly normal shop, and this
  /// must not break it.
  final bool enabled;

  /// The terminal's address on the shop's network — an IP, or a hostname.
  final String host;
  final int port;

  /// Paytm's merchant ID (MID) and terminal ID (TID), printed on the machine
  /// and on the merchant agreement.
  final String merchantId;
  final String terminalId;

  /// How long to wait for the customer to finish. Two minutes is the usual
  /// terminal-side limit; the till gives up slightly after the machine does.
  final int timeoutSeconds;

  /// Whether there is enough here to try a push at all.
  bool get isConfigured =>
      enabled && host.trim().isNotEmpty && terminalId.trim().isNotEmpty;

  Duration get timeout => Duration(seconds: timeoutSeconds.clamp(15, 600));

  Uri orderUri() => Uri(
    scheme: 'http',
    host: host.trim(),
    port: port,
    path: '/api/v1/edc/order',
  );

  Uri statusUri(String orderId) => Uri(
    scheme: 'http',
    host: host.trim(),
    port: port,
    path: '/api/v1/edc/status',
    queryParameters: {'orderId': orderId},
  );

  PosTerminalSettings copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? merchantId,
    String? terminalId,
    int? timeoutSeconds,
  }) => PosTerminalSettings(
    enabled: enabled ?? this.enabled,
    host: host ?? this.host,
    port: port ?? this.port,
    merchantId: merchantId ?? this.merchantId,
    terminalId: terminalId ?? this.terminalId,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'host': host,
    'port': port,
    'merchantId': merchantId,
    'terminalId': terminalId,
    'timeoutSeconds': timeoutSeconds,
  };

  factory PosTerminalSettings.fromJson(Map<String, dynamic> json) =>
      PosTerminalSettings(
        enabled: json['enabled'] as bool? ?? false,
        host: (json['host'] as String? ?? '').trim(),
        port: (json['port'] as num?)?.toInt().clamp(1, 65535) ?? 8080,
        merchantId: (json['merchantId'] as String? ?? '').trim(),
        terminalId: (json['terminalId'] as String? ?? '').trim(),
        timeoutSeconds:
            (json['timeoutSeconds'] as num?)?.toInt().clamp(15, 600) ?? 120,
      );

  String encode() => jsonEncode(toJson());

  factory PosTerminalSettings.decode(String json) =>
      PosTerminalSettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

/// One request/response with the terminal, kept behind an interface so the
/// checkout flow can be driven end to end in a test without a card machine.
abstract class PosTerminalTransport {
  /// Whether this build can reach a terminal at all.
  bool get isSupported;

  /// POSTs [body] as JSON and returns the decoded reply, or null when the
  /// device could not be reached.
  Future<Map<String, dynamic>?> post(Uri uri, Map<String, dynamic> body);

  /// GETs [uri] and returns the decoded reply, or null when unreachable.
  Future<Map<String, dynamic>?> get(Uri uri);
}

/// The real one: plain HTTP on the shop's LAN.
class HttpPosTerminalTransport implements PosTerminalTransport {
  HttpPosTerminalTransport({Duration? connectTimeout})
    : _connectTimeout = connectTimeout ?? const Duration(seconds: 8);

  final Duration _connectTimeout;

  @override
  bool get isSupported => !kIsWeb;

  @override
  Future<Map<String, dynamic>?> post(Uri uri, Map<String, dynamic> body) =>
      _send(uri, method: 'POST', body: body);

  @override
  Future<Map<String, dynamic>?> get(Uri uri) => _send(uri, method: 'GET');

  Future<Map<String, dynamic>?> _send(
    Uri uri, {
    required String method,
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final request = method == 'POST'
          ? await client.postUrl(uri)
          : await client.getUrl(uri);
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(_connectTimeout);
      final text = await response.transform(utf8.decoder).join();
      if (text.trim().isEmpty) return const <String, dynamic>{};
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on Object {
      // A terminal that is off, renamed or on another subnet is an everyday
      // event at a counter. It is reported to the cashier as "unreachable",
      // not thrown at them as a stack trace.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// Stands in on platforms with no networking, and when no terminal is set up.
class UnsupportedPosTerminalTransport implements PosTerminalTransport {
  const UnsupportedPosTerminalTransport();

  @override
  bool get isSupported => false;

  @override
  Future<Map<String, dynamic>?> post(
    Uri uri,
    Map<String, dynamic> body,
  ) async => null;

  @override
  Future<Map<String, dynamic>?> get(Uri uri) async => null;
}

/// Pushes an amount at the card machine and waits for the bank's answer.
class PosTerminalService {
  PosTerminalService({PosTerminalTransport? transport, this.pollInterval})
    : transport = transport ?? HttpPosTerminalTransport();

  final PosTerminalTransport transport;

  /// How often to ask the terminal whether the customer has finished. Injected
  /// so a test does not spend two seconds of wall clock per poll.
  final Duration? pollInterval;

  Duration get _poll => pollInterval ?? const Duration(seconds: 2);

  bool get isSupported => transport.isSupported;

  /// Sends [amount] to the terminal for [reference] and waits for it to settle.
  ///
  /// [reference] is the bill number, so the terminal's own printout and the
  /// shop's bill quote the same order. The returned reference is the bank's,
  /// not ours.
  Future<PosTerminalResult> collect({
    required PosTerminalSettings settings,
    required double amount,
    required String reference,
    required PosTenderKind tender,
  }) async {
    if (!settings.isConfigured || !transport.isSupported) {
      return const PosTerminalResult(
        outcome: PosTerminalOutcome.unreachable,
        message:
            'No card machine is set up. Turn the Paytm terminal on under '
            'Hardware, or take the payment on the machine and type its '
            'reference in.',
      );
    }
    if (amount <= 0) {
      return const PosTerminalResult(
        outcome: PosTerminalOutcome.declined,
        message: 'There is nothing to charge.',
      );
    }

    // Paise, not rupees: every Indian payment API counts in the smallest unit,
    // and sending 1234.56 where 123456 was meant overcharges by a hundredfold.
    final paise = (amount * 100).round();
    final opened = await transport.post(settings.orderUri(), {
      'merchantId': settings.merchantId.trim(),
      'terminalId': settings.terminalId.trim(),
      'orderId': reference,
      'amount': paise,
      'currency': 'INR',
      'paymentMode': tender == PosTenderKind.upi ? 'UPI' : 'CARD',
    });

    if (opened == null) {
      return PosTerminalResult(
        outcome: PosTerminalOutcome.unreachable,
        message:
            'The card machine at ${settings.host} did not answer. Check it is '
            'switched on and on the same network.',
      );
    }

    final orderId = (opened['orderId'] as String?)?.trim().isNotEmpty == true
        ? (opened['orderId'] as String).trim()
        : reference;

    // Some terminals settle instantly — a saved card, or a QR the customer had
    // already scanned. Read the opening reply before starting to poll.
    final immediate = _read(opened);
    if (immediate != null) return immediate;

    final deadline = DateTime.now().add(settings.timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_poll);
      final status = await transport.get(settings.statusUri(orderId));
      if (status == null) continue; // A dropped poll is not a failed payment.
      final settled = _read(status);
      if (settled != null) return settled;
    }

    return const PosTerminalResult(
      outcome: PosTerminalOutcome.timedOut,
      message:
          'The card machine did not report back in time. Check the machine '
          'before charging again — the customer may already have paid.',
    );
  }

  /// Reads a terminal reply, or null when it is still in progress.
  ///
  /// Status names differ between firmware revisions, so this matches on the
  /// families rather than on exact strings.
  PosTerminalResult? _read(Map<String, dynamic> reply) {
    final status = (reply['status'] ?? reply['resultStatus'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (status.isEmpty) return null;

    final message = (reply['message'] ?? reply['resultMsg'] ?? '').toString();

    if (status.contains('PENDING') ||
        status.contains('INITIATED') ||
        status.contains('PROGRESS')) {
      return null;
    }
    if (status.contains('SUCCESS') || status.contains('APPROVED')) {
      final reference =
          (reply['txnId'] ??
                  reply['transactionId'] ??
                  reply['rrn'] ??
                  reply['bankTxnId'] ??
                  '')
              .toString()
              .trim();
      if (reference.isEmpty) {
        // Approved with nothing to quote is worse than useless: the money has
        // moved and the bill would carry no way to trace it.
        return const PosTerminalResult(
          outcome: PosTerminalOutcome.timedOut,
          message:
              'The machine approved the payment but sent no reference number. '
              'Read it off the terminal slip and type it in.',
        );
      }
      return PosTerminalResult.approved(
        reference: reference,
        terminalId: (reply['terminalId'] ?? '').toString().trim(),
        authCode: (reply['authCode'] ?? '').toString().trim(),
        cardLast4: (reply['cardLast4'] ?? reply['maskedCard'] ?? '')
            .toString()
            .trim(),
        message: message.isEmpty ? 'Payment approved.' : message,
      );
    }
    if (status.contains('CANCEL') || status.contains('ABORT')) {
      return PosTerminalResult(
        outcome: PosTerminalOutcome.cancelled,
        message: message.isEmpty
            ? 'The payment was cancelled at the machine.'
            : message,
      );
    }
    return PosTerminalResult(
      outcome: PosTerminalOutcome.declined,
      message: message.isEmpty ? 'The bank declined the payment.' : message,
    );
  }
}
