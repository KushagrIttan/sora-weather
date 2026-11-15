import 'dart:async';
import '../appearance.dart';
import 'anime_weather_card.dart';
import 'forecast_day.dart';
import 'package:flutter/material.dart';
import '../data/location_service.dart';
import '../data/ai/local_ai_platform.dart';
import 'weather_api.dart';
import 'weather_data.dart';
import 'weather_ai.dart';

const ink = Color(0xFF303654);
const muted = Color(0xFF858BA7);
const green = Color(0xFF5869D9);

class WeatherScreen extends StatefulWidget {
  final SoraWeatherApi api;
  const WeatherScreen({super.key, required this.api});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  bool get dark => Theme.of(context).brightness == Brightness.dark;
  Color tileColor(Color tint) =>
      dark
          ? Color.alphaBlend(
            tint.withValues(alpha: 0.18),
            const Color(0xFF1B2943),
          )
          : tint;
  WeatherPlace? place;
  WeatherBundle? bundle;
  bool loading = false;
  bool locating = false;
  bool fahrenheit = false;
  bool aiBusy = false;
  bool modelPicked = false;
  int request = 0;
  String? error;
  String? chosenId;
  final platform = MethodChannelLocalAi();
  Timer? timer;
  int selectedDay = 0;
  final daysController = PageController(viewportFraction: 0.94);
  final chipsController = ScrollController();

  @override
  void initState() {
    super.initState();
    place = widget.api.savedPlace();
    if (place != null) unawaited(load(place!));
    timer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (place != null &&
          !loading &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(load(place!));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    daysController.dispose();
    chipsController.dispose();
    unawaited(platform.unload().catchError((_) {}));
    super.dispose();
  }

  Future<void> load(WeatherPlace next) async {
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
      chosenId = null;
      modelPicked = false;
      if (place?.key != next.key) {
        bundle = null;
        selectedDay = 0;
        if (daysController.hasClients) daysController.jumpToPage(0);
      }
      place = next;
    });
    try {
      final result = await widget.api.load(next);
      if (!mounted || token != request) return;
      setState(() {
        bundle = result;
        final count = forecastDays(result.weather).length;
        if (selectedDay >= count) {
          selectedDay = 0;
          if (daysController.hasClients) daysController.jumpToPage(0);
        }
        loading = false;
      });
      try {
        await widget.api.savePlace(next);
      } catch (_) {
        /* Keep the current session usable. */
      }
    } catch (_) {
      if (mounted && token == request) {
        setState(() {
          loading = false;
          error = 'Could not load this location. Please try again.';
        });
      }
    }
  }

  Future<void> locate() async {
    setState(() => locating = true);
    try {
      final p = await LocationService().detectCurrentPlace().timeout(
        const Duration(seconds: 25),
      );
      if (mounted) {
        await load(
          WeatherPlace(p.name, 'Current location', p.latitude, p.longitude),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error =
                  e is LocationUnavailableException
                      ? e.message
                      : 'Location is unavailable. Search for your city instead.',
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> search() async {
    final selected = await showModalBottomSheet<WeatherPlace>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CitySearch(api: widget.api),
    );
    if (selected != null && mounted) await load(selected);
  }

  Future<void> useAi() async {
    if (bundle == null || aiBusy) return;
    final token = request;
    setState(() => aiBusy = true);
    try {
      final status = await platform.status();
      if (!mounted || token != request) return;
      if (!status.supported || !status.installed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !status.supported
                  ? 'The AI model runs on supported Android builds. Local rule insights are active.'
                  : 'Install the optional Qwen model in AI settings first. Local rule insights are active.',
            ),
          ),
        );
        return;
      }
      final id = await chooseLocalInsight(
        platform,
        localInsights(bundle!, DateTime.now().toUtc()),
      );
      if (mounted && token == request) {
        setState(() {
          chosenId = id;
          modelPicked = id != null;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The model is unavailable. Showing local rule insights.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => aiBusy = false);
    }
  }

  Future<void> settings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (context) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Make it your kind of sky',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'APPEARANCE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Builder(
                        builder: (context) {
                          final appearance = AppearanceScope.of(context);
                          return Wrap(
                            spacing: 8,
                            children: [
                              for (final mode in ThemeMode.values)
                                ChoiceChip(
                                  key: ValueKey('theme-${mode.name}'),
                                  selected: appearance.value == mode,
                                  avatar: Icon(
                                    mode == ThemeMode.dark
                                        ? Icons.dark_mode_rounded
                                        : mode == ThemeMode.light
                                        ? Icons.light_mode_rounded
                                        : Icons.brightness_auto_rounded,
                                    size: 17,
                                  ),
                                  label: Text(
                                    mode.name[0].toUpperCase() +
                                        mode.name.substring(1),
                                  ),
                                  onSelected: (_) => appearance.setMode(mode),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your choice is saved on this device.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(indent: 24, endIndent: 24),
                _AiSettings(platform: platform),
              ],
            ),
          ),
    );
  }

  String temp(Object? value) {
    final n = reading(value);
    return n == null ? '—' : '${(fahrenheit ? n * 9 / 5 + 32 : n).round()}°';
  }

  void goToDay(int index) {
    daysController.animateToPage(
      index,
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = bundle;
    final w = b?.weather;
    final a = b?.air;
    final days = forecastDays(w);
    final d = days.isEmpty ? null : days[selectedDay.clamp(0, days.length - 1)];
    final current = d?.isCurrent ?? true;
    final insights =
        b == null
            ? <WeatherInsight>[]
            : localInsights(b, DateTime.now().toUtc());
    if (chosenId != null) {
      insights.sort(
        (x, y) =>
            x.id == chosenId
                ? -1
                : y.id == chosenId
                ? 1
                : 0,
      );
    }
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors:
                dark
                    ? [
                      const Color(0xFF101C32),
                      const Color(0xFF1B2443),
                      const Color(0xFF27203C),
                    ]
                    : [
                      const Color(0xFFEDF3FF),
                      const Color(0xFFF0EEFF),
                      const Color(0xFFFFEEF5),
                    ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              if (place != null) await load(place!);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 18, 0),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFB7C5FF),
                                    Color(0xFFF4BEE1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Icon(
                                Icons.wb_cloudy_rounded,
                                color: Colors.white,
                                size: 25,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'sora',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.4,
                                    ),
                                  ),
                                  Text(
                                    'a forecast to fall in love with',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                      fontSize: 9,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Toggle Celsius and Fahrenheit',
                              onPressed:
                                  () =>
                                      setState(() => fahrenheit = !fahrenheit),
                              icon: Text(
                                fahrenheit ? '°F' : '°C',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Appearance and AI settings',
                              onPressed: settings,
                              icon: const Icon(Icons.tune_rounded, size: 21),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 23, 18, 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: green,
                              size: 17,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    place?.name ?? 'Find your sky',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (place?.region.isNotEmpty ?? false)
                                    Text(
                                      place!.region,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Search city',
                              onPressed: search,
                              icon: Icon(
                                Icons.search_rounded,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                size: 21,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Use my location',
                              onPressed: locating ? null : locate,
                              icon:
                                  locating
                                      ? const SizedBox(
                                        width: 17,
                                        height: 17,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : Icon(
                                        Icons.near_me_outlined,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                        size: 20,
                                      ),
                            ),
                          ],
                        ),
                      ),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Color(0xFFB04E69)),
                          ),
                        ),
                      if (days.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Your week, in full color.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Previous day',
                                visualDensity: VisualDensity.compact,
                                onPressed:
                                    selectedDay > 0
                                        ? () => goToDay(selectedDay - 1)
                                        : null,
                                icon: const Icon(
                                  Icons.chevron_left_rounded,
                                  size: 21,
                                ),
                              ),
                              Text(
                                '${selectedDay + 1} / ${days.length}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next day',
                                visualDensity: VisualDensity.compact,
                                onPressed:
                                    selectedDay < days.length - 1
                                        ? () => goToDay(selectedDay + 1)
                                        : null,
                                icon: const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 21,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 465 + mathExtra(context),
                          child: PageView.builder(
                            key: ValueKey(place?.key),
                            controller: daysController,
                            itemCount: days.length,
                            onPageChanged: (i) {
                              setState(() => selectedDay = i);
                              if (chipsController.hasClients) {
                                chipsController.animateTo(
                                  (i * 105.0).clamp(
                                    0,
                                    chipsController.position.maxScrollExtent,
                                  ),
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                          ? Duration.zero
                                          : const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              }
                            },
                            itemBuilder:
                                (_, i) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 8,
                                  ),
                                  child: AnimeWeatherCard(
                                    day: days[i],
                                    temperature: temp,
                                    fahrenheit: fahrenheit,
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 55,
                          child: ListView.separated(
                            controller: chipsController,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            scrollDirection: Axis.horizontal,
                            itemCount: days.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(width: 8),
                            itemBuilder:
                                (_, i) => Semantics(
                                  selected: selectedDay == i,
                                  child: ActionChip(
                                    key: ValueKey('day-chip-$i'),
                                    onPressed: () => goToDay(i),
                                    backgroundColor:
                                        selectedDay == i
                                            ? const Color(0xFF5869D9)
                                            : (dark
                                                    ? const Color(0xFF2D3C5B)
                                                    : Colors.white)
                                                .withValues(alpha: 0.9),
                                    side: BorderSide(
                                      color:
                                          selectedDay == i
                                              ? const Color(0xFF5869D9)
                                              : dark
                                              ? const Color(0xFF4B5D7C)
                                              : const Color(0xFFE8E5F5),
                                    ),
                                    label: Text(
                                      '${days[i].label} · ${days[i].shortDate}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            selectedDay == i
                                                ? Colors.white
                                                : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: SizedBox(
                            height: 460,
                            child: AnimeWeatherCard(
                              day: null,
                              temperature: temp,
                              fahrenheit: fahrenheit,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (place == null) ...[
                              const SizedBox(height: 14),
                              const Text(
                                'Good days start with a little wonder.',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.7,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Discover your weather, breathe a little easier, and find the bright side of every forecast.',
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                  height: 1.6,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: search,
                                icon: const Icon(Icons.search),
                                label: const Text('Find my city'),
                              ),
                            ] else if (w == null) ...[
                              _unavailable(
                                loading
                                    ? 'Bringing your forecast into focus…'
                                    : 'Weather is unavailable. Check your connection and refresh.',
                              ),
                              const SizedBox(height: 14),
                              _airCard(b, null),
                            ] else ...[
                              _stamp(w, 'Weather'),
                              const SizedBox(height: 16),
                              _metrics(d!),
                              const SizedBox(height: 25),
                              _heading(
                                current
                                    ? 'A little fresh-air check'
                                    : '${d.label}’s air outlook',
                                'BREATHE EASY',
                              ),
                              const SizedBox(height: 12),
                              _airCard(b, d),
                              const SizedBox(height: 26),
                              _heading(
                                current
                                    ? 'The hours ahead'
                                    : '${d.label}, hour by hour',
                                'TAKE IT HOUR BY HOUR',
                              ),
                              const SizedBox(height: 12),
                              _hourly(d, a),
                              const SizedBox(height: 24),
                              if (current)
                                _insightCard(insights)
                              else
                                _futureInsight(d),
                              const SizedBox(height: 24),
                              if (current) ...[
                                _heading(
                                  'What’s in your air?',
                                  'THE LITTLE DETAILS',
                                ),
                                const SizedBox(height: 12),
                                _pollutants(a),
                                const SizedBox(height: 14),
                              ],
                              Text(
                                'US AQI scale · PM2.5 in µg/m³. Air quality is modeled, not a nearby sensor reading. Future air forecasts appear only for dates with available data.',
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  height: 1.7,
                                ),
                              ),
                            ],
                            if (place != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: OutlinedButton.icon(
                                  onPressed:
                                      loading ? null : () => load(place!),
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('Refresh conditions'),
                                ),
                              ),
                            const SizedBox(height: 28),
                            const Center(
                              child: Text(
                                'A little sky. A little joy. All yours. ✦',
                                style: TextStyle(color: green, fontSize: 11),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Center(
                              child: SelectableText(
                                'Weather & geocoding: Open-Meteo\nAir quality: CAMS ENSEMBLE / CAMS via Open-Meteo\nopen-meteo.com · atmosphere.copernicus.eu',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                  fontSize: 9,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Give large text enough space within the fixed-height page viewport.
  double mathExtra(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0, 30) * 7;

  Widget _metrics(ForecastDay d) {
    final current = d.isCurrent;
    final items =
        current
            ? [
              (
                Icons.thermostat_rounded,
                'Feels like',
                temp(d.weather.value('apparent_temperature')),
              ),
              (
                Icons.air_rounded,
                'Wind',
                '${_number(d.weather.value('wind_speed_10m'))} km/h',
              ),
              (
                Icons.water_drop_outlined,
                'Humidity',
                '${_number(d.weather.value('relative_humidity_2m'))}%',
              ),
            ]
            : [
              (Icons.umbrella_outlined, 'Rain chance', '${_number(d.rain)}%'),
              (
                Icons.air_rounded,
                'Peak wind',
                '${_number(reading(d.daily['wind_speed_10m_max']))} km/h',
              ),
              (
                Icons.wb_sunny_outlined,
                'Max UV',
                _number(reading(d.daily['uv_index_max']), decimal: true),
              ),
            ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
              decoration: BoxDecoration(
                color: tileColor(
                  [
                    const Color(0xFFFFDBC8),
                    const Color(0xFFD8E3FF),
                    const Color(0xFFC7F0DF),
                  ][i],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  Icon(
                    items[i].$1,
                    color:
                        [
                          const Color(0xFFC77E75),
                          const Color(0xFF7D87C4),
                          const Color(0xFF72A7A8),
                        ][i],
                    size: 21,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    items[i].$3,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _airCard(WeatherBundle? b, ForecastDay? d) {
    final current = d?.isCurrent ?? true;
    final aqi = current ? b?.aqi : d!.peakAir(b?.air, 'us_aqi');
    final pm = current ? b?.pm25 : d!.peakAir(b?.air, 'pm2_5');
    return _card(
      const Color(0xFFD5F3D4),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.spa_outlined,
                color: Color(0xFF68A79A),
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  current ? 'Your air, right now' : 'Daily peak air forecast',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              _tag('US AQI'),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Text(
                _number(aqi),
                style: const TextStyle(
                  fontSize: 46,
                  letterSpacing: -2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  aqiCategory(aqi),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        dark
                            ? Color.lerp(_aqiColor(aqi), Colors.white, 0.35)
                            : _aqiColor(aqi),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                for (final c in [
                  const Color(0xFF8BC8AD),
                  const Color(0xFFE5D18E),
                  const Color(0xFFEAB193),
                  const Color(0xFFD68D9D),
                  const Color(0xFFAD94CA),
                  const Color(0xFF946D9B),
                ])
                  Expanded(
                    child: ColoredBox(
                      color: c,
                      child: const SizedBox(height: 6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${current ? 'PM2.5' : 'Peak PM2.5'}  ${_number(pm, decimal: true)} µg/m³',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (aqi == null && !current)
            Text(
              'No air-quality forecast available for this day.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          if (b?.air != null)
            _stamp(b!.air!, current ? 'Air' : 'Air forecast source')
          else
            Text(
              'Air data unavailable · Refresh to try again',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _hourly(ForecastDay d, WeatherPayload? air) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final rows =
        d.hours
            .where((r) => !d.isCurrent || (r['time'] as num) >= now - 3600)
            .toList();
    if (rows.isEmpty) {
      return _unavailable('No hourly data available for this day.');
    }
    final airRows = {
      for (final r in air?.rows('hourly') ?? <Map<String, dynamic>>[])
        r['time']: r,
    };
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = rows[i];
          return Container(
            width: 91,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5),
            decoration: BoxDecoration(
              color:
                  i == 0
                      ? tileColor(const Color(0xFFD9D3FF))
                      : (dark ? const Color(0xFF273552) : Colors.white)
                          .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color:
                    dark
                        ? const Color(0xFF465273)
                        : i == 0
                        ? const Color(0xFFD2CDFF)
                        : const Color(0xFFEAE7F7),
              ),
            ),
            child: Column(
              children: [
                Text(
                  hourLabel(
                    localTime((r['time'] as num).toInt(), d.weather.offset),
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 13),
                Icon(
                  _weatherIcon(reading(r['weather_code'])),
                  color: const Color(0xFFA398D4),
                  size: 25,
                ),
                const SizedBox(height: 9),
                Text(
                  temp(r['temperature_2m']),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rain ${_number(reading(r['precipitation_probability']))}%',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'PM2.5 ${_number(reading(airRows[r['time']]?['pm2_5']), decimal: true)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _insightCard(List<WeatherInsight> insights) => _card(
    const Color(0xFFFFDDB4),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Color(0xFFC69B67)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'A little heads-up',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            _tag(modelPicked ? 'LOCAL AI' : 'LOCAL RULES'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          insights.isEmpty ? 'Waiting for your sky' : insights.first.title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          insights.isEmpty
              ? 'Insights appear when conditions arrive.'
              : insights.first.body,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: aiBusy || bundle == null ? null : useAi,
          icon:
              aiBusy
                  ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.memory_rounded, size: 16),
          label: Text(
            aiBusy
                ? 'Thinking on your device…'
                : 'Prioritize with on-device AI',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Text(
          'Private by nature. Insights stay on your device.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 9,
          ),
        ),
      ],
    ),
  );
  Widget _futureInsight(ForecastDay d) => _card(
    const Color(0xFFFFDDB4),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: Color(0xFFC69B67)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'A little plan for ${d.label.toLowerCase()}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${conditionLabel(d.code)} with a high of ${temp(d.high)} and a low of ${temp(d.low)}. ${d.rain == null
              ? 'Check back as the forecast develops.'
              : d.rain! >= 50
              ? 'Rain probability peaks at ${d.rain!.round()}% — an umbrella could come in handy.'
              : 'Peak rain probability is ${d.rain!.round()}%.'}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.7,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        _tag('FORECAST · LOCAL RULES'),
      ],
    ),
  );
  Widget _pollutants(WeatherPayload? air) => _card(
    (dark ? const Color(0xFF273552) : Colors.white).withValues(alpha: 0.9),
    Wrap(
      spacing: 28,
      runSpacing: 20,
      children: [
        for (final e
            in {
              'PM2.5': 'pm2_5',
              'PM10': 'pm10',
              'Nitrogen dioxide': 'nitrogen_dioxide',
              'Ozone': 'ozone',
            }.entries)
          SizedBox(
            width: 125,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.key,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_number(air?.value(e.value), decimal: true)} µg/m³',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _stamp(WeatherPayload p, String label) {
    final date = p.observedAt;
    final local =
        date == null
            ? null
            : localTime(date.millisecondsSinceEpoch ~/ 1000, p.offset);
    return Text(
      '${p.stale ? 'Cached / stale · ' : ''}$label valid ${local == null ? 'time unavailable' : '${dayKey(local)} ${hourLabel(local)}'} · location time',
      style: TextStyle(
        fontSize: 9,
        height: 1.5,
        color:
            p.stale
                ? const Color(0xFFB17859)
                : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _tag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color:
          dark ? const Color(0xFF34405F) : Colors.white.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 8,
        letterSpacing: 0.7,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
  Widget _card(Color color, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: tileColor(color),
      borderRadius: BorderRadius.circular(27),
      border: Border.all(
        color:
            dark
                ? const Color(0xFF3A4563)
                : Colors.white.withValues(alpha: 0.9),
      ),
    ),
    child: child,
  );
  Widget _heading(String title, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 1.6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        title,
        style: const TextStyle(
          fontSize: 22,
          letterSpacing: -0.7,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
  Widget _unavailable(String text) => _card(
    Colors.white,
    Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    ),
  );
}

String _number(double? n, {bool decimal = false}) =>
    n == null
        ? '—'
        : decimal
        ? n.toStringAsFixed(1)
        : '${n.round()}';
Color _aqiColor(double? aqi) =>
    aqi == null
        ? muted
        : aqi <= 50
        ? const Color(0xFF4E977D)
        : aqi <= 100
        ? const Color(0xFF99814E)
        : aqi <= 150
        ? const Color(0xFFB77A55)
        : const Color(0xFFB95678);
IconData _weatherIcon(double? code) =>
    code == null
        ? Icons.cloud_outlined
        : code < 2
        ? Icons.wb_sunny_outlined
        : code < 50
        ? Icons.cloud_outlined
        : code >= 95
        ? Icons.thunderstorm_outlined
        : (code >= 71 && code <= 77) || code == 85 || code == 86
        ? Icons.ac_unit
        : Icons.water_drop_outlined;

class _CitySearch extends StatefulWidget {
  final SoraWeatherApi api;
  const _CitySearch({required this.api});
  @override
  State<_CitySearch> createState() => _CitySearchState();
}

class _CitySearchState extends State<_CitySearch> {
  final controller = TextEditingController();
  List<WeatherPlace> results = [];
  bool busy = false;
  String? message;
  int token = 0;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (controller.text.trim().length < 2) {
      setState(() => message = 'Enter at least two characters.');
      return;
    }
    final id = ++token;
    setState(() {
      busy = true;
      message = null;
      results = [];
    });
    try {
      final found = await widget.api.search(controller.text);
      if (mounted && id == token) {
        setState(() {
          results = found;
          busy = false;
          message =
              found.isEmpty
                  ? 'No cities found. Try a nearby city or add a country.'
                  : null;
        });
      }
    } catch (_) {
      if (mounted && id == token) {
        setState(() {
          busy = false;
          message = 'Search is unavailable. Check your connection and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      8,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SizedBox(
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Where’s your sky?',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => search(),
            decoration: InputDecoration(
              labelText: 'City or postal code',
              hintText: 'e.g. Kolkata, India',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (busy) const LinearProgressIndicator(),
          if (message != null)
            Text(
              message!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder:
                  (_, i) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(results[i].name),
                    subtitle: Text(results[i].region),
                    onTap: () => Navigator.pop(context, results[i]),
                  ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AiSettings extends StatefulWidget {
  final LocalAiPlatform platform;
  const _AiSettings({required this.platform});
  @override
  State<_AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<_AiSettings> {
  LocalModelStatus? status;
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final result = await widget.platform.status();
    if (mounted) setState(() => status = result);
  }

  Future<void> install() async {
    setState(() {
      busy = true;
      message =
          'Downloading model. Keep this panel open; the model is about 328 MiB.';
    });
    try {
      await widget.platform.install();
      if (mounted) {
        await refresh();
        if (mounted) {
          setState(
            () =>
                message =
                    'Model ready. Use the AI button on your insight card.',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              message =
                  'Download did not complete. You can retry; local rules remain available.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A thoughtful little companion',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Text(
            'Local rules create insights from forecast facts. The optional Qwen model prioritizes those insights entirely on your device. Weather and location search still need internet access.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          if (status == null)
            const LinearProgressIndicator()
          else
            Text(
              !status!.supported
                  ? 'On-device model: supported Android builds only.'
                  : status!.installed
                  ? 'Qwen3 0.6B · Installed'
                  : 'Qwen3 0.6B · Optional download, about 328 MiB',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message!),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (status?.supported == true && status?.installed == false)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: FilledButton(
                onPressed: busy ? null : install,
                child: const Text('Download on-device model'),
              ),
            ),
          if (busy)
            TextButton(
              onPressed: () async {
                await widget.platform.cancel();
              },
              child: const Text('Cancel download'),
            ),
        ],
      ),
    ),
  );
}
