import 'package:flutter/widgets.dart';

import '../services/retail_store.dart';

/// Lets a page accept a search typed into the top bar.
///
/// Two moments matter and only one of them used to be handled. A page opened
/// *by* the search reads the query as it builds — that part always worked. A
/// page that is already on screen when the next search is submitted never
/// rebuilt its state, so its search box sat there with the old text in it and
/// the search appeared to do nothing at all. Listening to the store covers the
/// second case, and addressing the handoff by route ([RetailStore.takeSearchFor])
/// stops one page swallowing a query meant for another.
mixin GlobalSearchTarget<T extends StatefulWidget> on State<T> {
  /// The store carrying the handoff.
  RetailStore get searchStore;

  /// This page's own route, e.g. `/products`. Only searches addressed here are
  /// claimed.
  String get searchRoute;

  /// The page's search box, filled with whatever is claimed.
  TextEditingController get searchField;

  /// Call at the end of `initState`, once [searchField] exists.
  void beginGlobalSearchHandoff() {
    final pending = searchStore.takeSearchFor(searchRoute);
    if (pending.isNotEmpty) searchField.text = pending;
    searchStore.addListener(_adoptGlobalSearch);
  }

  /// Call from `dispose`, before the controller is disposed.
  void endGlobalSearchHandoff() {
    searchStore.removeListener(_adoptGlobalSearch);
  }

  void _adoptGlobalSearch() {
    final query = searchStore.takeSearchFor(searchRoute);
    if (query.isEmpty || !mounted) return;
    setState(() {
      searchField.text = query;
      searchField.selection = TextSelection.collapsed(offset: query.length);
    });
  }
}
