/// Small, predictable search helpers for back-office screens.
///
/// Enterprise POS/ERP screens usually search as the user types, match partial
/// words, and ignore punctuation/case differences so pasted invoice numbers,
/// phone numbers and SKUs still find the record.
class AppSearch {
  const AppSearch._();

  static bool matches(String haystack, String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return true;

    final normalizedHaystack = _normalize(haystack);
    if (normalizedHaystack.contains(normalizedQuery)) return true;

    final haystackTokens = normalizedHaystack.split(' ');
    return normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .every(
          (queryToken) => haystackTokens.any(
            (haystackToken) => haystackToken.startsWith(queryToken),
          ),
        );
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
