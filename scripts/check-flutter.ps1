$ErrorActionPreference = "Stop"

$repo = "C:\_flutter_work\fluxidi_tracking"

Set-Location $repo

flutter pub get
dart format --set-exit-if-changed lib
flutter analyze lib/main.dart lib/app_config.dart lib/app_strings.dart
