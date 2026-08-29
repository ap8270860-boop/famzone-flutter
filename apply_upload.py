#!/usr/bin/env python3
"""Give uploads a longer timeout than an ordinary request.

Run from the famzone-flutter repo root. Idempotent.
"""

import io
import sys

changed = []


def read(p):
    return io.open(p, encoding='utf-8').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


# ============================================================= app_config

P = 'lib/core/config/app_config.dart'
s = read(P)

if 'uploadTimeout' in s:
    print(f'{P}: already patched')
else:
    OLD = """  /// How long to wait on any single request before giving up.
  static const Duration requestTimeout = Duration(seconds: 15);"""

    NEW = """  /// How long to wait on any single request before giving up.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Uploads get their own, much longer.
  ///
  /// 15 seconds is generous for a JSON round trip and hopeless for a photo on
  /// mobile data — a 4 MB file at 500 kbps is over a minute. Sharing the
  /// short timeout would mean uploads failing constantly on exactly the
  /// connections where they matter most.
  static const Duration uploadTimeout = Duration(minutes: 3);"""

    if OLD not in s:
        sys.exit(f'{P}: requestTimeout not found')

    write(P, s.replace(OLD, NEW, 1))
    changed.append(P)
    print(f'{P}: uploadTimeout added')


# ============================================================= api_client

P = 'lib/core/api/api_client.dart'
s = read(P)

if 'AppConfig.uploadTimeout' in s:
    print(f'{P}: already patched')
else:
    OLD = "      final streamed = await request.send().timeout(AppConfig.requestTimeout);"
    NEW = "      final streamed = await request.send().timeout(AppConfig.uploadTimeout);"

    if OLD not in s:
        sys.exit(f'{P}: upload timeout line not found')

    write(P, s.replace(OLD, NEW, 1))
    changed.append(P)
    print(f'{P}: uploads use the long timeout')


print('\ndone: ' + (', '.join(changed) if changed else 'nothing to do'))
