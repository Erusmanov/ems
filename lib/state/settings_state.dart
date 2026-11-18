import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

/// Режим темы приложения (ТЗ: тёмная по умолчанию, светлая, авто по системе).
enum AppThemeMode { dark, light, system }

extension AppThemeModeLabel on AppThemeMode {
  String get label => switch (this) {
        AppThemeMode.dark => tr('theme_dark'),
        AppThemeMode.light => tr('theme_light'),
        AppThemeMode.system => tr('theme_system'),
      };
}

/// Настройки приложения (телефонная часть этапа Э4/M5): тема, язык,
/// пороги SOC по умолчанию. Хранятся локально в Hive — без сервера/облака.
class SettingsState extends ChangeNotifier {
  final Box _box;

  SettingsState(this._box);

  static const boxName = 'settings';

  AppThemeMode get themeMode => AppThemeMode.values[
      (_box.get('themeMode', defaultValue: AppThemeMode.dark.index) as int)
          .clamp(0, AppThemeMode.values.length - 1)];

  String get language {
    final saved = _box.get('language', defaultValue: 'system');
    return saved is String && (saved == 'system' || AppStrings.languageNames.containsKey(saved)) ? saved : 'system';
  }

  double get socWarning =>
      (_box.get('socWarning', defaultValue: 50.0) as num).toDouble();

  double get socCritical =>
      (_box.get('socCritical', defaultValue: 20.0) as num).toDouble();

  bool get lowSocNotify =>
      _box.get('lowSocNotify', defaultValue: true) as bool;

  /// Демо-банки (мок без железа). По умолчанию ВЫКЛ — старт с нуля, как в реале
  /// (решение Михаила 15.07).
  bool get demoMode => _box.get('demoMode', defaultValue: false) as bool;

  set demoMode(bool v) {
    _box.put('demoMode', v);
    notifyListeners();
  }

  set themeMode(AppThemeMode v) {
    _box.put('themeMode', v.index);
    notifyListeners();
  }

  set language(String v) {
    if (v != 'system' && !AppStrings.languageNames.containsKey(v)) {
      throw ArgumentError.value(v, 'language');
    }
    _box.put('language', v);
    notifyListeners();
  }

  /// Пороги хранятся согласованными: критический всегда ниже уведомления.
  void setSocThresholds({double? warning, double? critical}) {
    var w = warning ?? socWarning;
    var c = critical ?? socCritical;
    w = w.clamp(5, 95).toDouble();
    c = c.clamp(1, w - 1).toDouble();
    _box.put('socWarning', w);
    _box.put('socCritical', c);
    notifyListeners();
  }

  set lowSocNotify(bool v) {
    _box.put('lowSocNotify', v);
    notifyListeners();
  }

  /// Режим разработчика: открывает отладочные экраны (сырые регистры).
  /// Включается 5 быстрыми тапами по строке «Версия» в настройках.
  bool get devMode => _box.get('devMode', defaultValue: false) as bool;

  set devMode(bool v) {
    _box.put('devMode', v);
    notifyListeners();
  }

  /// Тёмная ли тема при данной системной яркости.
  bool resolveDark(Brightness platform) => switch (themeMode) {
        AppThemeMode.dark => true,
        AppThemeMode.light => false,
        AppThemeMode.system => platform == Brightness.dark,
      };
}
