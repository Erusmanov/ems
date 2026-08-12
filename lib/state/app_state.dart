import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive/hive.dart';
import '../data/bms_data_source.dart';
import '../data/ble_bms_data_source.dart';
import '../data/mock_bms_data_source.dart';
import '../models/bank.dart';
import '../models/bank_icons.dart';
import '../models/bms_data.dart';
import '../protocol/daly_parser.dart';
import '../services/notification_service.dart';
import '../utils/estimates.dart';

/// Центральное состояние приложения. Держит банки, источники данных и
/// скользящие средние тока для расчёта оставшегося времени.
///
/// Банки пользователя сохраняются в Hive (имя, иконка, тип, пороги, привязанные
/// устройства) и восстанавливаются при запуске с попыткой BLE-переподключения.
/// Демо-банки (мок) НЕ сохраняются.
class AppState extends ChangeNotifier {
  static const banksBoxName = 'banks';

  final Box? _banksBox;
  final List<Bank> _banks = [];
  final Map<String, BmsDataSource> _sources = {};
  final Map<String, RollingAverage> _bankCurrentAvg = {};
  final List<StreamSubscription> _subs = [];

  AppState({Box? banksBox, double socWarning = 50, double socCritical = 20})
      : _banksBox = banksBox,
        _socWarning = socWarning,
        _socCritical = socCritical;

  // Глобальные пороги SOC из настроек: применяются ко всем банкам, включая
  // новые (раньше новый банк получал 50/20 и «не краснел» — видео 02.08)
  double _socWarning;
  double _socCritical;

  List<Bank> get banks => List.unmodifiable(_banks);
  bool get anyConnected => _banks.any((b) => b.connected);

  bool _isMockBank(Bank b) => b.id.startsWith('bank-mock');

  // ---------- Персистентность банков ----------

  void _persist() {
    if (_banksBox == null) return;
    final data = [
      for (final b in _banks.where((b) => !_isMockBank(b)))
        {
          'id': b.id,
          'name': b.name,
          'icon': b.iconId,
          'type': b.type.index,
          'warn': b.socWarning,
          'crit': b.socCritical,
          'devices': [
            for (final bat in b.batteries)
              {'id': bat.deviceId, 'name': bat.bleName},
          ],
        },
    ];
    _banksBox.put('banks', data);
  }

  /// Восстановление банков из хранилища (реальный режим, старт приложения).
  /// Батареи создаются отключёнными, затем фоном пробуем BLE-переподключение.
  Future<void> initFromStore() async {
    await _disposeSources();
    _banks.clear();
    final raw = _banksBox?.get('banks');
    if (raw is List) {
      for (final e in raw) {
        final m = Map<dynamic, dynamic>.from(e as Map);
        final devices = (m['devices'] as List?) ?? const [];
        if (devices.isEmpty) continue; // банков без АКБ не бывает (22.07 п.3)
        final bank = Bank(
          id: m['id'] as String,
          name: m['name'] as String,
          iconId: normalizeBankIconId(m['icon']),
          type: BankType
              .values[((m['type'] as int?) ?? 0).clamp(0, BankType.values.length - 1)],
          socWarning: _socWarning,
          socCritical: _socCritical,
          batteries: [
            for (final d in devices)
              BatteryData.placeholder(
                deviceId: (d as Map)['id'] as String,
                bleName: (d['name'] as String?) ?? (d['id'] as String),
              ),
          ],
        );
        // Инвариант состава: parallel/series с одной АКБ невозможен —
        // если приложение убили на середине добора (видео 11.08),
        // банк возвращается к одиночному типу сам.
        if (bank.type != BankType.single && bank.batteries.length < 2) {
          bank.type = BankType.single;
        }
        _banks.add(bank);
        _bankCurrentAvg[bank.id] = RollingAverage();
      }
    }
    _persist();
    notifyListeners();
    // Фоновое переподключение известных устройств
    for (final bank in _banks) {
      for (final bat in bank.batteries) {
        unawaited(_tryReconnect(bat.deviceId));
      }
    }
  }

  /// Попытка переподключения к известному устройству по сохранённому id.
  Future<void> _tryReconnect(String deviceId) async {
    if (_sources.containsKey(deviceId)) return;
    try {
      final device = BluetoothDevice.fromId(deviceId);
      // Имя из сохранённого банка: platformName у fromId-устройства пуст
      final knownName = _banks
          .expand((b) => b.batteries)
          .where((b) => b.deviceId == deviceId)
          .map((b) => b.bleName)
          .where((n) => n.isNotEmpty)
          .firstOrNull;
      final source = BleBmsDataSource(device, overrideName: knownName);
      _sources[deviceId] = source;
      _subs.add(source.readings.listen(_onReading));
      await source.start();
      notifyListeners();
    } catch (_) {
      _sources.remove(deviceId);
      // осталась отключённой — пользователь может подключить через скан
    }
  }

  /// Инициализация демо-режима: 3 одиночных банка как на референс-макете.
  Future<void> initMock() async {
    await _disposeSources();
    _banks.clear();

    final profiles = MockBmsDataSource.demoProfiles();
    final iconIds = ['home_general', 'auxiliary_other', 'trolling_motor'];
    final names = ['House Battery', 'Service Battery', 'Trolling Motor'];

    for (var i = 0; i < profiles.length; i++) {
      final p = profiles[i];
      final battery = BatteryData(
        deviceId: p.deviceId,
        bleName: p.bleName,
        totalVoltage: 0,
        current: 0,
        soc: p.baseSoc,
        remainingCapacity: 0,
        fullCapacity: p.fullCapacity,
        tempAvg: 25,
        tempMax: 26,
        tempMin: 24,
        cycles: p.cycles,
        status: ChargeStatus.standby,
        mosCharge: true,
        mosDischarge: true,
        cells: List.filled(p.cellCount, 3.3),
        tempSensorCount: 2,
        faults: const [],
        serialNumber: p.serial,
        manufactureDate: p.manufactureDate,
        lastUpdate: DateTime.now(),
        connected: false,
      );
      final bank = Bank(
        id: 'bank-${p.deviceId}',
        name: names[i],
        iconId: iconIds[i],
        type: BankType.single,
        batteries: [battery],
      );
      _banks.add(bank);
      _bankCurrentAvg[bank.id] = RollingAverage();

      final source = MockBmsDataSource(p);
      _sources[p.deviceId] = source;
      _subs.add(source.readings.listen(_onReading));
      await source.start();
    }
    notifyListeners();
  }

  /// Логика состава банков (Михаил 22.07): одиночный — максимум 1 АКБ.
  /// null — добавлять можно, иначе текст запрета.
  String? canAddBatteryTo(Bank bank) {
    if (bank.type == BankType.single && bank.batteries.isNotEmpty) {
      return 'В одиночный банк можно добавить только одну АКБ. '
          'Смените тип банка на параллельный или последовательный.';
    }
    return null;
  }

  /// Подключение реального устройства Daly BMS по BLE (через мост DL-B40).
  /// [bankId] — привязать к существующему банку; [newBank] — создать банк
  /// с заданными параметрами и первой АКБ. Возвращает текст ошибки или null.
  Future<String?> connectBle(BluetoothDevice device,
      {String? bankId,
      String? displayName,
      ({String name, String iconId, BankType type})? newBank}) async {
    final id = device.remoteId.str;
    if (_sources.containsKey(id)) return 'Устройство уже подключено';
    // Имя: из advertising (передаёт экран скана) → системное → id
    final name = (displayName != null && displayName.isNotEmpty &&
            displayName != 'Без имени')
        ? displayName
        : (device.platformName.isNotEmpty ? device.platformName : id);

    // Устройство уже числится в каком-то банке (восстановлено из хранилища,
    // но не подключено) — просто поднимаем источник, без дублирования.
    final owningBank = _banks
        .where((b) => b.batteries.any((bat) => bat.deviceId == id))
        .firstOrNull;

    final targetBank = owningBank ??
        (bankId == null
            ? null
            : _banks.where((b) => b.id == bankId).firstOrNull);
    if (owningBank == null && targetBank != null) {
      final veto = canAddBatteryTo(targetBank);
      if (veto != null) return veto;
    }
    Bank? createdBank;
    try {
      final source = BleBmsDataSource(device, overrideName: name);
      if (owningBank == null) {
        final battery = BatteryData.placeholder(deviceId: id, bleName: name);
        if (targetBank != null) {
          targetBank.batteries.add(battery);
        } else {
          createdBank = Bank(
            id: 'ble-$id',
            name: newBank?.name ?? name,
            iconId: newBank?.iconId ?? defaultBankIconId,
            type: newBank?.type ?? BankType.single,
            batteries: [battery],
            socWarning: _socWarning,
            socCritical: _socCritical,
          );
          _banks.insert(0, createdBank);
          _bankCurrentAvg[createdBank.id] = RollingAverage();
        }
      }
      _sources[id] = source;
      _subs.add(source.readings.listen(_onReading));
      // Подписка ДО start — чтобы не пропустить первый кадр
      final firstReading = source.readings.first;
      await source.start();
      // Валидация: устройство должно ответить как Daly BMS. Иначе колонка/
      // наушники «подключаются», а банк создаётся с нулями (баг Михаила 20.07).
      final BatteryData firstData;
      try {
        firstData = await firstReading.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        throw StateError(
            'Устройство подключилось, но не отвечает как Daly BMS — банк не создан');
      }
      // Совместимость АКБ в банке (тест 26.07: 12В и 36В в параллели — «бабах»):
      // число ячеек (=номинал напряжения) строго равно, ёмкость в пределах 15%.
      if (owningBank == null && targetBank != null) {
        final ref = targetBank.batteries
            .where((b) =>
                b.deviceId != id && b.connected && b.cellCount > 0)
            .firstOrNull;
        if (ref != null) {
          if (firstData.cellCount != ref.cellCount) {
            throw StateError(
                'АКБ различаются по напряжению (${firstData.cellCount}S против '
                '${ref.cellCount}S) — устанавливать их в общий банк недопустимо.');
          }
          // Номинальная ёмкость (заводской регистр 0x80) — строго равна
          // (правка Михаила 27.07: номинал либо равен, либо нет)
          final refRated = ref.ratedCapacityAh;
          final newRated = firstData.ratedCapacityAh;
          if (refRated != null &&
              newRated != null &&
              (refRated - newRated).abs() > 0.05) {
            throw StateError(
                'АКБ различаются по номинальной ёмкости '
                '(${newRated.toStringAsFixed(1)} Ач против '
                '${refRated.toStringAsFixed(1)} Ач) — устанавливать их '
                'в общий банк недопустимо.');
          }
        }
      }
      _persist();
      notifyListeners();
      return null;
    } catch (e) {
      if (owningBank == null) {
        targetBank?.batteries.removeWhere((b) => b.deviceId == id);
        if (createdBank != null) {
          _banks.remove(createdBank);
          _bankCurrentAvg.remove(createdBank.id);
        }
      }
      final src = _sources.remove(id);
      if (src != null) {
        try {
          await src.stop();
        } catch (_) {}
      }
      notifyListeners();
      return e is StateError ? e.message : e.toString();
    }
  }

  /// Отвязка батареи от банка: останавливает источник, батарею убирает.
  Future<void> removeBattery(String bankId, String deviceId) async {
    final bank = _banks.where((b) => b.id == bankId).firstOrNull;
    if (bank == null) return;
    bank.batteries.removeWhere((b) => b.deviceId == deviceId);
    final src = _sources.remove(deviceId);
    if (src != null) await src.stop();
    _persist();
    notifyListeners();
  }

  // Банки, по которым уже отправлен push о критическом SOC (edge-trigger:
  // одно уведомление на пересечение порога, сброс при заряде выше порога+3%)
  final Set<String> _lowSocNotified = {};

  void _onReading(BatteryData data) {
    for (final bank in _banks) {
      final idx = bank.batteries.indexWhere((b) => b.deviceId == data.deviceId);
      if (idx >= 0) {
        final oldName = bank.batteries[idx].bleName;
        bank.batteries[idx] = (data.bleName.isEmpty && oldName.isNotEmpty)
            ? data.copyWithName(oldName)
            : data;
        _bankCurrentAvg[bank.id]?.add(bank.aggregate.current);
        _checkLowSoc(bank);
        break;
      }
    }
    notifyListeners();
  }

  void _checkLowSoc(Bank bank) {
    if (!bank.connected) return;
    final soc = bank.aggregate.soc;
    if (soc <= bank.socCritical && !_lowSocNotified.contains(bank.id)) {
      _lowSocNotified.add(bank.id);
      NotificationService.lowSoc(bank.name, soc, bank.socCritical);
    } else if (soc > bank.socCritical + 3) {
      _lowSocNotified.remove(bank.id); // гистерезис против дребезга
    }
  }

  /// Активные события для бейджа на вкладке «Уведомления»:
  /// аварии BMS + пороговые события SOC (та же логика, что список).
  int get activeAlertCount {
    var n = 0;
    for (final bank in _banks) {
      for (final b in bank.batteries) {
        n += b.faults.length;
      }
      final agg = bank.aggregate;
      if (bank.batteries.length > 1 && agg.socSpread > 10) n++;
      if (bank.connected && agg.soc <= bank.socWarning) n++;
    }
    return n;
  }

  // ---------- Управление банками (этап Э3/M4) ----------

  int _bankSeq = 0;

  /// Создание пустого банка. Устройства привязываются позже через BLE-скан.
  Bank createBank({
    required String name,
    required String iconId,
    required BankType type,
  }) {
    final bank = Bank(
      id: 'user-${_bankSeq++}-${name.hashCode.toRadixString(16)}',
      name: name,
      iconId: iconId,
      type: type,
      batteries: [],
      socWarning: _socWarning,
      socCritical: _socCritical,
    );
    _banks.add(bank);
    _bankCurrentAvg[bank.id] = RollingAverage();
    _persist();
    notifyListeners();
    return bank;
  }

  /// Возвращает текст ошибки, если смена типа противоречит составу банка.
  String? renameBank(String bankId,
      {String? name, String? iconId, BankType? type}) {
    final bank = _banks.where((b) => b.id == bankId).firstOrNull;
    if (bank == null) return 'Банк не найден';
    if (type != null && type != bank.type) {
      if (type == BankType.single && bank.batteries.length > 1) {
        return 'В одиночном банке не может быть больше одной АКБ — '
            'сначала отвяжите лишние батареи.';
      }
      // single -> parallel/series разрешено и с одной АКБ: это единственный
      // путь расширить одиночный банк (замкнутый круг из теста 26.07 п.1)
      bank.type = type;
    }
    if (name != null && name.trim().isNotEmpty) bank.name = name.trim();
    if (iconId != null) bank.iconId = iconId;
    _persist();
    notifyListeners();
    return null;
  }

  /// Удаление банка: останавливает и отвязывает источники его батарей.
  Future<void> deleteBank(String bankId) async {
    final idx = _banks.indexWhere((b) => b.id == bankId);
    if (idx < 0) return;
    final bank = _banks.removeAt(idx);
    _bankCurrentAvg.remove(bankId);
    for (final battery in bank.batteries) {
      final src = _sources.remove(battery.deviceId);
      if (src != null) await src.stop();
    }
    _persist();
    notifyListeners();
  }

  // ---------- Управление BMS (этап M5: sleep-таймер, рестарт) ----------

  BleBmsDataSource? _bleSourceOf(String deviceId) {
    final src = _sources[deviceId];
    return src is BleBmsDataSource ? src : null;
  }

  /// Чтение sleep-таймера (0x8A), секунды. null — устройство не подключено/мок.
  Future<int?> readSleepTime(String deviceId) async {
    final src = _bleSourceOf(deviceId);
    if (src == null) return null;
    try {
      return await src.readSetting(DalyReg.sleepWaitTime);
    } catch (_) {
      return null;
    }
  }

  /// Безопасная запись sleep-таймера: запись → контрольное чтение → сверка.
  /// Возвращает null при успехе, иначе текст ошибки.
  Future<String?> writeSleepTime(String deviceId, int seconds) async {
    final src = _bleSourceOf(deviceId);
    if (src == null) return 'Устройство не подключено';
    try {
      await src.writeSetting(DalyReg.sleepWaitTime, seconds.clamp(0, 65535));
      final check = await src.readSetting(DalyReg.sleepWaitTime);
      if (check != seconds.clamp(0, 65535)) {
        return 'BMS вернула другое значение: $check с';
      }
      return null;
    } catch (e) {
      return e is StateError ? e.message : e.toString();
    }
  }

  /// Чтение адреса платы (board number, intranet-регистр 0x100).
  Future<int?> readBoardNumber(String deviceId) async {
    final src = _bleSourceOf(deviceId);
    if (src == null) return null;
    try {
      return await src.intranetRead(DalyReg.intranetBoardNumber);
    } catch (_) {
      return null;
    }
  }

  /// Безопасная запись адреса платы: запись → контрольное чтение → сверка.
  Future<String?> writeBoardNumber(String deviceId, int number) async {
    final src = _bleSourceOf(deviceId);
    if (src == null) return 'Устройство не подключено';
    try {
      final v = number.clamp(1, 16); // BMS реально принимает 1..16 (тест 26.07)
      await src.intranetWrite(DalyReg.intranetBoardNumber, v);
      final check = await src.intranetRead(DalyReg.intranetBoardNumber);
      if (check != v) return 'BMS вернула другое значение: $check';
      return null;
    } catch (e) {
      return e is StateError ? e.message : e.toString();
    }
  }

  /// Перезагрузка BMS (запись в 0xF0). После рестарта связь оборвётся —
  /// устройство надо будет подключить заново (или дождаться автоподхвата).
  Future<String?> restartBms(String deviceId) async {
    final src = _bleSourceOf(deviceId);
    if (src == null) return 'Устройство не подключено';
    try {
      await src.writeSetting(DalyReg.cmdRestart, 1);
      return null;
    } on TimeoutException {
      // BMS часто уходит в рестарт, не успев ответить — это успех
      return null;
    } catch (e) {
      return e is StateError ? e.message : e.toString();
    }
  }

  /// Сырые регистры устройства для отладочного экрана (null — мок/нет чтений).
  List<int>? rawRegistersFor(String deviceId) =>
      _sources[deviceId]?.lastRawRegisters;

  /// Применение порогов SOC из настроек ко всем банкам (цвет кольца).
  void applySocThresholds({required double warning, required double critical}) {
    _socWarning = warning;
    _socCritical = critical;
    for (final bank in _banks) {
      bank.socWarning = warning;
      bank.socCritical = critical;
    }
    _persist(); // без сохранения пороги слетали после перезапуска (видео 31.07)
    notifyListeners();
  }

  /// Оставшееся время для банка (по скользящему среднему тока).
  TimeEstimate timeFor(Bank bank) {
    final agg = bank.aggregate;
    final avg = _bankCurrentAvg[bank.id];
    final current = (avg == null || avg.isEmpty) ? agg.current : avg.value;
    return TimeEstimate.compute(
      status: agg.status,
      avgCurrent: current,
      remaining: agg.remaining,
      full: agg.full,
    );
  }

  Future<void> _disposeSources() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final src in _sources.values) {
      await src.stop();
    }
    _sources.clear();
    _bankCurrentAvg.clear();
  }

  @override
  void dispose() {
    _disposeSources();
    super.dispose();
  }
}
