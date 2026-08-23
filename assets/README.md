# Assets

| Folder | What goes here |
|---|---|
| `logo/` | SFamily brand marks only — wordmark, icon mark, monochrome variants |
| `images/` | Photos, illustrations, onboarding art, empty-state graphics |
| `icons/` | Custom icons that Material Icons does not cover |
| `fonts/` | Font files, if a custom typeface is added later |

## Resolution variants

Flutter picks the right file for the device's pixel density automatically.
Put the 1x file in the folder and higher-density copies in `2.0x/` and `3.0x/`
subfolders, using the **same filename**:

```
assets/logo/sfamily_mark.png          <- 1x  (e.g. 96x96)
assets/logo/2.0x/sfamily_mark.png     <- 2x  (192x192)
assets/logo/3.0x/sfamily_mark.png     <- 3x  (288x288)
```

You reference only `assets/logo/sfamily_mark.png` in code.

## Naming

`lower_snake_case`, no spaces, no capitals. Describe the thing, not the screen —
`empty_inbox.png` rather than `chat_screen_image_2.png`.

## Do not put the launcher icon here

The Android home-screen icon lives in `android/app/src/main/res/mipmap-*/`
and is generated, not referenced from Dart. See the note in `pubspec.yaml`.
