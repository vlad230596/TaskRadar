import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../providers/login_controller.dart';

/// Email + password, one button, one inline error.
///
/// Port of `frontend/src/pages/LoginPage.tsx`, including its wording. There is
/// no "sign up" and no "forgot password": the single user is defined by
/// environment variables on the server (see `backend/src/lib/authConfig.ts`),
/// so there is nothing here for either flow to do.
///
/// Navigation away on success is not this screen's job. It just calls
/// `LoginController.submit`; the session state flips and the root widget swaps
/// the screen out. That keeps "who is allowed in" in one place instead of
/// spread across `Navigator` calls.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Dismiss the soft keyboard before the request: on a phone it covers the
    // area where the error message will appear.
    FocusScope.of(context).unfocus();

    await ref
        .read(loginControllerProvider.notifier)
        .submit(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider);
    final submitting = state.isLoading;
    final error = state.error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              // Without a cap the form stretches edge to edge on the Windows
              // target, where the window is 1280 points wide.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'TaskRadar',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      autofocus: true,
                      enabled: !submitting,
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Введите email' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Пароль',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      // Submitting from the keyboard's "done" key is the normal
                      // way to finish a two-field form on a phone.
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => submitting ? null : _submit(),
                      enabled: !submitting,
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Введите пароль' : null,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        loginErrorMessage(error),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: submitting ? null : _submit,
                      child: submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Войти'),
                    ),
                    const SizedBox(height: 16),
                    // The one piece of diagnostics worth showing on a login
                    // screen. "Cannot connect" on a phone is almost always the
                    // wrong base URL (localhost baked in, or the laptop's LAN
                    // address changed), and this turns a ten-minute guess into
                    // a glance. It is compile-time constant, so nothing secret
                    // can leak through it.
                    Text(
                      AppConfig.apiBaseUrl,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
