#!/usr/bin/env python3
"""Bake the Reverb app key in as the default, so `flutter run` just works."""

import io
import sys

P = 'lib/core/config/app_config.dart'
s = io.open(P, encoding='utf-8').read()

if "defaultValue: 'lrqwccbcdgoprday7bub'" in s:
    sys.exit(f'{P}: already patched')

OLD = """  /// The Reverb application key, from the API's .env.
  ///
  ///   flutter run --dart-define=REVERB_KEY=xxxxxxxx
  ///
  /// Empty by default, and that is a feature: with no key the realtime layer
  /// stays dormant and the app behaves exactly as it did before websockets
  /// existed — messages still send over HTTP, screens still refresh. A build
  /// can ship before the socket server is ready.
  static const String reverbKey = String.fromEnvironment('REVERB_KEY');"""

NEW = """  /// The Reverb application key.
  ///
  /// Safe to keep in the repo. Unlike REVERB_APP_SECRET, the key is public by
  /// design: it travels in the WebSocket URL of every client that connects,
  /// so it is already visible to anyone who looks at network traffic. What
  /// actually protects a conversation is channel authorisation — every
  /// private subscription is signed server-side with the secret, which never
  /// leaves EC2. Holding the key alone lets somebody open a socket and
  /// subscribe to nothing.
  ///
  /// Override for a local Reverb, or set it empty to turn the realtime layer
  /// off entirely — with no key the app falls back to exactly how it behaved
  /// before websockets existed, which is a useful thing to be able to do
  /// while diagnosing something:
  ///
  ///   flutter run --dart-define=REVERB_KEY=
  static const String reverbKey = String.fromEnvironment(
    'REVERB_KEY',
    defaultValue: 'lrqwccbcdgoprday7bub',
  );"""

if OLD not in s:
    sys.exit(f'{P}: reverbKey block not found')

io.open(P, 'w', encoding='utf-8', newline='').write(s.replace(OLD, NEW, 1))
print(f'{P}: Reverb key defaulted — plain `flutter run` now connects')
