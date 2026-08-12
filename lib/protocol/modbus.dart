import 'dart:typed_data';
import 'crc16.dart';

/// Сборка/разбор кадров Modbus RTU для Daly/KVMS BMS.
/// Данные big-endian (старший байт вперёд), адрес slave по умолчанию 0xD2.
class Modbus {
  static const int defaultSlave = 0xD2;

  // KVMS intranet-протокол (docs/KVMS_intranet_protocol.xlsx, от Daly 26.07):
  // запрос уходит на 0x81, ответ приходит с адресом 0x51. Не конфликтует с
  // BLE-Modbus (0xD2) — ходит по тому же каналу DL-B40. Регистр 0x100 —
  // board number (адрес платы для RS485/NMEA2000 каскада).
  static const int intranetRequest = 0x81;
  static const int intranetResponse = 0x51;
  static const int fnReadHolding = 0x03;
  static const int fnWriteSingle = 0x06;
  static const int fnWriteMultiple = 0x10;

  /// Read Holding Registers: ADDR 03 startHi startLo countHi countLo CRClo CRChi
  static Uint8List readHolding(int start, int count, {int slave = defaultSlave}) {
    final frame = [
      slave,
      fnReadHolding,
      (start >> 8) & 0xFF,
      start & 0xFF,
      (count >> 8) & 0xFF,
      count & 0xFF,
    ];
    return Uint8List.fromList(appendCrc(frame));
  }

  /// Write Single Register: ADDR 06 regHi regLo valHi valLo CRClo CRChi
  static Uint8List writeSingle(int reg, int value, {int slave = defaultSlave}) {
    final frame = [
      slave,
      fnWriteSingle,
      (reg >> 8) & 0xFF,
      reg & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
    return Uint8List.fromList(appendCrc(frame));
  }

  /// Write Multiple Registers (0x10).
  static Uint8List writeMultiple(int start, List<int> values,
      {int slave = defaultSlave}) {
    final n = values.length;
    final frame = <int>[
      slave,
      fnWriteMultiple,
      (start >> 8) & 0xFF,
      start & 0xFF,
      (n >> 8) & 0xFF,
      n & 0xFF,
      (n * 2) & 0xFF,
      for (final v in values) ...[(v >> 8) & 0xFF, v & 0xFF],
    ];
    return Uint8List.fromList(appendCrc(frame));
  }

  /// Разбирает ответ на чтение (fn 0x03) в массив 16-битных регистров.
  /// Бросает [ModbusException] при ошибке CRC/длины/функции.
  static List<int> parseReadResponse(List<int> resp, {int? expectedSlave}) {
    if (resp.length < 5) {
      throw const ModbusException('Слишком короткий ответ');
    }
    if (!checkCrc(resp)) {
      throw const ModbusException('Ошибка CRC');
    }
    final slave = resp[0];
    final fn = resp[1];
    if (expectedSlave != null && slave != expectedSlave) {
      throw ModbusException('Чужой адрес slave: $slave');
    }
    if (fn & 0x80 != 0) {
      throw ModbusException('BMS вернула ошибку, код ${resp[2]}');
    }
    if (fn != fnReadHolding) {
      throw ModbusException('Неожиданная функция 0x${fn.toRadixString(16)}');
    }
    final byteCount = resp[2];
    if (resp.length < 3 + byteCount + 2) {
      throw const ModbusException('Несовпадение длины пакета');
    }
    final regs = <int>[];
    for (int i = 0; i < byteCount; i += 2) {
      regs.add((resp[3 + i] << 8) | resp[3 + i + 1]);
    }
    return regs;
  }
}

class ModbusException implements Exception {
  final String message;
  const ModbusException(this.message);
  @override
  String toString() => 'ModbusException: $message';
}
