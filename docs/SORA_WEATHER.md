# Standalone architecture

This project owns all source, assets, platform configuration and data used by Sora Weather. Its package is `app.sora.sora_weather`. There are no path dependencies, links, external project imports, wardrobe modules or shared application data.

- `lib/main.dart`: standalone bootstrap and app themes.
- `lib/appearance.dart`: persisted Light / Dark / System preference.
- `lib/weather/weather_api.dart`: independent weather and air-quality fetches, city search and per-coordinate caches.
- `lib/weather/forecast_day.dart`: day selection, hourly alignment, artwork selection and daily air-forecast peaks.
- `lib/weather/anime_weather_card.dart`: illustrated swipe-card presentation.
- `lib/weather/weather_screen.dart`: dashboard, day navigation, appearance settings and local AI controls.
- `lib/data/ai/local_ai_platform.dart` and the Android `ai` package: optional verified model download and device-only insight selection.
- `assets/weather`: original anime environment paintings. Prompts and provenance are in `SORA_ANIME_ART.md`.

Fresh data uses Open-Meteo weather/geocoding and CAMS via Open-Meteo for modeled air quality. Endpoint failures use separate labeled cached fallbacks. Missing AQI and PM2.5 remain unavailable. Current data older than two hours is excluded from local insights. No cloud AI service is used.

On the first day the card shows current temperature; subsequent days show forecast highs and labeled high/low ranges. Day selection updates the hourly details and summaries. Future air cards show maximum available hourly values for the selected date; days beyond the air response show unavailable.

The Android runtime accepts only a grounded insight-ranking task. The model cannot author forecast facts or call application tools. Local rules remain active without a downloaded model. Physical-device AI inference, permissions and battery testing remain separate from emulator visual checks.
