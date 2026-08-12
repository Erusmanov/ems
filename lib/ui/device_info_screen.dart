import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme/app_theme.dart';
import 'debug_registers_screen.dart';

/// Информация об устройстве — ОТДЕЛЬНЫЙ экран (решение Михаила 13.07:
/// не совмещать с графиком напряжений ячеек). Строки-меню в согласованном стиле.
class DeviceInfoScreen extends StatefulWidget {
  final String bankId;
  final String deviceId;

  const DeviceInfoScreen({
    super.key,
    required this.bankId,
    required this.deviceId,
  });

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  String get bankId => widget.bankId;
  String get deviceId => widget.deviceId;

  int? _sleepSec; // текущий sleep-таймер BMS (0x8A), null — не прочитан
  int? _boardNumber; // адрес платы (intranet 0x100), null — не прочитан

  @override
  void initState() {
    super.initState();
    _loadSleep();
    _loadBoardNumber();
  }

  Future<void> _loadSleep() async {
    final v = await context.read<AppState>().readSleepTime(deviceId);
    if (mounted) setState(() => _sleepSec = v);
  }

  Future<void> _loadBoardNumber() async {
    final v = await context.read<AppState>().readBoardNumber(deviceId);
    if (mounted) setState(() => _boardNumber = v);
  }

  /// Смена адреса платы (0..32) — нужен для различения батарей на RS485-шине
  /// и картплоттерах NMEA2000 (Михаил 26.07: «без этого приложение теряет
  /// смысл»). Запись безопасная: запись → перечитка → сверка.
  Future<void> _pickBoardNumber() async {
    final controller =
        TextEditingController(text: _boardNumber?.toString() ?? '');
    final entered = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Адрес платы',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Число от 1 до 16. Уникальный адрес нужен, чтобы батареи '
              'различались на шине RS485 и на приборах NMEA2000. '
              'Внимание: на NMEA2000-приборах номер отображается на единицу '
              'меньше (адрес 14 виден как «.13») — так устроено у Daly.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 20),
              decoration: InputDecoration(
                labelText: 'Адрес',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.cardBorder)),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 1 || v > 16) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Допустимый адрес — от 1 до 16 (проверено на BMS)')));
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Записать',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    final err =
        await context.read<AppState>().writeBoardNumber(deviceId, entered);
    if (!mounted) return;
    if (err == null) {
      setState(() => _boardNumber = entered);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Адрес платы записан и проверен. Если приборы NMEA2000 '
              'не увидели смену — перезагрузите BMS.')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка записи: $err')));
    }
  }

  String get _sleepLabel {
    final s = _sleepSec;
    if (s == null) return '…';
    if (s >= 65535) return 'Никогда';
    if (s % 3600 == 0) return '${s ~/ 3600} ч';
    if (s % 60 == 0) return '${s ~/ 60} мин';
    return '$s с';
  }

  /// Диалог выбора sleep-таймера: пресеты + «Никогда». Запись безопасная:
  /// запись → контрольное чтение → сверка (протокол ТЗ M5).
  Future<void> _pickSleep() async {
    const presets = <(String, int)>[
      ('5 минут', 300),
      ('30 минут', 1800),
      ('1 час', 3600),
      ('4 часа', 14400),
      ('12 часов', 43200),
      ('Никогда (не засыпать)', 65535),
    ];
    final chosen = await showModalBottomSheet<int>(
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
              child: Text('ТАЙМЕР СНА BMS',
                  style: TextStyle(
                      color: AppColors.textLabel,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0)),
            ),
            for (final (label, sec) in presets)
              ListTile(
                dense: true,
                leading: Icon(
                    sec >= 65535
                        ? Icons.block
                        : Icons.nightlight_outlined,
                    size: 18,
                    color: sec == _sleepSec
                        ? AppColors.accent
                        : AppColors.textSecondary),
                title: Text(label,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 14)),
                trailing: sec == _sleepSec
                    ? const Icon(Icons.check,
                        size: 18, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.pop(ctx, sec),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final err =
        await context.read<AppState>().writeSleepTime(deviceId, chosen);
    if (!mounted) return;
    if (err == null) {
      setState(() => _sleepSec = chosen);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Таймер сна записан в BMS и проверен')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка записи: $err')));
    }
  }

  Future<void> _restart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Перезагрузить BMS?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          'BMS перезапустится, связь с батареей на несколько секунд оборвётся. '
          'Затем подключите её заново через поиск, если не подхватится сама.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Перезагрузить',
                style: TextStyle(color: AppColors.socRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<AppState>().restartBms(deviceId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err == null
            ? 'Команда перезагрузки отправлена'
            : 'Ошибка: $err')));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bank = app.banks.where((b) => b.id == bankId).firstOrNull;
    final battery =
        bank?.batteries.where((b) => b.deviceId == deviceId).firstOrNull;

    if (battery == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.bg),
        body: Center(
          child: Text('Устройство не найдено',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final df = DateFormat('dd.MM.yyyy');
    final rows = <(IconData, String, String)>[
      (Icons.bluetooth, 'BLE-имя', battery.bleName),
      (Icons.memory, 'Версия ПО BMS', battery.swVersion ?? '—'),
      (Icons.qr_code_2, 'Имя устройства', battery.serialNumber ?? '—'),
      (
        Icons.event,
        'Дата производства',
        battery.manufactureDate != null
            ? df.format(battery.manufactureDate!)
            : '—'
      ),
      (Icons.grid_view_rounded, 'Количество ячеек', '${battery.cellCount}'),
      (Icons.thermostat, 'Датчиков температуры', '${battery.tempSensorCount}'),
      (Icons.replay, 'Циклов заряд/разряд', '${battery.cycles}'),
      (
        Icons.settings_input_component,
        'MOS заряд / разряд',
        '${battery.mosCharge ? 'вкл' : 'выкл'} / ${battery.mosDischarge ? 'вкл' : 'выкл'}'
      ),
      (
        Icons.thermostat_auto,
        'Температура min / max',
        '${battery.tempMin.toStringAsFixed(0)} / ${battery.tempMax.toStringAsFixed(0)} °C'
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Об устройстве',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          for (final (icon, label, value) in rows)
            Container(
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          // Управление BMS (этап M5): sleep-таймер (0x8A) и рестарт (0xF0).
          // Запрос Михаила 21.07: батареи засыпают, зависшую не ресетнуть из Daly.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text('УПРАВЛЕНИЕ BMS',
                style: TextStyle(
                    color: AppColors.textLabel,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0)),
          ),
          InkWell(
            onTap: battery.connected ? _pickBoardNumber : null,
            child: Container(
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(Icons.tag, size: 15, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Адрес платы (RS485 / NMEA2000)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                  ),
                  Text(
                      battery.connected
                          ? (_boardNumber?.toString() ?? '…')
                          : 'нет связи',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textLabel),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: battery.connected ? _pickSleep : null,
            child: Container(
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(Icons.nightlight_outlined,
                      size: 15, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Таймер сна',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                  ),
                  Text(battery.connected ? _sleepLabel : 'нет связи',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textLabel),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: battery.connected ? _restart : null,
            child: Container(
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  const Icon(Icons.restart_alt,
                      size: 15, color: AppColors.socRed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Перезагрузить BMS',
                        style: TextStyle(
                            color: battery.connected
                                ? AppColors.socRed
                                : AppColors.textLabel,
                            fontSize: 14)),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textLabel),
                ],
              ),
            ),
          ),
          // Тех-строка — только в режиме разработчика (5 тапов по версии
          // в Настройках): дистрибьюторам и клиентам её видеть не нужно (24.07)
          if (context.watch<SettingsState>().devMode)
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DebugRegistersScreen(deviceId: deviceId),
            )),
            child: Container(
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 15, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Сырые регистры (отладка)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textLabel),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
