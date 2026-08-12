import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme/app_theme.dart';
import '../version.dart';

/// Вкладка «Настройки» (телефонная часть этапа Э4/M5): тема, язык,
/// пороги SOC. Строки-меню в согласованном стиле (иконка в размер заглавной
/// буквы + текст в одну строку); группы параметров — отдельными оттенками фона
/// (решение Михаила 30.06).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static int _versionTaps = 0;
  static DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  /// 5 быстрых тапов по «Версия» — переключение режима разработчика
  /// (открывает «Сырые регистры»; спрятано от дистрибьюторов, 24.07).
  void _onVersionTap(BuildContext context, SettingsState settings) {
    final now = DateTime.now();
    if (now.difference(_lastTap).inSeconds > 2) _versionTaps = 0;
    _lastTap = now;
    _versionTaps++;
    if (_versionTaps >= 5) {
      _versionTaps = 0;
      settings.devMode = !settings.devMode;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(settings.devMode
              ? 'Режим разработчика включён'
              : 'Режим разработчика выключен')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Настройки',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _sectionTitle('ВНЕШНИЙ ВИД'),
          _group([
            _row(
              context,
              icon: Icons.dark_mode_outlined,
              label: 'Тема',
              value: settings.themeMode.label,
              onTap: () => _pickTheme(context, settings),
            ),
            _row(
              context,
              icon: Icons.language,
              label: 'Язык',
              value: switch (settings.language) {
                'ru' => 'Русский',
                'en' => 'English',
                _ => 'Как в системе',
              },
              onTap: () => _pickLanguage(context, settings),
            ),
          ]),
          _sectionTitle('ПОРОГИ SOC'),
          _group([
            _row(
              context,
              icon: Icons.notifications_none,
              label: 'Порог «Уведомление»',
              value: '${settings.socWarning.round()} %',
              onTap: () => _pickThreshold(context, settings, warning: true),
            ),
            _row(
              context,
              icon: Icons.error_outline,
              label: 'Порог «Критический»',
              value: '${settings.socCritical.round()} %',
              onTap: () => _pickThreshold(context, settings, warning: false),
            ),
            _switchRow(
              context,
              icon: Icons.battery_alert_outlined,
              label: 'Уведомление о низком SOC',
              value: settings.lowSocNotify,
              onChanged: (v) => settings.lowSocNotify = v,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              'Пороги задают цвет кольца SOC на главном экране: выше '
              '«Уведомления» — зелёный, между порогами — жёлтый, ниже '
              '«Критического» — красный.',
              style: TextStyle(color: AppColors.textLabel, fontSize: 11),
            ),
          ),
          _sectionTitle('ДАННЫЕ'),
          _group([
            _switchRow(
              context,
              icon: Icons.science_outlined,
              label: 'Демо-банки (без железа)',
              value: settings.demoMode,
              onChanged: (v) {
                settings.demoMode = v;
                final app = context.read<AppState>();
                v ? app.initMock() : app.initFromStore();
              },
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              'Вкл — три демонстрационных банка с имитацией данных. '
              'Выкл — только реальные устройства; ваши банки сохраняются '
              'и восстанавливаются при запуске.',
              style: TextStyle(color: AppColors.textLabel, fontSize: 11),
            ),
          ),
          _sectionTitle('О ПРИЛОЖЕНИИ'),
          _group([
            _row(
              context,
              icon: Icons.info_outline,
              label: 'Версия',
              value: appVersion,
              onTap: () => _onVersionTap(context, settings),
            ),
          ]),
        ],
      ),
    );
  }

  // ---------- Диалоги выбора ----------

  Future<void> _pickTheme(BuildContext context, SettingsState settings) async {
    final mode = await _pickFromList<AppThemeMode>(
      context,
      title: 'Тема',
      items: AppThemeMode.values,
      selected: settings.themeMode,
      labelOf: (m) => m.label,
      iconOf: (m) => switch (m) {
        AppThemeMode.dark => Icons.dark_mode_outlined,
        AppThemeMode.light => Icons.light_mode_outlined,
        AppThemeMode.system => Icons.brightness_auto_outlined,
      },
    );
    if (mode != null) settings.themeMode = mode;
  }

  Future<void> _pickLanguage(
      BuildContext context, SettingsState settings) async {
    final lang = await _pickFromList<String>(
      context,
      title: 'Язык',
      items: const ['system', 'ru', 'en'],
      selected: settings.language,
      labelOf: (l) => switch (l) {
        'ru' => 'Русский',
        'en' => 'English (перевод — этап Э4)',
        _ => 'Как в системе (авто по региону)',
      },
      iconOf: (l) =>
          l == 'system' ? Icons.brightness_auto_outlined : Icons.language,
    );
    if (lang != null) settings.language = lang;
  }

  Future<void> _pickThreshold(BuildContext context, SettingsState settings,
      {required bool warning}) async {
    final appState = context.read<AppState>();
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _ThresholdDialog(
        title: warning ? 'Порог «Уведомление»' : 'Порог «Критический»',
        initial: warning ? settings.socWarning : settings.socCritical,
        min: warning ? settings.socCritical + 1 : 1,
        max: warning ? 95 : settings.socWarning - 1,
        accent: warning ? AppColors.socYellow : AppColors.socRed,
      ),
    );
    if (result == null) return;
    if (warning) {
      settings.setSocThresholds(warning: result);
    } else {
      settings.setSocThresholds(critical: result);
    }
    appState.applySocThresholds(
        warning: settings.socWarning, critical: settings.socCritical);
  }

  Future<T?> _pickFromList<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required T selected,
    required String Function(T) labelOf,
    required IconData Function(T) iconOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(title.toUpperCase(),
                  style: TextStyle(
                      color: AppColors.textLabel,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0)),
            ),
            for (final item in items)
              ListTile(
                leading: Icon(iconOf(item),
                    size: 18,
                    color: item == selected
                        ? AppColors.accent
                        : AppColors.textSecondary),
                title: Text(labelOf(item),
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 14)),
                trailing: item == selected
                    ? Icon(Icons.check,
                        size: 18, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, item),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- Элементы списка ----------

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text,
            style: TextStyle(
                color: AppColors.textLabel,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0)),
      );

  /// Группа строк — на своём оттенке фона (карточка на общем фоне).
  Widget _group(List<Widget> rows) => Container(
        color: AppColors.card,
        child: Column(children: rows),
      );

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14)),
            ),
            Text(value,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textLabel),
            ],
          ],
        ),
      ),
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
            activeTrackColor: AppColors.accent.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

/// Диалог выбора порога SOC ползунком.
class _ThresholdDialog extends StatefulWidget {
  final String title;
  final double initial;
  final double min;
  final double max;
  final Color accent;

  const _ThresholdDialog({
    required this.title,
    required this.initial,
    required this.min,
    required this.max,
    required this.accent,
  });

  @override
  State<_ThresholdDialog> createState() => _ThresholdDialogState();
}

class _ThresholdDialogState extends State<_ThresholdDialog> {
  late double _value = widget.initial.clamp(widget.min, widget.max);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(widget.title,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
      // Степпер вместо Slider: у Slider на устройстве Михаила рендер-глюк
      // («серый столб», видео 02.08). Кнопки −/+ надёжны везде.
      content: SizedBox(
        width: 300,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              onPressed: _value > widget.min
                  ? () => setState(() => _value = _value - 1)
                  : null,
              icon: Icon(Icons.remove_circle_outline,
                  color: _value > widget.min
                      ? widget.accent
                      : AppColors.textLabel),
            ),
            SizedBox(
              width: 110,
              child: Text('${_value.round()} %',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: widget.accent,
                      fontSize: 36,
                      fontWeight: FontWeight.w700)),
            ),
            IconButton(
              iconSize: 36,
              onPressed: _value < widget.max
                  ? () => setState(() => _value = _value + 1)
                  : null,
              icon: Icon(Icons.add_circle_outline,
                  color: _value < widget.max
                      ? widget.accent
                      : AppColors.textLabel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _value),
          child:
              Text('Сохранить', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    );
  }
}
