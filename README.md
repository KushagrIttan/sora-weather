# Sora Weather

An independent Flutter Android app with vibrant anime weather cards, current weather, swipeable daily forecasts, hourly predictions, US AQI and PM2.5. Weather, air quality, local insights, preferences and optional on-device model management live entirely in this project.

## Run

```bash
flutter pub get
flutter run
```

Android application ID: `app.sora.sora_weather`. Launcher: **Sora Weather**. There are no FitFlow project, database, asset, plugin or runtime dependencies. This app owns separate Android storage and preferences.

## Appearance

Tap the sliders button at the top right and choose **Light**, **Dark**, or **System**. The selection is saved locally. Bold rounded layouts, vibrant mint/peach/lavender panels and original anime scenery are inspired by the approachable visual direction of Pixel Weather; all illustrations and branding are original.

## Forecast and air

Swipe the main card left/right, tap date chips, or use the arrow buttons to browse every daily forecast returned by Open-Meteo. The first card shows the current temperature; subsequent cards show forecast highs with an explicit daily range. Hourly details, forecast summaries and air outlook follow the chosen day. AQI and PM2.5 are only shown where the air API provides coverage; later days show unavailable.

Weather and air requests have independent cached fallbacks. Stale data is labeled. PM2.5 is a concentration in µg/m³; US AQI is a separate index. Air data is modeled CAMS data, not a local sensor reading. Source attribution appears in the app. Internet access is required for fresh data, not for local insight computation. Review provider licensing/plans before commercial distribution.

## Optional local AI

Settings can download the verified Qwen3 0.6B INT4 model (~328 MiB) on supported Android devices. The pinned LiteRT-LM runtime selects among grounded insights. No cloud AI API or API key is used. Missing models or failed inference retain local rule insights. Model downloads and runtime caches are separate from app backups.

## Verify and build

```bash
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --target-platform android-x64
# For a physical ARM64 phone:
flutter build apk --debug --target-platform android-arm64
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`. Release signing is currently the development configuration. See [art prompts and provenance](docs/SORA_ANIME_ART.md).
# sora-weather
