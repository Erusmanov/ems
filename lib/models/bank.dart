import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'bms_data.dart';

enum BankType { single, parallel, series }

extension BankTypeLabel on BankType {
  String get label => switch (this) {
        BankType.single => 'Одиночная АКБ',
        BankType.parallel => 'Параллельный банк',
        BankType.series => 'Последовательный банк',
      };
  String get short => switch (this) {
        BankType.single => 'single',
        BankType.parallel => 'parallel',
        BankType.series => 'series',
      };
}

/// Банк АКБ. Пороги SOC — на банк (для визуализации кольца), хранятся локально,
/// в регистры BMS НЕ пишутся (решение заказчика 22.06).
class Bank {
  final String id;
  String name;
  String iconId; // id SVG-иконки из bank_icons.dart (набор заказчика)
  BankType type; // редактируемый (решение Михаила 15.07, п.3)
  final List<BatteryData> batteries;

  /// Пороги SOC для цвета кольца (%). По умолчанию 20/50 — совпадает с
  /// исходным правилом цвета из ТЗ/макета.
  double socWarning;
  double socCritical;

  Bank({
    required this.id,
    required this.name,
    required this.iconId,
    required this.type,
    required this.batteries,
    this.socWarning = 50,
    this.socCritical = 20,
  });

  bool get connected => batteries.any((b) => b.connected);

  /// Сводные параметры банка по формулам ТЗ §12.
  BankAggregate get aggregate {
    final live = batteries.where((b) => b.connected).toList();
    if (live.isEmpty) {
      return const BankAggregate.empty();
    }
    switch (type) {
      case BankType.single:
        final b = live.first;
        return BankAggregate(
          voltage: b.totalVoltage,
          current: b.current,
          power: b.power,
          soc: b.soc,
          remaining: b.remainingCapacity,
          full: b.fullCapacity,
          tempAvg: b.tempAvg,
          status: b.status,
          socSpread: 0,
          faults: b.faults,
        );
      case BankType.parallel:
        final totalCurrent = live.fold(0.0, (s, b) => s + b.current);
        final totalPower = live.fold(0.0, (s, b) => s + b.power);
        final remaining = live.fold(0.0, (s, b) => s + b.remainingCapacity);
        final full = live.fold(0.0, (s, b) => s + b.fullCapacity);
        final avgV = live.fold(0.0, (s, b) => s + b.totalVoltage) / live.length;
        // SOC — средневзвешенное по ёмкости
        final soc = full > 0
            ? live.fold(0.0, (s, b) => s + b.soc * b.fullCapacity) / full
            : live.fold(0.0, (s, b) => s + b.soc) / live.length;
        return BankAggregate(
          voltage: avgV,
          current: totalCurrent,
          power: totalPower,
          soc: soc,
          remaining: remaining,
          full: full,
          tempAvg: live.fold(0.0, (s, b) => s + b.tempAvg) / live.length,
          status: _commonStatus(live),
          socSpread: _spread(live),
          faults: live.expand((b) => b.faults).toSet().toList(),
        );
      case BankType.series:
        final voltage = live.fold(0.0, (s, b) => s + b.totalVoltage);
        final current = live.fold(0.0, (s, b) => s + b.current) / live.length;
        final soc = live.map((b) => b.soc).reduce(math.min); // мин SOC
        return BankAggregate(
          voltage: voltage,
          current: current,
          power: voltage * current,
          soc: soc,
          remaining: live.map((b) => b.remainingCapacity).reduce(math.min),
          full: live.map((b) => b.fullCapacity).reduce(math.min),
          tempAvg: live.fold(0.0, (s, b) => s + b.tempAvg) / live.length,
          status: _commonStatus(live),
          socSpread: _spread(live),
          faults: live.expand((b) => b.faults).toSet().toList(),
        );
    }
  }

  static double _spread(List<BatteryData> live) {
    if (live.length < 2) return 0;
    final socs = live.map((b) => b.soc);
    return socs.reduce(math.max) - socs.reduce(math.min);
  }

  static ChargeStatus _commonStatus(List<BatteryData> live) {
    if (live.any((b) => b.status == ChargeStatus.discharging)) {
      return ChargeStatus.discharging;
    }
    if (live.any((b) => b.status == ChargeStatus.charging)) {
      return ChargeStatus.charging;
    }
    return ChargeStatus.standby;
  }

  /// Код конфигурации для подписи (схема Михаила 26.07): одиночный «1»,
  /// последовательный из N — «NS», параллельный из N — «NP».
  String get configCode => switch (type) {
        BankType.single => '1',
        BankType.series => '${batteries.length}S',
        BankType.parallel => '${batteries.length}P',
      };

  /// Цвет кольца по порогам банка.
  Color ringColor(double soc) {
    if (soc <= socCritical) return AppColors.socRed;
    if (soc <= socWarning) return AppColors.socYellow;
    return AppColors.socGreen;
  }
}

class BankAggregate {
  final double voltage; // V
  final double current; // A (+заряд/-разряд)
  final double power; // W
  final double soc; // %
  final double remaining; // Ah
  final double full; // Ah
  final double tempAvg; // °C
  final ChargeStatus status;
  final double socSpread; // разброс SOC между АКБ
  final List<String> faults;

  const BankAggregate({
    required this.voltage,
    required this.current,
    required this.power,
    required this.soc,
    required this.remaining,
    required this.full,
    required this.tempAvg,
    required this.status,
    required this.socSpread,
    required this.faults,
  });

  const BankAggregate.empty()
      : voltage = 0,
        current = 0,
        power = 0,
        soc = 0,
        remaining = 0,
        full = 0,
        tempAvg = 0,
        status = ChargeStatus.standby,
        socSpread = 0,
        faults = const [];
}
