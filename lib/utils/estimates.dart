import 'dart:collection';
import '../models/bms_data.dart';

/// Скользящее среднее тока (rolling average) за окно времени.
/// По ТЗ/комменту Михаила: среднее арифметическое показаний за последние
/// 5–10 минут с интервалом 1 с. Живёт только в памяти (не история измерений).
class RollingAverage {
  final int maxSamples;
  final Queue<double> _samples = Queue<double>();

  RollingAverage({this.maxSamples = 300}); // 5 минут при 1 с

  void add(double value) {
    _samples.addLast(value);
    while (_samples.length > maxSamples) {
      _samples.removeFirst();
    }
  }

  double get value =>
      _samples.isEmpty ? 0 : _samples.reduce((a, b) => a + b) / _samples.length;

  bool get isEmpty => _samples.isEmpty;
}

/// Расчёт оставшегося времени (поле «Время» на Dashboard).
/// Заряд:  Тз = (Сп − Со) / Iз   → «Время до 100%»
/// Разряд: Тр = Со / Iр          → «Время до 0%»
/// Ожидание: null → показываем прочерки.
class TimeEstimate {
  final Duration? duration;
  final String label; // «Время до 100%» / «Время до 0%» / «Время»

  const TimeEstimate(this.duration, this.label);

  static TimeEstimate compute({
    required ChargeStatus status,
    required double avgCurrent, // А (>0 заряд, <0 разряд)
    required double remaining, // Ah
    required double full, // Ah
  }) {
    switch (status) {
      case ChargeStatus.charging:
        final i = avgCurrent.abs();
        if (i < 0.05) return const TimeEstimate(null, 'Время до 100%');
        final hours = (full - remaining) / i;
        return TimeEstimate(_h(hours), 'Время до 100%');
      case ChargeStatus.discharging:
        final i = avgCurrent.abs();
        if (i < 0.05) return const TimeEstimate(null, 'Время до 0%');
        final hours = remaining / i;
        return TimeEstimate(_h(hours), 'Время до 0%');
      case ChargeStatus.standby:
        return const TimeEstimate(null, 'Время');
    }
  }

  static Duration? _h(double hours) {
    if (hours.isNaN || hours.isInfinite || hours < 0 || hours > 1000) return null;
    return Duration(minutes: (hours * 60).round());
  }

  /// Форматирование как на макете: «9ч 30м», иначе прочерк.
  String get text {
    if (duration == null) return '— : —';
    final h = duration!.inHours;
    final m = duration!.inMinutes % 60;
    if (h <= 0) return '$mм';
    return '$hч $mм';
  }
}
