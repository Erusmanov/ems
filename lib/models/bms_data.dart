import 'dart:math' as math;

/// Статус заряда/разряда (регистр Daly 0x2F: 0 покой, 1 заряд, 2 разряд).
enum ChargeStatus { standby, charging, discharging }

/// Снимок параметров одной АКБ, прочитанный из BMS (или сгенерированный моком).
/// Все величины — в человеко-читаемых единицах (V, A, W, Ah, °C, %).
class BatteryData {
  final String deviceId; // BLE identifier / MAC
  final String bleName;

  final double totalVoltage; // V
  final double current; // A  (+ заряд, - разряд)
  final double soc; // %
  final double remainingCapacity; // Ah
  final double fullCapacity; // Ah (для UI; с санити-фильтром мусора 0x80)
  /// Номинальная ёмкость из регистра 0x80 КАК ЕСТЬ (заводская установка).
  /// Для сравнения батарей в банке: у одинаковых АКБ значения равны, даже
  /// если прошивка отдаёт их в нестандартном масштабе.
  final double? ratedCapacityAh;
  final double tempAvg; // °C
  final double tempMax;
  final double tempMin;
  final int cycles;
  /// SOH, % — состояние здоровья. null: регистр уточняется на живом железе.
  final double? soh;
  final ChargeStatus status;
  final bool mosCharge;
  final bool mosDischarge;
  final List<double> cells; // напряжения ячеек, V
  final int tempSensorCount;
  final List<String> faults; // активные аварии (декодированы)
  final String? swVersion;
  final String? serialNumber;
  final DateTime? manufactureDate;
  final DateTime lastUpdate;
  final bool connected;

  BatteryData({
    required this.deviceId,
    required this.bleName,
    required this.totalVoltage,
    required this.current,
    required this.soc,
    required this.remainingCapacity,
    required this.fullCapacity,
    this.ratedCapacityAh,
    required this.tempAvg,
    required this.tempMax,
    required this.tempMin,
    required this.cycles,
    this.soh,
    required this.status,
    required this.mosCharge,
    required this.mosDischarge,
    required this.cells,
    required this.tempSensorCount,
    required this.faults,
    required this.lastUpdate,
    this.swVersion,
    this.serialNumber,
    this.manufactureDate,
    this.connected = true,
  });

  /// Пустой снимок до первого чтения (устройство ещё не отвечает).
  factory BatteryData.placeholder({
    required String deviceId,
    required String bleName,
  }) =>
      BatteryData(
        deviceId: deviceId,
        bleName: bleName,
        totalVoltage: 0,
        current: 0,
        soc: 0,
        remainingCapacity: 0,
        fullCapacity: 0,
        ratedCapacityAh: null,
        tempAvg: 0,
        tempMax: 0,
        tempMin: 0,
        cycles: 0,
        soh: null,
        status: ChargeStatus.standby,
        mosCharge: false,
        mosDischarge: false,
        cells: const [],
        tempSensorCount: 0,
        faults: const [],
        lastUpdate: DateTime.now(),
        connected: false,
      );

  int get cellCount => cells.length;

  double get power => totalVoltage * current; // W (знак как у тока)

  double get maxCellV => cells.isEmpty ? 0 : cells.reduce(math.max);
  double get minCellV => cells.isEmpty ? 0 : cells.reduce(math.min);

  int get maxCellIndex =>
      cells.isEmpty ? -1 : cells.indexOf(maxCellV);
  int get minCellIndex =>
      cells.isEmpty ? -1 : cells.indexOf(minCellV);

  /// Разброс напряжений ячеек (delta / «дисперсия» в макете), V.
  double get cellDelta => cells.isEmpty ? 0 : maxCellV - minCellV;

  double get avgCellV =>
      cells.isEmpty ? 0 : cells.reduce((a, b) => a + b) / cells.length;

  bool get hasAlarms => faults.isNotEmpty;

  /// Копия с заменой имени (защита от затирания пустым, 03.08).
  BatteryData copyWithName(String name) => BatteryData(
        deviceId: deviceId,
        bleName: name,
        totalVoltage: totalVoltage,
        current: current,
        soc: soc,
        remainingCapacity: remainingCapacity,
        fullCapacity: fullCapacity,
        ratedCapacityAh: ratedCapacityAh,
        tempAvg: tempAvg,
        tempMax: tempMax,
        tempMin: tempMin,
        cycles: cycles,
        soh: soh,
        status: status,
        mosCharge: mosCharge,
        mosDischarge: mosDischarge,
        cells: cells,
        tempSensorCount: tempSensorCount,
        faults: faults,
        swVersion: swVersion,
        serialNumber: serialNumber,
        manufactureDate: manufactureDate,
        lastUpdate: lastUpdate,
        connected: connected,
      );

  BatteryData copyWith({bool? connected, DateTime? lastUpdate}) => BatteryData(
        deviceId: deviceId,
        bleName: bleName,
        totalVoltage: totalVoltage,
        current: current,
        soc: soc,
        remainingCapacity: remainingCapacity,
        fullCapacity: fullCapacity,
        ratedCapacityAh: ratedCapacityAh,
        tempAvg: tempAvg,
        tempMax: tempMax,
        tempMin: tempMin,
        cycles: cycles,
        soh: soh,
        status: status,
        mosCharge: mosCharge,
        mosDischarge: mosDischarge,
        cells: cells,
        tempSensorCount: tempSensorCount,
        faults: faults,
        swVersion: swVersion,
        serialNumber: serialNumber,
        manufactureDate: manufactureDate,
        lastUpdate: lastUpdate ?? this.lastUpdate,
        connected: connected ?? this.connected,
      );
}
