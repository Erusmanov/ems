import 'dart:async';
import 'dart:math' as math;
import '../models/bms_data.dart';
import 'bms_data_source.dart';

/// Профиль виртуальной АКБ для мок-режима (работа без реального железа).
class MockProfile {
  final String deviceId;
  final String bleName;
  final int cellCount;
  final double fullCapacity; // Ah
  final double baseSoc; // %
  final double baseCurrent; // A (+заряд / -разряд / 0 покой)
  final String serial;
  final int cycles;
  final DateTime manufactureDate;
  final List<String> faults;

  const MockProfile({
    required this.deviceId,
    required this.bleName,
    required this.cellCount,
    required this.fullCapacity,
    required this.baseSoc,
    required this.baseCurrent,
    required this.serial,
    required this.cycles,
    required this.manufactureDate,
    this.faults = const [],
  });
}

/// Генерирует реалистичные данные АКБ с лёгким «дыханием» значений.
/// Подключается к интерфейсу [BmsDataSource] так же, как реальный BLE-драйвер.
class MockBmsDataSource implements BmsDataSource {
  @override
  List<int>? get lastRawRegisters => null;

  final MockProfile profile;
  final Duration interval;
  final _controller = StreamController<BatteryData>.broadcast();
  final _rnd = math.Random();
  Timer? _timer;
  bool _connected = false;

  MockBmsDataSource(this.profile, {this.interval = const Duration(seconds: 1)});

  @override
  String get deviceId => profile.deviceId;
  @override
  String get bleName => profile.bleName;
  @override
  bool get isConnected => _connected;
  @override
  Stream<BatteryData> get readings => _controller.stream;

  @override
  Future<void> start() async {
    _connected = true;
    _emit();
    _timer = Timer.periodic(interval, (_) => _emit());
  }

  @override
  Future<void> stop() async {
    _connected = false;
    _timer?.cancel();
    await _controller.close();
  }

  double _jitter(double v, double amp) => v + (_rnd.nextDouble() - 0.5) * amp;

  void _emit() {
    if (_controller.isClosed) return;
    final status = profile.baseCurrent > 0.1
        ? ChargeStatus.charging
        : profile.baseCurrent < -0.1
            ? ChargeStatus.discharging
            : ChargeStatus.standby;

    final current = status == ChargeStatus.standby
        ? _jitter(0, 0.2)
        : _jitter(profile.baseCurrent, profile.baseCurrent.abs() * 0.08);

    final soc = profile.baseSoc.clamp(0, 100).toDouble();
    final remaining = profile.fullCapacity * soc / 100.0;

    // Ячейки: вокруг среднего с небольшим разбросом
    final cellAvg = 3.30 + soc / 100.0 * 0.10; // 3.30..3.40 V примерно
    final cells = <double>[
      for (int i = 0; i < profile.cellCount; i++)
        double.parse(_jitter(cellAvg, 0.012).toStringAsFixed(3)),
    ];

    final temp = _jitter(25.0, 1.5);

    _controller.add(BatteryData(
      deviceId: profile.deviceId,
      bleName: profile.bleName,
      totalVoltage: double.parse(
          (cells.fold(0.0, (s, c) => s + c)).toStringAsFixed(2)),
      current: double.parse(current.toStringAsFixed(1)),
      soc: soc,
      remainingCapacity: double.parse(remaining.toStringAsFixed(1)),
      fullCapacity: profile.fullCapacity,
      tempAvg: double.parse(temp.toStringAsFixed(1)),
      tempMax: double.parse((temp + 1.2).toStringAsFixed(1)),
      tempMin: double.parse((temp - 1.0).toStringAsFixed(1)),
      cycles: profile.cycles,
      status: status,
      mosCharge: true,
      mosDischarge: true,
      cells: cells,
      tempSensorCount: 2,
      soh: 100,
      faults: profile.faults,
      swVersion: '60_231116_001T',
      serialNumber: profile.serial,
      manufactureDate: profile.manufactureDate,
      lastUpdate: DateTime.now(),
      connected: true,
    ));
  }

  /// Три демо-АКБ как на референс-макете.
  static List<MockProfile> demoProfiles() => [
        MockProfile(
          deviceId: 'mock-house',
          bleName: '2605-235-0001',
          cellCount: 16,
          fullCapacity: 200,
          baseSoc: 76,
          baseCurrent: -20.5, // разряд
          serial: '2605-235-0001',
          cycles: 128,
          manufactureDate: DateTime(2024, 4, 12),
        ),
        MockProfile(
          deviceId: 'mock-service',
          bleName: '2605-235-0002',
          cellCount: 16,
          fullCapacity: 100,
          baseSoc: 85,
          baseCurrent: 15.2, // заряд
          serial: '2605-235-0002',
          cycles: 86,
          manufactureDate: DateTime(2024, 6, 18),
        ),
        MockProfile(
          deviceId: 'mock-trolling',
          bleName: '2605-234-0001',
          cellCount: 4,
          fullCapacity: 100,
          baseSoc: 60,
          baseCurrent: -8.7, // разряд
          serial: '2605-234-0001',
          cycles: 54,
          manufactureDate: DateTime(2024, 5, 2),
        ),
      ];
}
