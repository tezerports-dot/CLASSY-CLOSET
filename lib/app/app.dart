import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class RetailProApp extends StatelessWidget {
  const RetailProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RetailPro POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
    );
  }
}
