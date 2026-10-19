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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(19) / 19;
                final accessibleLayout = scale > 1.3;
                final ring = SocRing(
                  soc: agg.soc,
                  color: ringColor,
                  statusText: _statusLabel(agg.status),
                  statusColor: _statusColor(agg.status),
                  size: accessibleLayout
                      ? (138 * scale.clamp(1.0, 2.0)).clamp(
                          0.0,
                          constraints.maxWidth,
                        )
                      : (constraints.maxWidth * 0.40).clamp(0.0, 138.0),
                );
                final metrics = [
                  _metric('НАПРЯЖЕНИЕ', '${agg.voltage.toStringAsFixed(2)} V'),
                  _metric('ТОК', '${agg.current.toStringAsFixed(1)} A'),
                  _metric('МОЩНОСТЬ', _fmtPower(agg.power), end: true),
                  _metric(time.label.toUpperCase(), time.text, end: true),
                ];
                if (accessibleLayout &&
                    constraints.maxWidth < ring.size + 300 * scale) {
                  final columns = constraints.maxWidth >= 300 * scale ? 2 : 1;
                  return Column(
                    children: [
                      ring,
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 16,
                        children: [
                          for (final metric in metrics)
                            SizedBox(
                              width:
                                  (constraints.maxWidth - 12 * (columns - 1)) /
                                  columns,
                              child: metric,
                            ),
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          metrics[0],
                          const SizedBox(height: 24),
                          metrics[1],
                        ],
                      ),
                    ),
                    ring,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          metrics[2],
                          const SizedBox(height: 24),
                          metrics[3],
                        ],
                      ),
                    ),
                  ],
                );
              },
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BankConfigScreen(bankId: bank.id)),
      ),
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
                  Text(
                    bank.name,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Шестерёнка вместо Bluetooth: тап ведёт в настройки банка (26.07)
            Icon(
              Icons.settings,
              color: bank.connected
                  ? AppColors.textSecondary
                  : AppColors.textLabel,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, {bool end = false}) {
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            textAlign: end ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              color: AppColors.textLabel,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value.replaceAll(' ', '\u00a0'),
            textAlign: end ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _extraPanel(BatteryData b, BankAggregate agg) {
    // Только параметры уровня БАНКА (3 в одну строку, решение Михаила 30.06).
    // Параметры одной АКБ (ячейки, ср.напр., дисперсия, циклы, дата, SN) —
    // на экране батареи/ячеек, не на карточке банка.
    final tiles = <_Param>[
      _Param(
        Icons.battery_5_bar,
        'ЁМКОСТЬ ОСТАТОК',
        '${agg.remaining.toStringAsFixed(1)} Ah',
      ),
      _Param(
        Icons.battery_full,
        'ЁМКОСТЬ ПОЛНАЯ',
        '${agg.full.toStringAsFixed(1)} Ah',
      ),
      _Param(
        Icons.thermostat,
        'ТЕМПЕРАТУРА',
        '${agg.tempAvg.toStringAsFixed(1)} °C',
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
              final columns = (constraints.maxWidth / (125 * scale))
                  .floor()
                  .clamp(1, 3);
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final tile in tiles)
                    SizedBox(
                      width:
                          (constraints.maxWidth - 8 * (columns - 1)) / columns,
                      child: _paramTile(tile),
                    ),
                ],
              );
            },
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
    // Высота зависит от текста, включая системный масштаб шрифта.
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
                Text(
                  t.label,
                  style: TextStyle(
                    color: AppColors.textLabel,
                    fontSize: 9,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    t.value.replaceAll(' ', '\u00a0'),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
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
