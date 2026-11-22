import 'package:flutter/material.dart';

import '../data/ssh_connection_service.dart';

/// First-use host-key trust prompt (FEATURE_SPEC section 8). The full
/// fingerprint is shown so the user can compare it with the value
/// from the server administrator. There is deliberately no "trust and
/// don't ask again" shortcut beyond this explicit decision — trusting
/// saves the key and later changes are blocked.
Future<bool> showHostKeyTrustDialog(
  BuildContext context,
  HostKeyChallenge challenge,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.shield_outlined),
      title: const Text('Unknown host key'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The server ${challenge.hostLabel} presented a host key '
              'that has not been trusted before:',
            ),
            const SizedBox(height: 12),
            Text('Type: ${challenge.keyType}'),
            const SizedBox(height: 4),
            SelectableText(
              'Fingerprint: ${challenge.fingerprint}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Compare this fingerprint with the one provided by your '
              'server administrator. Only trust it if they match.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('hostkey-abort'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abort connection'),
        ),
        FilledButton(
          key: const Key('hostkey-trust'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Trust and connect'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Password prompt used when a session has no stored credential.
Future<String?> showPasswordPromptDialog(
  BuildContext context, {
  required String username,
  required String hostLabel,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Password required'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the password for $username@$hostLabel.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('prompt-password'),
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
            const SizedBox(height: 8),
            const Text(
              'Used for this connection only — it is not saved. To save '
              'it, edit the session and enter the password there.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('prompt-password-cancel'),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('prompt-password-ok'),
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Connect'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
