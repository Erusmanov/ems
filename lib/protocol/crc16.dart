/// CRC-16 Modbus (полином 0xA001, начальное значение 0xFFFF).
int modbusCrc16(List<int> data) {
  int crc = 0xFFFF;
  for (final b in data) {
    crc ^= b & 0xFF;
    for (int i = 0; i < 8; i++) {
      if (crc & 1 != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}

/// Дописывает CRC к кадру: младший байт вперёд, затем старший
/// (проверено по примеру протокола: D2 03 00 0C 00 01 -> ... 57 AA).
List<int> appendCrc(List<int> frame) {
  final crc = modbusCrc16(frame);
  return [...frame, crc & 0xFF, (crc >> 8) & 0xFF];
}

/// Проверяет CRC в конце кадра (последние 2 байта — low, high).
bool checkCrc(List<int> frameWithCrc) {
  if (frameWithCrc.length < 3) return false;
  final body = frameWithCrc.sublist(0, frameWithCrc.length - 2);
  final crc = modbusCrc16(body);
  final lo = frameWithCrc[frameWithCrc.length - 2];
  final hi = frameWithCrc[frameWithCrc.length - 1];
  return (crc & 0xFF) == lo && ((crc >> 8) & 0xFF) == hi;
}
