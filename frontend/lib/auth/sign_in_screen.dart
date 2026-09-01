/// Sign up and sign in — password, and Google — against Supabase Auth
/// directly. There is no backend involved here at all: the API never sees a
/// password (ADR-0002), it only ever verifies the session Supabase issues.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await action();
      // On success the app moves on via AuthGate's own auth-state
      // listener — nothing to navigate to here.
    } on AuthException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Something went wrong: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      () => Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      () => Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    // On Flutter Web this navigates the browser to Google and back via
    // Supabase's own redirect — there is no separate "callback screen" to
    // build: the app reloads at this same URL with a session already
    // established, and AuthGate's listener picks it up like any other sign
    // -in.
    await _run(() => Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (value) =>
                        (value == null || !value.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: (value) =>
                        (value == null || value.length < 6) ? 'At least 6 characters' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _signIn,
                    child: const Text('Sign in'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _submitting ? null : _signUp,
                    child: const Text('Create an account'),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _signInWithGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text('Continue with Google'),
                  ),
                  if (_submitting) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
