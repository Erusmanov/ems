import '../models/bms_data.dart';

/// Абстракция источника данных одного устройства (АКБ).
/// Реализации: [MockBmsDataSource] (без железа) и BleBmsDataSource (реальный BMS).
/// UI и логика работают только через этот интерфейс — драйверы заменяемы.
abstract class BmsDataSource {
  String get deviceId;
  String get bleName;

  /// Поток снимков параметров АКБ.
  Stream<BatteryData> get readings;

  /// Текущее состояние подключения.
  bool get isConnected;

  /// Запустить подключение и опрос.
  Future<void> start();

  /// Остановить опрос и освободить ресурсы.
  Future<void> stop();

  /// Последний сырой блок регистров 0x00..0x3D (для отладочного экрана).
  /// null — если источник не отдаёт сырые данные (мок) или чтения ещё не было.
  List<int>? get lastRawRegisters => null;
}
