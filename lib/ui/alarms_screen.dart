import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Вкладка «Алармы»: активные аварии и предупреждения по всем банкам (этап Э2/M3).
/// Уровни: критические (fault, красный) и предупреждения (warning, жёлтый) —
/// по ТЗ раздел про декодирование fault-регистров 0x3A–0x3D.
class AlarmsScreen extends StatelessWidget {
  const AlarmsScreen({super.key});

  /// Критические аварии — отказы защиты/железа; остальное — предупреждения.
  static const _critical = <String>{
    'Защита от короткого замыкания',
    'Тепловой разгон',
    'Отказ нагрева',
    'Перегрев заряд-MOS',
    'Перегрев разряд-MOS',
    'Неисправность AFE',
    'Ошибка EEPROM',
    'Перегрузка по току заряда (ур.2)',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // Собираем активные аварии: (банк, батарея, текст)
    final items = <(_AlarmLevel, String, String)>[];
    for (final bank in app.banks) {
      for (final b in bank.batteries) {
        for (final f in b.faults) {
          final level = _critical.contains(f)
              ? _AlarmLevel.fault
              : _AlarmLevel.warning;
          items.add((level, f, '${bank.name} • ${b.bleName}'));
        }
      }
      // Предупреждение о разбросе SOC внутри банка (ТЗ §12)
      final agg = bank.aggregate;
      if (bank.batteries.length > 1 && agg.socSpread > 10) {
        items.add((
          _AlarmLevel.warning,
          'Разброс SOC между АКБ ${agg.socSpread.toStringAsFixed(0)} %',
          bank.name,
        ));
      }
      // Пороговые события SOC (видео Михаила 31.07: кольцо красное, а во
      // вкладке пусто) — та же логика, что и цвет кольца на главном экране
      if (bank.connected) {
        if (agg.soc <= bank.socCritical) {
          items.add((
            _AlarmLevel.fault,
            'SOC ниже критического порога '
                '(${agg.soc.toStringAsFixed(0)} % ≤ ${bank.socCritical.round()} %)',
            bank.name,
          ));
        } else if (agg.soc <= bank.socWarning) {
          items.add((
            _AlarmLevel.warning,
            'SOC ниже порога уведомления '
                '(${agg.soc.toStringAsFixed(0)} % ≤ ${bank.socWarning.round()} %)',
            bank.name,
          ));
        }
      }
    }
    // Критические — сверху
    items.sort((a, b) => a.$1.index.compareTo(b.$1.index));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Уведомления',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: items.isEmpty ? _emptyState() : _list(items),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 44, color: AppColors.socGreen),
          SizedBox(height: 12),
          Text('Уведомлений нет',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('Все подключённые батареи в норме',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _list(List<(_AlarmLevel, String, String)> items) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final (level, text, source) = items[i];
        final color = level == _AlarmLevel.fault
            ? AppColors.socRed
            : AppColors.socYellow;
        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                level == _AlarmLevel.fault
                    ? Icons.error_outline
                    : Icons.warning_amber_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textLabel, fontSize: 11)),
                  ],
                ),
              ),
              Text(
                level == _AlarmLevel.fault ? 'АВАРИЯ' : 'ВНИМАНИЕ',
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _AlarmLevel { fault, warning }
