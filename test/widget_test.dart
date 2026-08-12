import 'package:flutter_test/flutter_test.dart';
import 'package:empower_bms/protocol/crc16.dart';
import 'package:empower_bms/protocol/modbus.dart';
import 'package:empower_bms/protocol/daly_parser.dart';
import 'package:empower_bms/models/bms_data.dart';

void main() {
  group('CRC16 Modbus', () {
    test('пример из протокола: D2 03 00 0C 00 01 -> 57 AA', () {
      final frame = Modbus.readHolding(0x0C, 1);
      expect(frame.sublist(frame.length - 2), [0x57, 0xAA]);
    });

    test('write single: D2 06 00 0C 00 01 -> 9B AA', () {
      final frame = Modbus.writeSingle(0x0C, 1);
      expect(frame.sublist(frame.length - 2), [0x9B, 0xAA]);
    });

    test('checkCrc принимает корректный кадр', () {
      final frame = Modbus.readHolding(0x00, 0x3E);
      expect(checkCrc(frame), isTrue);
    });
  });

  group('Modbus parse', () {
    test('разбирает ответ чтения в регистры', () {
      // D2 03 02 00 01 + CRC  (один регистр = 1)
      final resp = appendCrc([0xD2, 0x03, 0x02, 0x00, 0x01]);
      final regs = Modbus.parseReadResponse(resp, expectedSlave: 0xD2);
      expect(regs, [1]);
    });

    test('бросает при битом CRC', () {
      expect(
        () => Modbus.parseReadResponse([0xD2, 0x03, 0x02, 0x00, 0x01, 0x00, 0x00]),
        throwsA(isA<ModbusException>()),
      );
    });
  });

  group('Daly parser', () {
    test('масштабирование напряжения, тока, SOC', () {
      final regs = List<int>.filled(0x3E, 0);
      regs[0x28] = 3500; // total voltage -> 350.0? нет: 0.1V => 350.0
      regs[0x29] = 30080; // current -> (30080-30000)*0.1 = 8.0 A (заряд)
      regs[0x2A] = 800; // SOC -> 80.0 %
      regs[0x30] = 1520; // remaining -> 152.0 Ah
      regs[0x31] = 4; // 4 ячейки
      regs[0x32] = 2; // 2 датчика темп.
      regs[0x2F] = 1; // заряд
      for (var i = 0; i < 4; i++) {
        regs[i] = 3300; // 3.300 V
      }
      for (var i = 0; i < 2; i++) {
        regs[0x20 + i] = 65; // 25 °C (offset 40)
      }

      final d = DalyParser.parseRealtime(regs,
          deviceId: 'x', bleName: 'x', fullCapacity: 190);
      expect(d.totalVoltage, 350.0);
      expect(d.current, closeTo(8.0, 0.001));
      expect(d.soc, 80.0);
      expect(d.remainingCapacity, 152.0);
      expect(d.cellCount, 4);
      expect(d.status, ChargeStatus.charging);
      expect(d.tempAvg, 25.0);
      expect(d.cells.first, closeTo(3.3, 0.0001));
    });

    test('декодирование аварии: КЗ в Fault4 bit2', () {
      final faults = DalyParser.decodeFaults(0, 0, 0, 1 << 2);
      expect(faults, contains('Защита от короткого замыкания'));
    });
  });
}
