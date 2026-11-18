import 'dart:ui';
import 'package:intl/intl.dart';
import 'messages.dart';

/// The app has one locale, shared by UI labels and background notifications.
/// User-entered bank/device names and protocol fault identifiers are never translated.
class AppStrings {
  static const languageNames = {
    'ru': 'Русский',
    'en': 'English',
    'de': 'Deutsch',
    'fr': 'Français',
    'es': 'Español',
    'it': 'Italiano',
    'tr': 'Türkçe',
    'el': 'Ελληνικά',
    'hr': 'Hrvatski',
  };
  static final supportedLocales = languageNames.keys
      .map((code) => Locale(code))
      .toList(growable: false);

  // Russian is the source language for standalone widgets/tests. The app sets
  // its resolved locale before building any UI or initializing data sources.
  static Locale locale = const Locale('ru');

  static Locale resolve(String preference, List<Locale> deviceLocales) {
    if (languageNames.containsKey(preference)) return Locale(preference);
    for (final device in deviceLocales) {
      if (languageNames.containsKey(device.languageCode)) {
        return Locale(device.languageCode);
      }
    }
    return const Locale('en');
  }

  static String text(String key, [List<Object?> values = const []]) {
    final template =
        messages[locale.languageCode]?[key] ?? messages['en']?[key];
    if (template == null) {
      throw ArgumentError.value(key, 'key', 'Unknown translation');
    }
    // A single pass keeps placeholders inside user names from being interpreted.
    return template.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < values.length ? '${values[index]}' : match[0]!;
    });
  }

  /// CLDR rules handle Croatian 2–4/22–24 as well as singular forms.
  static String plural(String key, int count) {
    final category = Intl.pluralLogic(
      count,
      one: 'one',
      few: 'few',
      other: 'other',
      locale: locale.languageCode,
    );
    return text('${key}_$category', [count]);
  }

  static String source(String value) {
    final key = sourceKeys[value];
    return key == null ? value : text(key);
  }
}

String tr(String key, [List<Object?> values = const []]) =>
    AppStrings.text(key, values);
