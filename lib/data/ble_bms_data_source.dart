import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/bms_data.dart';
import '../protocol/modbus.dart';
import '../protocol/daly_parser.dart';
import 'bms_data_source.dart';

/// Реальный драйвер Daly BMS поверх BLE-моста DL-B40.
/// UUID (из даташита DL-B40): service fff0, notify fff1, write fff2.
///
/// ВНИМАНИЕ: проверяется на реальном стенде (Daly BMS + DL-B40). Логика сборки
/// кадров и тайминги могут потребовать калибровки на железе.
class BleBmsDataSource implements BmsDataSource {
  static const String serviceFrag = 'fff0';
  static const String notifyFrag = 'fff1';
  static const String writeFrag = 'fff2';

  final BluetoothDevice device;
  /// Имя для отображения (серийник из advertising при первом подключении).
  /// platformName у восстановленного устройства бывает пуст — из-за этого
  /// имена «пропадали» на экране (видео Михаила 03.08).
  final String? overrideName;
  final Duration pollInterval;
  final Duration commandTimeout;

  final _controller = StreamController<BatteryData>.broadcast();
  final _rxBuffer = <int>[];
  BluetoothCharacteristic? _notifyChar;
  BluetoothCharacteristic? _writeChar;
  StreamSubscription? _notifySub;
  Completer<List<int>>? _pending;
  bool _connected = false;
  bool _running = false;
  bool _reconnecting = false;
  StreamSubscription? _connStateSub;
  BatteryData? _lastData;
  double? _fullCapacity;
  String? _swVersion;
  String? _serialNumber;
  DateTime? _mfgDate;
  bool _infoTried = false;
  List<int>? _lastRawRegs;

  @override
  List<int>? get lastRawRegisters => _lastRawRegs;

  BleBmsDataSource(
    this.device, {
    this.overrideName,
    this.pollInterval = const Duration(seconds: 1),
    this.commandTimeout = const Duration(milliseconds: 1200),
  });

  @override
  String get deviceId => device.remoteId.str;
  @override
  String get bleName {
    final o = overrideName;
    if (o != null && o.isNotEmpty) return o;
    return device.platformName;
  }
  @override
  bool get isConnected => _connected;
  @override
  Stream<BatteryData> get readings => _controller.stream;

  /// Число попыток подключения. Android BLE часто рвёт первую попытку
  /// (GATT 133/timeout сразу после скана) — ретраи с паузой решают это,
  /// чтобы пользователю не приходилось тыкать по устройству много раз.
  static const _connectAttempts = 4;

  @override
  Future<void> start() async {
    Object? lastError;
    for (var attempt = 1; attempt <= _connectAttempts; attempt++) {
      try {
        await _startOnce();
        return;
      } catch (e) {
        lastError = e;
        _connected = false;
        _notifyChar = null;
        _writeChar = null;
        await _notifySub?.cancel();
        _notifySub = null;
        try {
          await device.disconnect();
        } catch (_) {}
        if (attempt < _connectAttempts) {
          // Пауза растёт с номером попытки — даём стеку BLE «отдышаться»
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    throw lastError ?? StateError('Не удалось подключиться');
  }

  Future<void> _startOnce() async {
    await device.connect(timeout: const Duration(seconds: 12));
    _connected = true;

    final services = await device.discoverServices();
    for (final s in services) {
      if (!s.uuid.str.toLowerCase().contains(serviceFrag)) continue;
      for (final c in s.characteristics) {
        final u = c.uuid.str.toLowerCase();
        if (u.contains(notifyFrag)) _notifyChar = c;
        if (u.contains(writeFrag)) _writeChar = c;
      }
    }
    if (_notifyChar == null || _writeChar == null) {
      // Показываем, какие сервисы устройство отдаёт на самом деле — так по
      // скрину ошибки видно, какой там BLE-модуль (не DL-B40 → другой протокол).
      final found = services
          .map((s) => s.uuid.str.toLowerCase())
          .where((u) => !u.startsWith('180')) // системные GAP/GATT не интересны
          .take(6)
          .join(', ');
      throw StateError(
          'Не найдены характеристики DL-B40 (fff1/fff2). '
          'Сервисы устройства: ${found.isEmpty ? 'нет данных' : found}');
    }

    await _notifyChar!.setNotifyValue(true);
    _notifySub = _notifyChar!.lastValueStream.listen(_onNotify);

    // Авто-восстановление: после ресета BMS / провала связи (тест 26.07)
    // соединение рвётся — чиним его фоном, а не показываем замершие данные.
    await _connStateSub?.cancel();
    _connStateSub = device.connectionState.listen((st) {
      if (st == BluetoothConnectionState.disconnected && _running) {
        _onDisconnected();
      }
    });

    if (!_running) {
      _running = true;
      unawaited(_pollLoop());
    }
  }

  void _onDisconnected() {
    _connected = false;
    // Сразу показываем «нет связи» вместо замерших значений
    final last = _lastData;
    if (last != null && !_controller.isClosed) {
      _controller.add(last.copyWith(connected: false));
    }
    unawaited(_reconnectLoop());
  }

  /// Цикл восстановления связи: попытка каждые 5 секунд, пока живёт источник.
  Future<void> _reconnectLoop() async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      while (_running && !_connected) {
        await Future.delayed(const Duration(seconds: 5));
        if (!_running) return;
        try {
          await _startOnce();
        } catch (_) {
          // следующая попытка
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _connected = false;
    await _connStateSub?.cancel();
    await _notifySub?.cancel();
    try {
      await device.disconnect();
    } catch (_) {}
    if (!_controller.isClosed) await _controller.close();
  }

  void _onNotify(List<int> chunk) {
    _rxBuffer.addAll(chunk);
    // Ресинхронизация по адресу slave: 0xD2 (BLE-Modbus) или 0x51
    // (ответ intranet-протокола на запросы 0x81)
    while (_rxBuffer.isNotEmpty &&
        _rxBuffer.first != Modbus.defaultSlave &&
        _rxBuffer.first != Modbus.intranetResponse) {
      _rxBuffer.removeAt(0);
    }
    if (_rxBuffer.length < 3) return;
    // Длина кадра зависит от функции: 0x03 несёт байт длины, эхо записи
    // 0x06/0x10 — фиксированные 8 байт, ошибка (fn|0x80) — 5 байт.
    final fn = _rxBuffer[1];
    final int expected;
    if (fn & 0x80 != 0) {
      expected = 5;
    } else if (fn == Modbus.fnReadHolding) {
      expected = 3 + _rxBuffer[2] + 2;
    } else {
      expected = 8; // 0x06 / 0x10
    }
    if (_rxBuffer.length < expected) return;
    final frame = _rxBuffer.sublist(0, expected);
    _rxBuffer.removeRange(0, expected);
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.complete(frame);
    }
  }

  // Запросы к BMS строго по одному: опрос и разовые операции (чтение/запись
  // настроек) идут через общую цепочку, иначе ответы перепутаются.
  Future<void> _chain = Future.value();
  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _chain.then((_) => op());
    // Цепочка продолжается независимо от исхода операции — ошибка одного
    // запроса (таймаут) не должна ломать очередь для следующих.
    _chain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<List<int>> _request(List<int> frame) =>
      _serialized(() => _requestNow(frame));

  Future<List<int>> _requestNow(List<int> frame) async {
    _rxBuffer.clear();
    _pending = Completer<List<int>>();
    await _writeChar!.write(frame, withoutResponse: true);
    return _pending!.future.timeout(commandTimeout);
  }

  /// Чтение одиночного настроечного регистра (например, sleep-таймер 0x8A).
  Future<int> readSetting(int reg) async {
    final resp = await _request(Modbus.readHolding(reg, 1));
    final regs =
        Modbus.parseReadResponse(resp, expectedSlave: Modbus.defaultSlave);
    if (regs.isEmpty) throw StateError('Пустой ответ BMS');
    return regs.first;
  }

  /// Запись одиночного регистра (0x06) с проверкой эха.
  Future<void> writeSetting(int reg, int value) async {
    final resp = await _request(Modbus.writeSingle(reg, value));
    if (resp.length < 8 || resp[1] & 0x80 != 0) {
      throw StateError('BMS отклонила запись (код ${resp.length > 2 ? resp[2] : '?'})');
    }
  }

  /// Чтение регистра intranet-протокола (запрос 0x81 → ответ 0x51).
  /// Используется для board number (0x100) — адреса платы RS485/NMEA2000.
  Future<int> intranetRead(int reg) async {
    final resp = await _request(
        Modbus.readHolding(reg, 1, slave: Modbus.intranetRequest));
    final regs = Modbus.parseReadResponse(resp,
        expectedSlave: Modbus.intranetResponse);
    if (regs.isEmpty) throw StateError('Пустой ответ BMS');
    return regs.first;
  }

  /// Запись регистра intranet-протокола с проверкой эха (ответ 0x51).
  Future<void> intranetWrite(int reg, int value) async {
    final resp = await _request(
        Modbus.writeSingle(reg, value, slave: Modbus.intranetRequest));
    if (resp.length < 8 ||
        resp[0] != Modbus.intranetResponse ||
        resp[1] & 0x80 != 0) {
      throw StateError('BMS отклонила запись адреса '
          '(код ${resp.length > 2 ? resp[2] : '?'})');
    }
  }

  /// ASCII из 16-битных регистров (по 2 байта в регистре), мусор отсекаем.
  static String? _asciiFromRegs(List<int> regs) {
    final bytes = <int>[];
    for (final r in regs) {
      bytes.add((r >> 8) & 0xFF);
      bytes.add(r & 0xFF);
    }
    final s = String.fromCharCodes(bytes.where((b) => b >= 0x20 && b < 0x7F))
        .trim();
    return s.isEmpty ? null : s;
  }

  Future<List<int>> _readRegs(int start, int count) async {
    final resp = await _request(Modbus.readHolding(start, count));
    return Modbus.parseReadResponse(resp, expectedSlave: Modbus.defaultSlave);
  }

  /// Разовое чтение паспортных данных BMS: версия ПО, серийник платы, дата
  /// производства (регистры 0xA9+, 0xB9+, 0xCC — карта Daly Modbus).
  Future<void> _readDeviceInfo() async {
    _infoTried = true;
    try {
      _swVersion = _asciiFromRegs(
          await _readRegs(DalyReg.swVersionStart, DalyReg.swVersionLen));
    } catch (_) {}
    try {
      _serialNumber = _asciiFromRegs(
          await _readRegs(DalyReg.machineCodeStart, DalyReg.machineCodeLen));
    } catch (_) {}
    try {
      final r = await _readRegs(DalyReg.mfgDateStart, DalyReg.mfgDateLen);
      if (r.length >= 2) {
        // YYMMDD00: r0 = 0xYYMM, r1 = 0xDD00
        final yy = (r[0] >> 8) & 0xFF;
        final mm = r[0] & 0xFF;
        final dd = (r[1] >> 8) & 0xFF;
        if (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31 && yy >= 15 && yy <= 60) {
          _mfgDate = DateTime(2000 + yy, mm, dd);
        }
      }
    } catch (_) {}
  }

  Future<void> _pollLoop() async {
    while (_running) {
      try {
        // Полную ёмкость читаем редко (раз в ~30 опросов)
        if (_fullCapacity == null) {
          try {
            final resp =
                await _request(Modbus.readHolding(DalyReg.ratedCapacity, 1));
            final regs = Modbus.parseReadResponse(resp,
                expectedSlave: Modbus.defaultSlave);
            if (regs.isNotEmpty) _fullCapacity = regs.first * 0.1;
          } catch (_) {/* не критично */}
        }
        // Паспортные данные — один раз за сессию подключения
        if (!_infoTried) await _readDeviceInfo();

        final resp =
            await _request(Modbus.readHolding(0x00, DalyReg.realtimeCount));
        final regs =
            Modbus.parseReadResponse(resp, expectedSlave: Modbus.defaultSlave);
        _lastRawRegs = regs;
        final data = DalyParser.parseRealtime(
          regs,
          deviceId: deviceId,
          bleName: bleName,
          fullCapacity: _fullCapacity,
          swVersion: _swVersion,
          serialNumber: _serialNumber,
          manufactureDate: _mfgDate,
        );
        _lastData = data;
        if (!_controller.isClosed) _controller.add(data);
      } on TimeoutException {
        // пропуск цикла; при серии таймаутов — пометить отключённым
      } catch (_) {
        // ошибка CRC/длины — пропускаем кадр
      }
      await Future.delayed(pollInterval);
    }
  }
}
