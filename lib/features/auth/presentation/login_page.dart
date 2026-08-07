import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/di/injection.dart';
import '../../../core/services/retail_store.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _store = getIt<RetailStore>();
  final _username = TextEditingController(text: 'admin');
  final _password = TextEditingController(text: 'admin123');
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_store.storeProfile?.logoPath != null && File(_store.storeProfile!.logoPath!).existsSync()) ...[
                    Image.file(File(_store.storeProfile!.logoPath!), height: 72),
                    const SizedBox(height: 16),
                  ],
                  Text('${_store.displayStoreName} Login', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text('Offline admin access seeded on first run.'),
                  const SizedBox(height: 24),
                  TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
                  const SizedBox(height: 12),
                  TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _submit, child: const Text('Sign in')),
                  const SizedBox(height: 12),
                  const Text('Demo credentials: admin / admin123'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final ok = await _store.login(_username.text, _password.text);
    if (!ok && mounted) {
      setState(() => _error = 'Invalid username or password');
    }
  }
}
