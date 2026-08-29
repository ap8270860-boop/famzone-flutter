#!/usr/bin/env python3
"""file_picker 11 moved pickFiles onto the class itself.

`FilePicker.platform.pickFiles()` was the API up to v10. In v11 the platform
indirection is gone and pickFiles is a static method on FilePicker. (v12 goes
further and returns a bare List<PlatformFile> — worth knowing before any
future upgrade.)

Also hardens the result handling: `.single` throws on an empty list, which is
exactly what a cancelled picker can return on some platforms.

Run from the famzone-flutter repo root. Idempotent.
"""

import io
import sys

P = 'lib/features/chat/presentation/chat_screen.dart'
s = io.open(P, encoding='utf-8').read()

if 'FilePicker.pickFiles' in s:
    sys.exit(f'{P}: already patched')

OLD = """      final result = await FilePicker.platform.pickFiles(withData: false);
      final file = result?.files.single;
      final path = file?.path;

      if (path == null || !mounted) return;"""

NEW = """      // Static on the class since file_picker 11 — there is no `.platform`
      // indirection any more. withData stays false so a 20 MB file is not
      // read into memory just to be uploaded from disk.
      final result = await FilePicker.pickFiles(withData: false);

      if (result == null || result.files.isEmpty || !mounted) return;

      final path = result.files.first.path;

      // Null on web, where there is no filesystem path — nothing to send
      // from here until that platform is actually supported.
      if (path == null) return;"""

if OLD not in s:
    sys.exit(f'{P}: pickFiles block not found')

io.open(P, 'w', encoding='utf-8', newline='').write(s.replace(OLD, NEW, 1))
print(f'{P}: file_picker 11 API')
