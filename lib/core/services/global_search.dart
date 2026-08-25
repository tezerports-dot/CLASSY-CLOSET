import '../utils/search.dart';
import 'retail_store.dart';

/// What a hit in the top-bar search points at.
enum GlobalHitKind {
  product('Product'),
  bill('Bill'),
  customer('Customer'),
  supplier('Supplier');

  const GlobalHitKind(this.label);
  final String label;
}

/// One row in the search drop-down.
///
/// [route] is the page that can show the thing, and [query] is what that
/// page's own search box should be filled with to bring it to the top. Keeping
/// both on the hit means the drop-down never has to guess a destination — the
/// thing that was found decides where it lives.
class GlobalHit {
  const GlobalHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.query,
  });

  /// The row shown when nothing matched. It carries no route, so picking it
  /// does nothing — but it is shown rather than swallowed, because a search
  /// box that goes blank on a typo is indistinguishable from a broken one.
  factory GlobalHit.nothingFound(String query) => GlobalHit(
    kind: GlobalHitKind.product,
    title: 'Nothing matches "$query"',
    subtitle: 'Try a barcode, a bill number, or part of a name.',
    route: '',
    query: '',
  );

  final GlobalHitKind kind;
  final String title;
  final String subtitle;

  /// Empty on [GlobalHit.nothingFound]; every real hit has somewhere to go.
  final String route;
  final String query;

  bool get isActionable => route.isNotEmpty;
}

/// Searches everything a shopkeeper might type into the top bar at once.
///
/// The old behaviour was to guess a page from the shape of the query and send
/// the shopkeeper there with the text pre-filled. It never worked in the shop:
/// the guess was "Customers whenever the shop has any customers", and every
/// install has a seeded walk-in from first run, so typing a garment name
/// landed on a customer list with nothing in it. Searching everything and
/// showing what was actually found removes the guess entirely.
///
/// Order is by usefulness, not by table: an exact barcode or bill number is
/// what somebody has just scanned or read off a slip, so it goes first.
List<GlobalHit> searchEverything(
  RetailStore store,
  String raw, {
  int limit = 8,
}) {
  final query = raw.trim();
  if (query.isEmpty) return const [];
  final needle = query.toLowerCase();

  final exact = <GlobalHit>[];
  final rest = <GlobalHit>[];

  for (final product in store.products) {
    final haystack =
        '${product.sku} ${product.name} ${product.barcode} '
        '${product.size} ${product.color} ${product.category} ${product.brand}';
    if (!AppSearch.matches(haystack, query)) continue;
    final code = product.barcode.trim().isEmpty
        ? product.sku
        : product.barcode.trim();
    final hit = GlobalHit(
      kind: GlobalHitKind.product,
      title: product.displayName,
      subtitle: '$code · ${product.stock.round()} in stock',
      route: '/products',
      // The code, not the typed text: it is unique, so the products page
      // lands on exactly this unit rather than everything sharing a word.
      query: code,
    );
    final isExact =
        product.barcode.trim().toLowerCase() == needle ||
        product.sku.toLowerCase() == needle;
    (isExact ? exact : rest).add(hit);
  }

  for (final sale in store.sales) {
    if (!AppSearch.matches('${sale.receipt} ${sale.customerName}', query)) {
      continue;
    }
    final hit = GlobalHit(
      kind: GlobalHitKind.bill,
      title: sale.receipt,
      subtitle: sale.customerName,
      route: '/sales',
      query: sale.receipt,
    );
    (sale.receipt.toLowerCase() == needle ? exact : rest).add(hit);
  }

  for (final customer in store.customers) {
    if (!AppSearch.matches(
      '${customer.name} ${customer.phone} ${customer.email}',
      query,
    )) {
      continue;
    }
    final hit = GlobalHit(
      kind: GlobalHitKind.customer,
      title: customer.name,
      subtitle: customer.phone.isEmpty ? 'No number on file' : customer.phone,
      route: '/customers',
      query: customer.phone.isEmpty ? customer.name : customer.phone,
    );
    (customer.phone.toLowerCase() == needle ? exact : rest).add(hit);
  }

  for (final supplier in store.suppliers) {
    if (!AppSearch.matches('${supplier.name} ${supplier.phone}', query)) {
      continue;
    }
    rest.add(
      GlobalHit(
        kind: GlobalHitKind.supplier,
        title: supplier.name,
        subtitle: supplier.phone.isEmpty ? 'Supplier' : supplier.phone,
        route: '/suppliers',
        query: supplier.name,
      ),
    );
  }

  final hits = [...exact, ...rest].take(limit).toList();
  return hits.isEmpty ? [GlobalHit.nothingFound(query)] : hits;
}
