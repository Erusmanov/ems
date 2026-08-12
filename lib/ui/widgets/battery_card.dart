import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/bank.dart';
import '../../models/bank_icons.dart';
import '../../models/bms_data.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../bank_config_screen.dart';
import 'soc_ring.dart';

/// Карточка банка на главном экране (как на референс-макете).
class BatteryCard extends StatefulWidget {
  final Bank bank;
  const BatteryCard({super.key, required this.bank});

  @override
  State<BatteryCard> createState() => _BatteryCardState();
}

class _BatteryCardState extends State<BatteryCard> {
  bool _expanded = false;

  String _fmtPower(double w) {
    if (w.abs() >= 1000) return '${(w / 1000).toStringAsFixed(2)} kW';
    return '${w.round()} W';
  }

  String _statusLabel(ChargeStatus s) => switch (s) {
        ChargeStatus.charging => 'Заряд',
        ChargeStatus.discharging => 'Разряд',
        ChargeStatus.standby => 'Ожидание',
      };

  Color _statusColor(ChargeStatus s) => switch (s) {
        ChargeStatus.charging => AppColors.statusCharge,
        ChargeStatus.discharging => AppColors.statusDischarge,
        ChargeStatus.standby => AppColors.statusStandby,
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bank = widget.bank;
    if (bank.batteries.isEmpty) {
      // Банков без АКБ быть не должно (22.07 п.3), но если такой остался
      // со старой версии — не роняем главный экран серым error-виджетом.
      return const SizedBox.shrink();
    }
    final agg = bank.aggregate;
    final battery = bank.batteries.first;
    final time = app.timeFor(bank);
    final ringColor = bank.ringColor(agg.soc);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          _header(bank, battery),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _metric('НАПРЯЖЕНИЕ', '${agg.voltage.toStringAsFixed(2)} V'),
                      const SizedBox(height: 24),
                      _metric('ТОК', '${agg.current.toStringAsFixed(1)} A'),
                    ],
                  ),
                ),
                SocRing(
                  soc: agg.soc,
                  color: ringColor,
                  statusText: _statusLabel(agg.status),
                  statusColor: _statusColor(agg.status),
                  size: 138,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _metric('МОЩНОСТЬ', _fmtPower(agg.power), end: true),
                      const SizedBox(height: 24),
                      _metric(time.label.toUpperCase(), time.text, end: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) _extraPanel(battery, agg),
          _expandHandle(),
        ],
      ),
    );
  }

  Widget _header(Bank bank, BatteryData b) {
    // Формат подписи — схема Михаила 26.07: код конфигурации банка (1/nS/nP),
    // тип словами, суммарная ёмкость банка.
    final subtitle =
        'LFP-${bank.configCode} • ${bank.type.label} • ${bank.aggregate.full.round()} Ач';
    return InkWell(
      // Тап по заголовку — конфигурация банка (решение Михаила 15.07);
      // к ячейкам батареи — из списка батарей на экране конфигурации.
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BankConfigScreen(bankId: bank.id),
      )),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          BankIcon(bank.iconId, color: AppColors.accent, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bank.name,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          // Шестерёнка вместо Bluetooth: тап ведёт в настройки банка (26.07)
          Icon(Icons.settings,
              color: bank.connected
                  ? AppColors.textSecondary
                  : AppColors.textLabel,
              size: 18),
        ],
      ),
      ),
    );
  }

  Widget _metric(String label, String value, {bool end = false}) {
    return Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            textAlign: end ? TextAlign.right : TextAlign.left,
            style: TextStyle(
                color: AppColors.textLabel,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Text(value,
            textAlign: end ? TextAlign.right : TextAlign.left,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }

  Widget _extraPanel(BatteryData b, BankAggregate agg) {
    // Только параметры уровня БАНКА (3 в одну строку, решение Михаила 30.06).
    // Параметры одной АКБ (ячейки, ср.напр., дисперсия, циклы, дата, SN) —
    // на экране батареи/ячеек, не на карточке банка.
    final tiles = <_Param>[
      _Param(Icons.battery_5_bar, 'ЁМКОСТЬ ОСТАТОК',
          '${agg.remaining.toStringAsFixed(1)} Ah'),
      _Param(Icons.battery_full, 'ЁМКОСТЬ ПОЛНАЯ',
          '${agg.full.toStringAsFixed(1)} Ah'),
      _Param(Icons.thermostat, 'ТЕМПЕРАТУРА', '${agg.tempAvg.toStringAsFixed(1)} °C'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.85,
            children: tiles.map((t) => _paramTile(t)).toList(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
              child: Text(
                'Последнее обновление: ${DateFormat('HH:mm:ss').format(b.lastUpdate)}',
                style: TextStyle(color: AppColors.textLabel, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paramTile(_Param t) {
    // Зона подписи фиксированной высоты (2 строки), значения — крупнее и
    // строго в один горизонтальный ряд (комментарий Михаила 15.07, п.4).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(t.icon, size: 16, color: AppColors.socGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  child: Text(t.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textLabel,
                          fontSize: 9,
                          height: 1.1)),
                ),
                Text(t.value,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandHandle() {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 2),
        child: Icon(
          _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _Param {
  final IconData icon;
  final String label;
  final String value;
  _Param(this.icon, this.label, this.value);
}
