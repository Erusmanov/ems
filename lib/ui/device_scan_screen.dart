import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/bank.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme/app_theme.dart';
import 'banks_screen.dart' show BankEditDialog;

/// Экран поиска и подключения BLE-устройств (Daly BMS через мост DL-B40).
/// UUID сервиса моста — fff0; имя АКБ обычно вида 2605-235-0001.
class DeviceScanScreen extends StatefulWidget {
  /// Если задан — найденное устройство привязывается к этому банку.
  final String? targetBankId;

  /// Целевой банк обязан получить минимум две АКБ (флоу смены типа
  /// одиночного банка на параллельный/последовательный, видео 03.08).
  final bool requireTwo;

  /// Параметры нового банка (флоу «Создать банк»): банк появится только
  /// вместе с первой подключённой АКБ (пустых банков не бывает, 22.07 п.3).
  final ({String name, String iconId, BankType type})? pendingBank;

  const DeviceScanScreen(
      {super.key, this.targetBankId, this.pendingBank, this.requireTwo = false});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final _results = <ScanResult>[];
  // Накопитель: батареи рекламируют себя редко и не все попадают в один цикл
  // скана (Михаил 24.07: из 5-6 рядом видно 1-3). Держим всё найденное между
  // циклами и лишь обновляем записи — «Обновить» больше не стирает список.
  final _found = <String, ScanResult>{};
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanningSub;
  bool _scanning = false;
  String? _status;
  String? _connectingId;
  // По умолчанию показываем ТОЛЬКО АКБ (решение Михаила 20.07): колонки,
  // наушники и «Без имени» скрыты за переключателем «Показать все».
  bool _showAll = false;
  // Банк, созданный в этой сессии скана (parallel/series): следующие
  // подключения идут в него, пока АКБ меньше двух.
  String? _lockedBankId;

  @override
  void initState() {
    super.initState();
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });
    _init();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _scanningSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _init() async {
    if (await FlutterBluePlus.isSupported == false) {
      setState(() => _status = 'BLE не поддерживается на этом устройстве');
      return;
    }
    // Разрешения Android 12+
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    // Включить адаптер при необходимости (Android)
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _status = null);
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      if (!mounted) return;
      setState(() {
        for (final r in list) {
          // Не затираем запись с именем безымянным дублем того же устройства
          final prev = _found[r.device.remoteId.str];
          if (prev != null && nameOf(prev).isNotEmpty && nameOf(r).isEmpty) {
            continue;
          }
          _found[r.device.remoteId.str] = r;
        }
        _results
          ..clear()
          ..addAll(_found.values);
        // Похожие на BMS — сверху, дальше по уровню сигнала
        _results.sort((a, b) {
          final ab = _looksLikeBms(a) ? 0 : 1;
          final bb = _looksLikeBms(b) ? 0 : 1;
          if (ab != bb) return ab - bb;
          return b.rssi.compareTo(a.rssi);
        });
      });
    });
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 30),
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (e) {
      setState(() => _status = 'Ошибка сканирования: $e');
    }
  }

  /// Имя устройства: сперва из advertising-пакета (advName — так батареи Daly
  /// транслируют серийник), затем кэшированное системное platformName.
  static String nameOf(ScanResult r) {
    final adv = r.advertisementData.advName;
    if (adv.isNotEmpty) return adv;
    return r.device.platformName;
  }

  bool _looksLikeBms(ScanResult r) {
    final name = nameOf(r);
    // Форматы имён Daly: «2605-235-0001» (мост DL-B40), серийники вида
    // «12120150STH0001» / «48165150RSCAN0002» (цифры + буквенный код),
    // явные «DL-…» / «daly».
    final byName = RegExp(r'\d{3,4}-\d{2,3}-\d{3,4}').hasMatch(name) ||
        RegExp(r'^\d{6,}[A-Za-z0-9]*$').hasMatch(name) ||
        name.toUpperCase().startsWith('DL-') ||
        name.toLowerCase().contains('daly');
    final byService = r.advertisementData.serviceUuids
        .any((g) => g.str.toLowerCase().contains('fff0'));
    return byName || byService;
  }

  /// Выбор банка для нового устройства: существующие (с проверкой состава)
  /// или «Новый банк…» через стандартный диалог.
  Future<({String? bankId, ({String name, String iconId, BankType type})? newBank})?>
      _chooseBank(AppState app) async {
    final result = await showModalBottomSheet<Object>(
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
              child: Text('В КАКОЙ БАНК ДОБАВИТЬ УСТРОЙСТВО?',
                  style: TextStyle(
                      color: AppColors.textLabel,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0)),
            ),
            for (final bank in app.banks)
              Builder(builder: (context) {
                final veto = app.canAddBatteryTo(bank);
                return ListTile(
                  dense: true,
                  enabled: veto == null,
                  leading: Icon(Icons.battery_charging_full,
                      size: 18,
                      color: veto == null
                          ? AppColors.accent
                          : AppColors.textLabel),
                  title: Text(bank.name,
                      style: TextStyle(
                          color: veto == null
                              ? AppColors.textPrimary
                              : AppColors.textLabel,
                          fontSize: 14)),
                  subtitle: veto != null
                      ? Text('одиночный банк уже занят',
                          style: TextStyle(
                              color: AppColors.textLabel, fontSize: 11))
                      : null,
                  onTap: () => Navigator.pop(ctx, bank.id),
                );
              }),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add, size: 18, color: AppColors.accent),
              title: Text('Новый банк…',
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              onTap: () => Navigator.pop(ctx, '__new__'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return null;
    if (result == '__new__') {
      final spec = await showDialog<(String, String, BankType)>(
        context: context,
        builder: (_) => const BankEditDialog(),
      );
      if (spec == null) return null;
      final (name, iconId, type) = spec;
      return (bankId: null, newBank: (name: name, iconId: iconId, type: type));
    }
    return (bankId: result as String, newBank: null);
  }

  Future<void> _connect(BluetoothDevice device, String name) async {
    final app = context.read<AppState>();

    // Куда отнести устройство (Михаил 22.07 п.4): к целевому банку, к новому
    // (флоу «Создать банк») или спросить пользователя — существующий/новый.
    String? bankId = _lockedBankId ?? widget.targetBankId;
    var newBank = _lockedBankId == null ? widget.pendingBank : null;
    if (bankId == null && newBank == null) {
      final choice = await _chooseBank(app);
      if (choice == null) return; // отмена
      bankId = choice.bankId;
      newBank = choice.newBank;
    }

    setState(() => _connectingId = device.remoteId.str);
    await FlutterBluePlus.stopScan();
    // Пауза после остановки скана — снижает шанс GATT-ошибки на Android
    await Future.delayed(const Duration(milliseconds: 300));
    final err = await app.connectBle(device,
        bankId: bankId, displayName: name, newBank: newBank);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (err == null) {
      // Параллельный/последовательный банк требует минимум две АКБ (26.07):
      // после первой не уходим — переключаемся на добавление в этот же банк.
      final spec = newBank;
      if (spec != null && spec.type != BankType.single) {
        final created = app.banks
            .where((b) =>
                b.batteries.any((bat) => bat.deviceId == device.remoteId.str))
            .firstOrNull;
        if (created != null && created.batteries.length < 2 && mounted) {
          setState(() => _lockedBankId = created.id);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'АКБ добавлена. «${created.name}» — ${created.type.label.toLowerCase()}: добавьте минимум ещё одну АКБ')));
          _startScan();
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Устройство подключено')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось подключиться: $err')),
      );
    }
  }

  /// Выход со скана при parallel/series банке с одной АКБ (видео 02.08):
  /// предлагаем достроить, сделать одиночным или удалить банк.
  Future<bool> _confirmLeave() async {
    // Гонка из видео 03.08 (в4): выйти во время подключения -> банк создаётся
    // за спиной. Пока идёт подключение, выход заблокирован.
    if (_connectingId != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Подождите — идёт подключение устройства')));
      return false;
    }
    final id = _lockedBankId ??
        (widget.requireTwo ? widget.targetBankId : null);
    if (id == null) return true;
    final app = context.read<AppState>();
    final bank = app.banks.where((b) => b.id == id).firstOrNull;
    if (bank == null ||
        bank.type == BankType.single ||
        bank.batteries.length >= 2) {
      return true;
    }
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('В банке одна АКБ',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          '«${bank.name}» — ${bank.type.label.toLowerCase()}, ему нужно '
          'минимум две АКБ. Что сделать?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Добавить вторую',
                style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'single'),
            child: Text('Сделать одиночным',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Удалить банк',
                style: TextStyle(color: AppColors.socRed)),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    switch (choice) {
      case 'single':
        app.renameBank(bank.id, type: BankType.single);
        return true;
      case 'delete':
        await app.deleteBank(bank.id);
        return true;
      default:
        return false; // остаёмся добавлять вторую
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Подключение устройства',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        actions: [
          if (_scanning)
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent)),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh, color: AppColors.accent),
              onPressed: _startScan,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_status != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_status!,
                  style: TextStyle(color: AppColors.statusDischarge)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                      _scanning
                          ? 'Идёт поиск…'
                          : 'Найдено АКБ: ${_results.where(_looksLikeBms).length}',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(
                      _showAll
                          ? 'Только АКБ'
                          : 'Показать все (${_results.length})',
                      style: TextStyle(
                          color: AppColors.textLabel, fontSize: 12)),
                ),
              ],
            ),
          ),
          // Подключённые сейчас батареи не видны в эфире (BLE-моносоединение)
          // — показываем их отдельным блоком, чтобы картина была полной (24.08)
          Builder(builder: (context) {
            final online = context
                .watch<AppState>()
                .banks
                .expand((bk) => bk.batteries.map((bat) => (bk, bat)))
                .where((e) => e.$2.connected)
                .toList();
            if (online.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                  child: Text('НА СВЯЗИ (НЕ ВИДНЫ В ПОИСКЕ)',
                      style: TextStyle(
                          color: AppColors.textLabel,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8)),
                ),
                for (final (bk, bat) in online)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.bluetooth_connected,
                          size: 14, color: AppColors.socGreen),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${bat.bleName} — банк «${bk.name}»',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ),
                    ]),
                  ),
                Divider(height: 12, color: AppColors.cardBorder),
              ],
            );
          }),
          Expanded(
            child: Builder(builder: (context) {
              final visible = _showAll
                  ? _results
                  : _results.where(_looksLikeBms).toList();
              if (visible.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        _scanning
                            ? 'Поиск АКБ поблизости…'
                            : 'АКБ не найдены.\nУбедитесь, что батарея включена и '
                              'не подключена к другому приложению, затем '
                              'обновите поиск. Кнопка «Показать все» выводит '
                              'остальные BLE-устройства.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textLabel)),
                  ),
                );
              }
              return ListView.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => Divider(
                    height: 1, color: AppColors.cardBorder),
                itemBuilder: (_, i) => _tile(visible[i]),
              );
            }),
          ),
        ],
      ),
      ),
    );
  }

  Widget _tile(ScanResult r) {
    final rawName = nameOf(r);
    final name = rawName.isNotEmpty ? rawName : 'Без имени';
    final isBms = _looksLikeBms(r);
    final connecting = _connectingId == r.device.remoteId.str;
    // АКБ, уже назначенная в банк, помечается и не подключается повторно
    // (коммент Михаила 24.08: «в списке ничем не отличается»)
    final ownerBank = context
        .read<AppState>()
        .banks
        .where((bk) =>
            bk.batteries.any((bat) => bat.deviceId == r.device.remoteId.str))
        .firstOrNull;
    return ListTile(
      leading: Icon(
        isBms ? Icons.battery_charging_full : Icons.bluetooth,
        color: isBms ? AppColors.accent : AppColors.textSecondary,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
          if (ownerBank != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.socGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('В БАНКЕ',
                  style: TextStyle(color: AppColors.socGreen, fontSize: 10)),
            )
          else if (isBms)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('АКБ',
                  style: TextStyle(color: AppColors.accent, fontSize: 10)),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          _SignalBars(rssi: r.rssi),
          const SizedBox(width: 8),
          Expanded(
            child: Text(r.device.remoteId.str,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textLabel, fontSize: 12)),
          ),
        ],
      ),
      trailing: connecting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent))
          : Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: connecting
          ? null
          : () {
              if (ownerBank != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Эта АКБ уже в банке «${ownerBank.name}». Управлять ею '
                        'можно из вкладки «Банки».')));
                return;
              }
              // Клиенты добавляли в банк колонки и наушники (видео 17.08):
              // подключение не-АКБ разрешено только в режиме разработчика.
              final isDev = context.read<SettingsState>().devMode;
              if (!isBms && !isDev) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Это устройство не похоже на АКБ EM-Power — '
                        'подключить его нельзя. АКБ помечены жёлтым значком.')));
                return;
              }
              _connect(r.device, name);
            },
    );
  }
}

/// Сила сигнала столбиками, как в приложении Daly (просьба Михаила 25.07):
/// 4 ступени по RSSI вместо цифр dBm.
class _SignalBars extends StatelessWidget {
  final int rssi;
  const _SignalBars({required this.rssi});

  @override
  Widget build(BuildContext context) {
    final level = rssi >= -60
        ? 4
        : rssi >= -70
            ? 3
            : rssi >= -80
                ? 2
                : 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            margin: const EdgeInsets.only(right: 2),
            width: 3.5,
            height: 5.0 + i * 3,
            decoration: BoxDecoration(
              color: i < level ? AppColors.socGreen : AppColors.ringTrack,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
      ],
    );
  }
}
