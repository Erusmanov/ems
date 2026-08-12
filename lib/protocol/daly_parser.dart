import '../models/bms_data.dart';

/// Адреса регистров Daly/KVMS (из «APP_Modbus protocol»).
class DalyReg {
  static const cellsStart = 0x00; // 0x00..0x1F — напряжения ячеек, 0.001 V
  static const tempStart = 0x20; // 0x20..0x27 — температуры, offset 40
  static const totalVoltage = 0x28; // 0.1 V
  static const current = 0x29; // 0.1 A, offset 30000 (+заряд / -разряд)
  static const soc = 0x2A; // 0.1 %
  static const maxCellV = 0x2B; // 1 mV
  static const minCellV = 0x2C; // 1 mV
  static const maxCellTemp = 0x2D; // offset 40
  static const minCellTemp = 0x2E; // offset 40
  static const status = 0x2F; // 0 покой, 1 заряд, 2 разряд
  static const remainingCap = 0x30; // 0.1 Ah
  static const cellCount = 0x31;
  static const tempSensorCount = 0x32;
  static const cycles = 0x33;
  static const chargeMos = 0x35;
  static const dischargeMos = 0x36;
  static const cellDelta = 0x38; // 1 mV
  static const power = 0x39; // W
  static const fault1 = 0x3A;
  static const fault2 = 0x3B;
  static const fault3 = 0x3C;
  static const fault4 = 0x3D;

  static const ratedCapacity = 0x80; // полная ёмкость (R/W), 0.1 Ah

  // Информация об устройстве (docs/dalyModbusProtocol.xlsx)
  static const swVersionStart = 0xA9; // 0xA9..0xB0 — версия ПО (ASCII)
  static const swVersionLen = 8;
  static const machineCodeStart = 0xB9; // 0xB9..0xC8 — заводской код/серийник
  static const machineCodeLen = 16;
  static const mfgDateStart = 0xCC; // 0xCC..0xCD — дата производства YYMMDD00 hex
  static const mfgDateLen = 2;

  // Настройки/команды (docs/dalyModbusProtocol.xlsx, подтверждено 21.07.2026)
  static const sleepWaitTime = 0x8A; // R/W, секунды; 65535 = не засыпать
  static const cmdRestart = 0xF0; // W — перезагрузка BMS

  /// Intranet-протокол (slave 0x81 → ответ 0x51): адрес платы 0..32 —
  /// «Slave board address» из приложения Daly, он же instance в NMEA2000.
  static const intranetBoardNumber = 0x100;
  // 0xF1 shutdown / 0xF3 factory reset — намеренно НЕ используем (опасно)

  /// Сколько регистров читать одним запросом для realtime-блока.
  static const realtimeCount = 0x3E;
}

/// Разбор блока realtime-регистров (чтение с 0x00) в [BatteryData].
class DalyParser {
  /// [regs] — массив регистров, проиндексированный от адреса 0x00.
  /// [fullCapacity] — полная ёмкость (читается отдельно из 0x80); если null,
  /// оценивается из остаточной ёмкости и SOC.
  static BatteryData parseRealtime(
    List<int> regs, {
    required String deviceId,
    required String bleName,
    double? fullCapacity,
    String? swVersion,
    String? serialNumber,
    DateTime? manufactureDate,
  }) {
    int u(int addr) => addr < regs.length ? regs[addr] : 0;

    final cellCount = u(DalyReg.cellCount).clamp(0, 16);
    final cells = <double>[
      for (int i = 0; i < cellCount; i++) u(DalyReg.cellsStart + i) * 0.001,
    ];

    final tempCount = u(DalyReg.tempSensorCount).clamp(0, 8);
    final temps = <double>[
      for (int i = 0; i < tempCount; i++) (u(DalyReg.tempStart + i) - 40).toDouble(),
    ];
    final tempAvg = temps.isEmpty
        ? 0.0
        : temps.reduce((a, b) => a + b) / temps.length;

    final totalVoltage = u(DalyReg.totalVoltage) * 0.1;
    final current = (u(DalyReg.current) - 30000) * 0.1;
    final soc = u(DalyReg.soc) * 0.1;
    final remaining = u(DalyReg.remainingCap) * 0.1;

    final status = switch (u(DalyReg.status)) {
      1 => ChargeStatus.charging,
      2 => ChargeStatus.discharging,
      _ => ChargeStatus.standby,
    };

    // Санити-чек регистра 0x80: часть прошивок отдаёт мусор (видели 2193 Ah
    // на 108 Ah батарее). Неправдоподобное значение -> оценка из SOC/остатка.
    var ratedFull = fullCapacity;
    if (ratedFull != null &&
        (ratedFull <= 0 || ratedFull > 1500 || ratedFull < remaining)) {
      ratedFull = null;
    }
    final full = ratedFull ??
        (soc > 1 ? remaining / (soc / 100.0) : remaining);

    return BatteryData(
      deviceId: deviceId,
      bleName: bleName,
      totalVoltage: totalVoltage,
      current: current,
      soc: soc,
      remainingCapacity: remaining,
      fullCapacity: full,
      ratedCapacityAh: fullCapacity, // сырое 0x80, без санити-фильтра
      tempAvg: tempAvg,
      tempMax: (u(DalyReg.maxCellTemp) - 40).toDouble(),
      tempMin: (u(DalyReg.minCellTemp) - 40).toDouble(),
      cycles: u(DalyReg.cycles),
      status: status,
      mosCharge: u(DalyReg.chargeMos) == 1,
      mosDischarge: u(DalyReg.dischargeMos) == 1,
      cells: cells,
      tempSensorCount: tempCount,
      faults: decodeFaults(
        u(DalyReg.fault1),
        u(DalyReg.fault2),
        u(DalyReg.fault3),
        u(DalyReg.fault4),
      ),
      swVersion: swVersion,
      serialNumber: serialNumber,
      manufactureDate: manufactureDate,
      lastUpdate: DateTime.now(),
    );
  }

  /// Декодирование аварий из регистров 0x3A..0x3D в читаемые строки.
  /// Точное соответствие байт/бит проверяется на реальном железе.
  static List<String> decodeFaults(int f1, int f2, int f3, int f4) {
    final out = <String>[];
    void bit(int reg, int b, String label) {
      if (reg & (1 << b) != 0) out.add(label);
    }
    // Fault 1 (0x3A)
    bit(f1, 0, 'Перегрузка по току заряда (ур.1)');
    bit(f1, 1, 'Перегрузка по току заряда (ур.2)');
    bit(f1, 2, 'Перегрузка по току разряда (ур.1)');
    bit(f1, 4, 'SOC ниже порога'); // проверено разрядом на стенде 26.07
    bit(f1, 6, 'Низкий SOC');
    bit(f1, 8, 'Большой разброс напряжений');
    bit(f1, 10, 'Большой разброс температур');
    // Fault 3 (0x3C) — MOS / датчики
    bit(f3, 0, 'Перегрев заряд-MOS');
    bit(f3, 1, 'Перегрев разряд-MOS');
    bit(f3, 8, 'Неисправность AFE');
    bit(f3, 11, 'Ошибка EEPROM');
    // Fault 4 (0x3D) — критические
    bit(f4, 2, 'Защита от короткого замыкания');
    bit(f4, 6, 'Тепловой разгон');
    bit(f4, 7, 'Отказ нагрева');
    return out;
  }
}
