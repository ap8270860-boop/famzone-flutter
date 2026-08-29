#!/usr/bin/env python3
"""FALLBACK ONLY — run this if `flutter clean` did not fix the build.

Pins file_picker to 8.3.7 and puts the call site back to the v8 API.

Why: v11.0.0 refactored the Android side for AGP 9 support, and v11.0.1 then
had to fix backward compatibility below AGP 9. If the plugin's module will not
build under this project's Gradle, its classes never reach the classpath and
the only symptom is GeneratedPluginRegistrant failing to find FilePickerPlugin
— an error that points at the registrant rather than at the real cause.

8.3.7 predates that refactor and is the version most production apps ship.

After running:
    flutter clean && flutter pub get && flutter run
"""

import io
import re
import sys

changed = []


def read(p):
    return io.open(p, encoding='utf-8').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


# ================================================================ pubspec

P = 'pubspec.yaml'
s = read(P)

if 'file_picker: 8.3.7' in s:
    print(f'{P}: already pinned')
else:
    new = re.sub(
        r'^(\s*)file_picker:.*$',
        # Pinned exactly, not with a caret. A caret would let pub climb back
        # into 11 on the next resolve and reintroduce this exact failure.
        r'\1file_picker: 8.3.7',
        s,
        count=1,
        flags=re.M,
    )

    if new == s:
        sys.exit(f'{P}: no file_picker line found')

    write(P, new)
    changed.append(P)
    print(f'{P}: file_picker pinned to 8.3.7')


# ============================================================ chat_screen

P = 'lib/features/chat/presentation/chat_screen.dart'
s = read(P)

if 'FilePicker.platform.pickFiles' in s:
    print(f'{P}: already on the v8 API')
else:
    OLD = """      // Static on the class since file_picker 11 — there is no `.platform`
      // indirection any more. withData stays false so a 20 MB file is not
      // read into memory just to be uploaded from disk.
      final result = await FilePicker.pickFiles(withData: false);"""

    NEW = """      // `.platform` is the v8 API. v11 moved pickFiles onto the class
      // itself and v12 changed the return type again — check the installed
      // version before touching this line.
      //
      // withData stays false so a 20 MB file is not read into memory just to
      // be uploaded from disk.
      final result = await FilePicker.platform.pickFiles(withData: false);"""

    if OLD not in s:
        sys.exit(f'{P}: pickFiles call not found in the expected shape')

    write(P, s.replace(OLD, NEW, 1))
    changed.append(P)
    print(f'{P}: reverted to the v8 API')


print('\ndone: ' + (', '.join(changed) if changed else 'nothing to do'))
print('\nnow run:  flutter clean && flutter pub get && flutter run')
