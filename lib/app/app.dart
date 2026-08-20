import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/services/retail_store.dart';
import '../core/theme/app_theme.dart';
import 'di/injection.dart';
import 'router.dart';

class WhiteLabelPosApp extends StatefulWidget {
  const WhiteLabelPosApp({super.key});

  @override
  State<WhiteLabelPosApp> createState() => _WhiteLabelPosAppState();
}

class _WhiteLabelPosAppState extends State<WhiteLabelPosApp> {
  late final RetailStore _store;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _store = getIt<RetailStore>();
    _router = createAppRouter(_store);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) => MaterialApp.router(
        builder: (context, child) => SelectionArea(
          child: child ?? const SizedBox(),
        ),
        title: '${_store.displayStoreName} POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: _router,
      ),
    );
  }
}
