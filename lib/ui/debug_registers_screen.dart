import '../l10n/app_strings.dart';
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
      return tr('message_069', [addr + 1]);
    }
    if (addr >= DalyReg.tempStart && addr < DalyReg.totalVoltage) {
      return 'T${addr - DalyReg.tempStart + 1}, °C+40';
    }
    return switch (addr) {
      DalyReg.totalVoltage => tr('message_070'),
      DalyReg.current => tr('message_071'),
      DalyReg.soc => 'SOC, ×0.1 %',
      DalyReg.maxCellV => tr('message_072'),
      DalyReg.minCellV => tr('message_073'),
      DalyReg.maxCellTemp => tr('message_074'),
      DalyReg.minCellTemp => tr('message_075'),
      DalyReg.status => tr('message_076'),
      DalyReg.remainingCap => tr('message_077'),
      DalyReg.cellCount => tr('message_078'),
      DalyReg.tempSensorCount => tr('message_079'),
      DalyReg.cycles => tr('message_080'),
      DalyReg.chargeMos => tr('message_081'),
      DalyReg.dischargeMos => tr('message_082'),
      DalyReg.cellDelta => tr('message_083'),
      DalyReg.power => tr('message_084'),
      DalyReg.fault1 => tr('message_085'),
      DalyReg.fault2 => tr('message_086'),
      DalyReg.fault3 => tr('message_087'),
      DalyReg.fault4 => tr('message_088'),
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context); // Rebuild open routes when the locale changes.
    final app = context.watch<AppState>();
    final regs = app.rawRegistersFor(widget.deviceId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text(tr('message_089'),
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
                  tr('message_090'),
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
        tr('message_091', [raw, (raw * 0.1).toStringAsFixed(1), raw]),
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
