/// Sign up and sign in — password, and Google — through whichever
/// [AuthGateway] the deployment runs on. Against Supabase Auth there is no
/// backend involved at all: the API never sees a password (ADR-0002), it only
/// ever verifies the session Supabase issues. Against the API's own sign-in
/// (issue #269) the gateway posts the password to the API, and what the API
/// refuses with is shown verbatim as an [AuthRefusal].
///
/// **The front door has an identity (issue #375).** It used to be an `AppBar`
/// reading "Platform" over a 400px column floating on an empty canvas. At
/// [SignInScreen.twoPanelWidth] and wider it is now two panels: an identity
/// panel (the wordmark, one sentence, and what the Platform contains in
/// CONTEXT.md's own words), tinted with [AppPalette.surfaceMuted] and edged by a
/// hairline, and the form in a card centred on the canvas. Below it the panel
/// collapses to a compact brand header above the same card. Nothing about the
/// form moved: the same `Form`, validators, [AuthGateway] calls and error
/// placement. There is no gradient, photograph, customer logo or statistic —
/// the panel says only what is true of the Platform.
///
/// **The front door carries the palette switch (issue #415).** The dark palette
/// has existed since #366, but its only control was inside the Shell's account
/// menu — and sign-in is drawn outside the Shell, so the page the site opens on
/// offered no way to change it. The same [PaletteToggle] the Shell's footer now
/// draws sits in this Screen's heading row, above the form. The Screen still
/// decides nothing: [darkPalette] and [onToggleDarkPalette] are handed in by
/// the router, which is where `ThemeMode.system` meets the browser's own
/// preference.
///
/// The width is read from the box this Screen is laid out in
/// (`LayoutBuilder`), not the window, the way every other responsive Screen
/// here reads it; there is no Shell around sign-in to take a share of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../platform/auth_gateway.dart';
import '../theme.dart';
import '../widgets/app_form_submit.dart';
import '../widgets/palette_toggle.dart';
import 'auth_error_messages.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.darkPalette,
    required this.onToggleDarkPalette,
  });

  /// Whether the dark palette is the one on screen, so [PaletteToggle] can name
  /// the other one (issue #415).
  final bool darkPalette;

  /// Switches to the other palette. The Screen decides nothing about which.
  final VoidCallback onToggleDarkPalette;

  /// The width at which the identity panel appears beside the form.
  static const double twoPanelWidth = 900;

  static const ValueKey<String> identityPanelKey = ValueKey<String>('sign-in-identity-panel');
  static const ValueKey<String> compactBrandKey = ValueKey<String>('sign-in-compact-brand');
  static const ValueKey<String> formCardKey = ValueKey<String>('sign-in-form-card');

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

/// The least height a touch target may have on this Screen. The theme sets no
/// button `minimumSize` and Material 3's own is 40, so the three buttons ask
/// for it here; `style` merges over the theme's, so its focus overlay and ring
/// are untouched.
const double _touchTarget = 44;

/// What the Platform contains, in CONTEXT.md's words, with each one's icon from
/// the Destination that carries it.
const List<(IconData, String)> _contents = [
  (Icons.build_outlined, 'Work orders'),
  (Icons.fact_check_outlined, 'KPI Review'),
  (Icons.swap_horiz_outlined, 'Shift handover'),
  (Icons.assignment_turned_in_outlined, 'Actions'),
];

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
      // On success the app moves on via AccountBloc's own access-token
      // listener — nothing to navigate to here.
    } on AuthRefusal catch (error) {
      setState(() => _error = error.message);
    } on AuthException catch (error) {
      setState(() => _error = authErrorMessage(error));
    } catch (error) {
      setState(() => _error = 'Something went wrong: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      () => context.read<AuthGateway>().signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(
      () => context.read<AuthGateway>().signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    // On Flutter Web this navigates the browser to Google and back via
    // Supabase's own redirect — there is no separate "callback screen" to
    // build: the app reloads at this same URL with a session already
    // established, and AccountBloc's listener picks it up like any other
    // sign-in.
    await _run(() => context.read<AuthGateway>().signInWithGoogle());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= SignInScreen.twoPanelWidth) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(flex: 2, child: _IdentityPanel()),
                Expanded(
                  flex: 3,
                  child: _Scrolling(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: _formCard(context, padding: Spacing.xl),
                  ),
                ),
              ],
            );
          }
          // Compact: the brand over the card, scrolling when it does not fit
          // and centred when it does. The padding is small so 320px has room.
          return _Scrolling(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Wordmark(key: SignInScreen.compactBrandKey, centered: true),
                const SizedBox(height: Spacing.lg),
                _formCard(context, padding: Spacing.lg),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _formCard(BuildContext context, {required double padding}) {
    return Center(
      child: ConstrainedBox(
        // 400 is one of the two centred-card widths `layout_rules_test.dart`
        // allows a Screen to state.
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          key: SignInScreen.formCardKey,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: _form(context),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    const buttonSize = Size.fromHeight(_touchTarget);
    // `Enter` in either field signs in (issue #401): the form's primary
    // action is the one a reader has typed toward, and the rule lives in the
    // one widget every form on the Platform shares. Null while a request is
    // in flight, the same null the button's own `onPressed` carries.
    return AppFormSubmit(
      onSubmit: _submitting ? null : _signIn,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A real heading to a screen reader, not just larger text. The
            // palette switch rides in the same row (issue #415): the one control
            // this Screen owns that is not part of signing in, and in reach
            // whether or not the form has been filled in.
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
                  ),
                ),
                PaletteToggle(
                  darkPalette: widget.darkPalette,
                  onPressed: widget.onToggleDarkPalette,
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (value) =>
                  (value == null || !value.contains('@')) ? 'Enter a valid email' : null,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              validator: (value) =>
                  (value == null || value.length < 6) ? 'At least 6 characters' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: Spacing.md),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: Spacing.lg),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: buttonSize),
              onPressed: _submitting ? null : _signIn,
              child: const Text('Sign in'),
            ),
            const SizedBox(height: Spacing.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: buttonSize),
              onPressed: _submitting ? null : _signUp,
              child: const Text('Create an account'),
            ),
            const SizedBox(height: Spacing.md),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.sm),
                  child: Text('or'),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: Spacing.md),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: buttonSize),
              onPressed: _submitting ? null : _signInWithGoogle,
              icon: const Icon(Icons.login),
              label: const Text('Continue with Google'),
            ),
            if (_submitting) ...[
              const SizedBox(height: Spacing.md),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

/// Scrolls rather than overflows on a short window, and centres its child
/// vertically when it fits.
class _Scrolling extends StatelessWidget {
  const _Scrolling({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - padding.vertical).clamp(0, double.infinity),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// The Platform's wordmark: the Shell's own brand icon and name.
class _Wordmark extends StatelessWidget {
  const _Wordmark({super.key, this.centered = false});

  final bool centered;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    // A Wrap, not a Row: "Platform" is one unbreakable word, and at 320px with
    // the reader's text at 200% it is wider than the row has left beside the
    // icon on either side of it (WCAG 1.4.4). A Wrap gives it the next line
    // instead of painting 32px past the window; at a text scale of 1 the two
    // sit on one line, laid out exactly as the Row laid them out, centred or
    // start-aligned as the header asks.
    return Wrap(
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      children: [
        Icon(Icons.dashboard_outlined, color: palette.actionPrimary),
        Text('Platform', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

/// The left panel at [SignInScreen.twoPanelWidth] and wider.
class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel();

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      key: SignInScreen.identityPanelKey,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        border: Border(right: BorderSide(color: palette.cardBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 2 * Spacing.xxl).clamp(0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Wordmark(),
                const SizedBox(height: Spacing.xl),
                Text(
                  'One application for running several manufacturing plants.',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Spacing.xl),
                for (final (icon, label) in _contents)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: Row(
                      children: [
                        Icon(icon, color: palette.actionPrimary),
                        const SizedBox(width: Spacing.md),
                        Expanded(child: Text(label, style: AppTypography.body(context))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
