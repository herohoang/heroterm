import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connection/data/connection_tester.dart';
import '../../connection/presentation/connection_dialogs.dart';
import '../../connection/presentation/connection_providers.dart';
import '../domain/ssh_session.dart';
import 'session_providers.dart';

/// Runs a Test Connection for [profile] (profile spec 7.3), shared
/// by the profile form and the session list menu.
///
/// Secret resolution: an explicitly [enteredSecret] wins; an empty
/// entry falls back to the profile's stored Keychain secret; with
/// neither, the SSH layer prompts for a password if it needs one.
/// Host-key and password prompts use the same dialogs as a real
/// connection. The result message never contains secret material.
Future<ConnectionTestResult> runConnectionTest(
  BuildContext context,
  WidgetRef ref,
  SshSession profile, {
  String? enteredSecret,
}) async {
  var secret = enteredSecret;
  if (secret != null && secret.isEmpty) secret = null;
  if (secret == null && profile.credentialRef != null) {
    secret = await ref
        .read(credentialStoreProvider)
        .read(profile.credentialRef!);
  }
  final tester = ref.read(connectionTesterProvider);
  return tester.test(
    profile,
    storedSecret: secret,
    onHostKeyPrompt: (challenge) async {
      if (!context.mounted) return false;
      return showHostKeyTrustDialog(context, challenge);
    },
    onPasswordPrompt: (username, hostLabel) async {
      if (!context.mounted) return null;
      return showPasswordPromptDialog(
        context,
        username: username,
        hostLabel: hostLabel,
      );
    },
  );
}
