import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bms_data.dart';
import '../models/bank_icons.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'device_info_screen.dart';

/// Экран батареи: напряжения ячеек (этап Э2/M3). Информация об устройстве —
/// на ОТДЕЛЬНОМ экране (решение Михаила 13.07), кнопка «i» в шапке.
/// Стиль — строки во всю ширину (за основу взят экран поиска устройств,
/// решение Михаила 30.06/12.07): маленькая тематическая иконка + текст в одну строку.
class BatteryDetailScreen extends StatelessWidget {
  final String bankId;
  final String deviceId;

  const BatteryDetailScreen({
    super.key,
    required this.bankId,
    required this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bank = app.banks.where((b) => b.id == bankId).firstOrNull;
    final battery =
        bank?.batteries.where((b) => b.deviceId == deviceId).firstOrNull;

    if (bank == null || battery == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.bg),
        body: Center(
          child: Text('Устройство не найдено',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            BankIcon(bank.iconId, size: 26, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                battery.bleName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          Icon(Icons.bluetooth,
              size: 18,
              color: battery.connected
                  ? AppColors.bluetooth
                  : AppColors.textLabel),
          IconButton(
            tooltip: 'Информация об устройстве',
            icon: Icon(Icons.info_outline,
                size: 20, color: AppColors.accent),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  DeviceInfoScreen(bankId: bankId, deviceId: deviceId),
            )),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _summaryStrip(battery),
          // Тревоги — между блоком данных и графиком ячеек (Михаил 16.07)
          for (final fault in battery.faults) _alarmRow(fault),
          _sectionHeader(Icons.grid_view_rounded,
              'ЯЧЕЙКИ (${battery.cellCount})', _cellsSummary(battery)),
          for (var i = 0; i < battery.cellCount; i++) _cellRow(battery, i),
        ],
      ),
    );
  }

  /// Строка активной тревоги: иконка аларма + описание.
  Widget _alarmRow(String fault) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.socRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.socRed.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppColors.socRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(fault,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ---------- Сводка сверху: V / A / SOC ----------

  Widget _summaryStrip(BatteryData b) {
    // Выравнивание по колонкам (Михаил 21.07): крайняя левая — к левому краю,
    // крайняя правая — к правому, середина — по центру.
    Widget item(String label, String value, {int align = 0}) {
      final cross = switch (align) {
        < 0 => CrossAxisAlignment.start,
        > 0 => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.center,
      };
      final ta = switch (align) {
        < 0 => TextAlign.left,
        > 0 => TextAlign.right,
        _ => TextAlign.center,
      };
      return Expanded(
        child: Column(
          crossAxisAlignment: cross,
          children: [
            Text(label,
                textAlign: ta,
                style: TextStyle(
                    color: AppColors.textLabel,
                    fontSize: 10,
                    letterSpacing: 0.8)),
            const SizedBox(height: 3),
            Text(value,
                textAlign: ta,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          // Состав полей — список Михаила от 16.07.2026 (+SOH/циклы/ёмкости).
          // Логически связанные показатели — в одной строке.
          // SOH скрыт (решение Михаила 21.07: регистра нет в Modbus-карте
          // DL-B40; вернём, если прошивка его отдаст) — b.soh остаётся в модели.
          Row(
            children: [
              item('SOC', '${b.soc.toStringAsFixed(0)} %', align: -1),
              if (b.soh != null)
                item('SOH', '${b.soh!.toStringAsFixed(0)} %'),
              item('ЦИКЛЫ', '${b.cycles}', align: 1),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              item('НАПРЯЖЕНИЕ', '${b.totalVoltage.toStringAsFixed(2)} V',
                  align: -1),
              item('ТОК', '${b.current.toStringAsFixed(1)} A'),
              item('СТАТУС', _statusLabel(b.status), align: 1),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              item('ЁМКОСТЬ ДОСТУПНАЯ',
                  '${b.remainingCapacity.toStringAsFixed(1)} Ah',
                  align: -1),
              item('ЁМКОСТЬ ПОЛНАЯ',
                  '${b.fullCapacity.toStringAsFixed(1)} Ah',
                  align: 1),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              item('T MIN', '${b.tempMin.toStringAsFixed(0)} °C', align: -1),
              item('T MAX', '${b.tempMax.toStringAsFixed(0)} °C', align: 1),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              item('MOS ЗАРЯД', b.mosCharge ? 'вкл' : 'выкл', align: -1),
              item('MOS РАЗРЯД', b.mosDischarge ? 'вкл' : 'выкл', align: 1),
            ],
          ),
          const SizedBox(height: 12),
          // Мин и макс — по краям, дельта в середине; без символа «№»
          Row(
            children: [
              item('ЯЧЕЙКА MIN',
                  '${b.minCellV.toStringAsFixed(3)} V (${b.minCellIndex + 1})',
                  align: -1),
              item('ДЕЛЬТА',
                  '${(b.cellDelta * 1000).toStringAsFixed(0)} mV'),
              item('ЯЧЕЙКА MAX',
                  '${b.maxCellV.toStringAsFixed(3)} V (${b.maxCellIndex + 1})',
                  align: 1),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLabel(ChargeStatus s) => switch (s) {
        ChargeStatus.charging => 'Заряд',
        ChargeStatus.discharging => 'Разряд',
        ChargeStatus.standby => 'Ожидание',
      };

  // ---------- Ячейки ----------

  String _cellsSummary(BatteryData b) {
    if (b.cells.isEmpty) return '';
    return 'Δ ${(b.cellDelta * 1000).toStringAsFixed(0)} mV';
  }

  Widget _sectionHeader(IconData icon, String title, String? trailing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: AppColors.textLabel,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0)),
          ),
          if (trailing != null && trailing.isNotEmpty)
            Text(trailing,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  /// Строка ячейки: номер + полоска напряжения + значение.
  /// Максимальная ячейка — зелёная метка, минимальная — красная.
  Widget _cellRow(BatteryData b, int i) {
    final v = b.cells[i];
    final isMax = i == b.maxCellIndex && b.cellDelta > 0.0005;
    final isMin = i == b.minCellIndex && b.cellDelta > 0.0005;

    // Нормировка полоски: окно вокруг фактического диапазона ячеек,
    // чтобы разбаланс был виден даже при малой дельте.
    final lo = b.minCellV - 0.02;
    final hi = b.maxCellV + 0.02;
    final frac = hi > lo ? ((v - lo) / (hi - lo)).clamp(0.0, 1.0) : 0.5;

    final markColor = isMax
        ? AppColors.socGreen
        : isMin
            ? AppColors.socRed
            : AppColors.textLabel;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text('${i + 1}',
                style: TextStyle(
                    color: markColor,
                    fontSize: 13,
                    fontWeight:
                        (isMax || isMin) ? FontWeight.w700 : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: AppColors.ringTrack,
                valueColor: AlwaysStoppedAnimation(
                  isMax
                      ? AppColors.socGreen
                      : isMin
                          ? AppColors.socRed
                          : AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text('${v.toStringAsFixed(3)} V',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: (isMax || isMin)
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight:
                        (isMax || isMin) ? FontWeight.w700 : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }

}
