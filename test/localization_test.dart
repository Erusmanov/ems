import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:empower_bms/l10n/app_strings.dart';
import 'package:empower_bms/l10n/messages.dart';
import 'package:empower_bms/state/settings_state.dart';
import 'package:empower_bms/ui/settings_screen.dart';

void main() {
  tearDown(() => AppStrings.locale = const Locale('ru'));

  test(
    'preferred device languages, regional variants and English fallback',
    () {
      expect(
        AppStrings.resolve('system', [const Locale('de', 'AT')]),
        const Locale('de'),
      );
      expect(
        AppStrings.resolve('system', [
          const Locale('ja'),
          const Locale('fr', 'CA'),
        ]),
        const Locale('fr'),
      );
      expect(
        AppStrings.resolve('system', [const Locale('ja')]),
        const Locale('en'),
      );
      expect(AppStrings.resolve('system', []), const Locale('en'));
      expect(
        AppStrings.resolve('ru', [const Locale('en')]),
        const Locale('ru'),
      );
      for (final code in AppStrings.languageNames.keys) {
        expect(AppStrings.resolve('system', [Locale(code)]).languageCode, code);
      }
    },
  );

  test('all languages contain every key and preserve interpolation fields', () {
    final placeholders = RegExp(r'\{\d+\}');
    for (final language in AppStrings.languageNames.keys) {
      expect(messages[language]!.keys.toSet(), messages['ru']!.keys.toSet());
      for (final entry in messages['ru']!.entries) {
        final value = messages[language]![entry.key]!;
        expect(value.trim(), isNotEmpty, reason: '$language/${entry.key}');
        expect(
          placeholders.allMatches(value).map((m) => m[0]).toSet(),
          placeholders.allMatches(entry.value).map((m) => m[0]).toSet(),
          reason: '$language/${entry.key}',
        );
      }
    }
  });

  test('bank names containing placeholder-like text are preserved', () {
    AppStrings.locale = const Locale('en');
    expect(
      tr('message_055', ['Bank {1}', 'Removed']),
      '“Bank {1}” will be deleted. Removed',
    );
  });

  test(
    'fresh install follows system; manual choice survives reopening Hive',
    () async {
      final dir = await Directory.systemTemp.createTemp('empower_locale_');
      Hive.init(dir.path);
      var box = await Hive.openBox('locale_persistence');
      var settings = SettingsState(box);
      expect(settings.language, 'system');
      settings.language = 'el';
      await box.flush();
      settings.dispose();
      await box.close();
      box = await Hive.openBox('locale_persistence');
      settings = SettingsState(box);
      expect(settings.language, 'el');
      settings.language = 'system';
      await box.flush();
      expect(settings.language, 'system');
      await box.put('language', 'invalid');
      expect(settings.language, 'system');
      settings.dispose();
      await box.close();
      await dir.delete(recursive: true);
    },
  );

  for (final code in AppStrings.languageNames.keys) {
    testWidgets('settings and scrollable language picker at 320px: $code', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = SettingsState(_MemoryBox())..language = code;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: Consumer<SettingsState>(
            builder: (_, state, child) {
              AppStrings.locale = AppStrings.resolve(state.language, [
                const Locale('de'),
              ]);
              return MaterialApp(
                locale: AppStrings.locale,
                supportedLocales: AppStrings.supportedLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: const SettingsScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(messages[code]!['nav_settings']!), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.language).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Hrvatski').last,
        100,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Hrvatski').last);
      await tester.pumpAndSettle();
      expect(settings.language, 'hr');
      expect(find.text('Postavke'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.language).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(messages['hr']!['lang_auto']!).last);
      await tester.pumpAndSettle();
      expect(settings.language, 'system');
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    });
  }
}

class _MemoryBox extends Fake implements Box {
  final Map<dynamic, dynamic> _values = {};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _values[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _values[key] = value;
  }
}
