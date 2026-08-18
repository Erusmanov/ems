import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../protocol/daly_parser.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Отладочный тех-экран (из этапа M0): сырые регистры Daly 0x00..0x3D как есть.
/// Нужен для сверки с оригинальным приложением Daly, когда показания вызывают
/// сомнения (например, SOC): видно сырое значение и варианты масштабирования.
class DebugRegistersScreen extends StatefulWidget {
  final String deviceId;
  const DebugRegistersScreen({super.key, required this.deviceId});

  @override
  State<DebugRegistersScreen> createState() => _DebugRegistersScreenState();
}

class _DebugRegistersScreenState extends State<DebugRegistersScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Сырые регистры не проходят через notifyListeners — обновляем сами раз в 1 с.
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Подписи известных регистров карты Daly/KVMS.
  static String _label(int addr) {
    if (addr >= DalyReg.cellsStart && addr < DalyReg.tempStart) {
      return 'Ячейка ${addr + 1}, мВ';
    }
    if (addr >= DalyReg.tempStart && addr < DalyReg.totalVoltage) {
      return 'T${addr - DalyReg.tempStart + 1}, °C+40';
    }
    return switch (addr) {
      DalyReg.totalVoltage => 'Напряжение, ×0.1 В',
      DalyReg.current => 'Ток, ×0.1 А −30000',
      DalyReg.soc => 'SOC, ×0.1 %',
      DalyReg.maxCellV => 'Макс. ячейка, мВ',
      DalyReg.minCellV => 'Мин. ячейка, мВ',
      DalyReg.maxCellTemp => 'T макс, °C+40',
      DalyReg.minCellTemp => 'T мин, °C+40',
      DalyReg.status => 'Статус (0/1/2)',
      DalyReg.remainingCap => 'Остаток, ×0.1 Ач',
      DalyReg.cellCount => 'Число ячеек',
      DalyReg.tempSensorCount => 'Число датчиков T',
      DalyReg.cycles => 'Циклы',
      DalyReg.chargeMos => 'MOS заряд',
      DalyReg.dischargeMos => 'MOS разряд',
      DalyReg.cellDelta => 'Дельта ячеек, мВ',
      DalyReg.power => 'Мощность, Вт',
      DalyReg.fault1 => 'Fault 1 (биты)',
      DalyReg.fault2 => 'Fault 2 (биты)',
      DalyReg.fault3 => 'Fault 3 (биты)',
      DalyReg.fault4 => 'Fault 4 (биты)',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final regs = app.rawRegistersFor(widget.deviceId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Сырые регистры',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
      ),
      body: regs == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Сырых данных нет.\nДемо-устройства (мок) не отдают регистры — '
                  'подключите реальную BMS.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
            )
          : ListView(
              children: [
                _socHint(regs),
                for (var a = 0; a < regs.length; a++) _regRow(a, regs[a]),
              ],
            ),
    );
  }

  /// Разбор SOC в двух масштабах — для сверки с приложением Daly.
  Widget _socHint(List<int> regs) {
    if (regs.length <= DalyReg.soc) return const SizedBox.shrink();
    final raw = regs[DalyReg.soc];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent),
      ),
      child: Text(
        'SOC (регистр 0x2A): сырое = $raw\n'
        '→ как ×0.1 %: ${(raw * 0.1).toStringAsFixed(1)} %   '
        '→ как 1 %: $raw %\n'
        'Сравните с показанием сервисного приложения производителя BMS.',
        style: TextStyle(
            color: AppColors.textPrimary, fontSize: 13, height: 1.4),
      ),
    );
  }

  Widget _regRow(int addr, int value) {
    final label = _label(addr);
    final hexAddr = '0x${addr.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    final hexVal =
        '0x${value.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(hexAddr,
                style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          Text('$value',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 10),
          SizedBox(
            width: 58,
            child: Text(hexVal,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: AppColors.textLabel,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}
