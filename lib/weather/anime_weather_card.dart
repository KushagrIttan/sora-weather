import 'package:flutter/material.dart';
import 'forecast_day.dart';
import 'weather_data.dart';

class AnimeWeatherCard extends StatelessWidget {
  final ForecastDay? day;
  final String Function(Object?) temperature;
  final bool fahrenheit;
  const AnimeWeatherCard({
    super.key,
    required this.day,
    required this.temperature,
    required this.fahrenheit,
  });
  @override
  Widget build(BuildContext context) {
    final d = day;
    final night = d?.night ?? false;
    final fg = night ? Colors.white : const Color(0xFF283959);
    return Semantics(
      label: d == null ? 'Welcome to Sora' : '${d.label} weather card',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/weather/${d?.artwork ?? 'clear'}.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0, 0.4),
              filterQuality: FilterQuality.medium,
              cacheWidth: 1000,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.48, 0.72, 1],
                  colors:
                      night
                          ? [
                            const Color(0xFF242C68).withValues(alpha: 0.4),
                            Colors.transparent,
                            Colors.transparent,
                            const Color(0xFF222850).withValues(alpha: 0.75),
                          ]
                          : [
                            Colors.white.withValues(alpha: 0.83),
                            Colors.white.withValues(alpha: 0.12),
                            Colors.transparent,
                            const Color(0xFF263E63).withValues(alpha: 0.65),
                          ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: (night
                                  ? Colors.white
                                  : const Color(0xFF5368BD))
                              .withValues(alpha: night ? 0.18 : 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          d == null
                              ? 'YOUR SKY, REIMAGINED'
                              : d.isCurrent
                              ? 'CURRENT WEATHER'
                              : 'DAILY FORECAST',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (d != null)
                        Text(
                          d.shortDate,
                          style: TextStyle(
                            fontSize: 12,
                            color: fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    d == null ? 'A sky worth\nstepping into.' : d.label,
                    style: TextStyle(
                      fontSize: d == null ? 34 : 27,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: fg,
                    ),
                  ),
                  if (d != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${temperature(d.temperature)}${fahrenheit ? 'F' : 'C'}',
                      style: TextStyle(
                        fontSize: 76,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -4,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color:
                            night
                                ? const Color(
                                  0xFF313665,
                                ).withValues(alpha: 0.72)
                                : Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            conditionLabel(d.code),
                            style: TextStyle(
                              fontSize: 14,
                              color: fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'H ${temperature(d.high)}   L ${temperature(d.low)}${d.isCurrent ? '' : '  ·  Daily range'}',
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d == null
                                  ? 'A little wonder, every day.'
                                  : d.isCurrent
                                  ? 'Your little window to the world.'
                                  : 'A new day. A whole new sky.',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(color: Colors.black26, blurRadius: 5),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              d == null
                                  ? 'Weather • Air quality • Local insights'
                                  : d.isCurrent
                                  ? 'Swipe to see what tomorrow brings  →'
                                  : 'Forecast high shown • Swipe to explore',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                shadows: [
                                  Shadow(color: Colors.black38, blurRadius: 5),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFFFFE2A9),
                        size: 22,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
