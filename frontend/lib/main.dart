/// Platform — the walking skeleton.
///
/// This screen exists to prove one thing: that a browser reaches the Flutter
/// app, the app reaches the API, and the API reaches Postgres. It asks
/// `/api/health` and shows what came back.
///
/// The URL is relative on purpose. The reverse proxy serves the app and the API
/// from one hostname, splitting on `/api`, so the browser sees a single origin
/// and there is no CORS to configure. That also means one build runs in every
/// environment: nothing here knows the API's address, so nothing has to be
/// rebuilt to move it.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const PlatformApp());
}

class PlatformApp extends StatelessWidget {
  const PlatformApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Platform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F172A)),
        useMaterial3: true,
      ),
      home: const HealthScreen(),
    );
  }
}

/// What the API said when we last asked.
sealed class HealthState {
  const HealthState();
}

class HealthChecking extends HealthState {
  const HealthChecking();
}

class HealthOk extends HealthState {
  const HealthOk(this.answer);

  /// The value the database returned. Carrying it through, rather than trusting
  /// a bare "ok", is what makes this a test of the whole path.
  final int answer;
}

class HealthFailed extends HealthState {
  const HealthFailed(this.reason);

  final String reason;
}

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  HealthState _state = const HealthChecking();

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _state = const HealthChecking());

    try {
      final response = await http.get(Uri.parse('/api/health'));

      if (response.statusCode != 200) {
        _settle(HealthFailed('The API answered ${response.statusCode}.'));
        return;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final answer = body['answer'];

      if (answer is! int) {
        // A 200 with nothing from the database in it means the API is up but
        // the path behind it is not, which is worth distinguishing from a
        // failure to reach the API at all.
        _settle(const HealthFailed('The API answered, but without a value from the database.'));
        return;
      }

      _settle(HealthOk(answer));
    } catch (error) {
      _settle(HealthFailed('Could not reach the API: $error'));
    }
  }

  void _settle(HealthState state) {
    if (!mounted) return;
    setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusCard(state: _state),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _state is HealthChecking ? null : _check,
                  child: const Text('Check again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final HealthState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (IconData icon, Color colour, String headline, String detail) = switch (state) {
      HealthChecking() => (
        Icons.hourglass_empty,
        theme.colorScheme.outline,
        'Checking',
        'Asking the API whether it can reach the database.',
      ),
      HealthOk(answer: final answer) => (
        Icons.check_circle_outline,
        Colors.green.shade700,
        'Connected',
        'The browser reached the app, the app reached the API, and the database '
            'answered with $answer.',
      ),
      HealthFailed(reason: final reason) => (
        Icons.error_outline,
        theme.colorScheme.error,
        'Not connected',
        reason,
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 48, color: colour),
            const SizedBox(height: 12),
            Text(headline, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
