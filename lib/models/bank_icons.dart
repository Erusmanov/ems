import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Библиотека иконок банка — фирменный SVG-набор заказчика (16.07.2026),
/// контурные, красятся через currentColor. Файлы в assets/bank_icons/.
/// В хранилище пишется строковый id (= имя файла без .svg).
class BankIconDef {
  final String id;
  final String label;
  const BankIconDef(this.id, this.label);
}

const bankIconLibrary = <BankIconDef>[
  BankIconDef('house_bank', 'Домашний банк'),
  BankIconDef('home_general', 'Дом'),
  BankIconDef('home_energy', 'Энергия дома'),
  BankIconDef('solar_storage', 'Солнечный накопитель'),
  BankIconDef('ups_backup', 'ИБП / резерв'),
  BankIconDef('camper_rv', 'Кемпер'),
  BankIconDef('engine_car', 'Автомобиль'),
  BankIconDef('starter_battery', 'Стартерная АКБ'),
  BankIconDef('marine_house', 'Лодка — жилой'),
  BankIconDef('marine_instruments', 'Лодка — приборы'),
  BankIconDef('trolling_motor', 'Троллинг-мотор'),
  BankIconDef('outboard', 'Подвесной мотор'),
  BankIconDef('outboard_starter', 'Стартер мотора'),
  BankIconDef('bow_thruster', 'Подруливающее'),
  BankIconDef('anchor', 'Якорная лебёдка'),
  BankIconDef('winch', 'Лебёдка'),
  BankIconDef('auxiliary_other', 'Прочее'),
];

const defaultBankIconId = 'house_bank';

/// Иконки, скрытые из грида выбора: визуальные близнецы других (клиентский
/// тест 07.08 «какие-то иконки дублируются»). Сохранённые банки с этими id
/// работают как прежде.
const _hiddenFromPicker = {'outboard_starter', 'home_energy', 'marine_house'};

/// Список для грида выбора — только визуально различимые.
List<BankIconDef> get bankIconChoices => bankIconLibrary
    .where((d) => !_hiddenFromPicker.contains(d.id))
    .toList();

/// Нормализация значения из хранилища: строковый id, легаси-индекс старой
/// Material-библиотеки (int) или мусор → валидный id.
String normalizeBankIconId(dynamic stored) {
  if (stored is String && bankIconLibrary.any((d) => d.id == stored)) {
    return stored;
  }
  if (stored is int) {
    // Старые индексы (cottage, handyman, sailing, boat, rv, solar, bolt,
    // battery, garage, agriculture) → ближайшие по смыслу новые id
    const legacy = [
      'home_general', // cottage
      'auxiliary_other', // handyman
      'marine_house', // sailing
      'marine_house', // directions_boat
      'camper_rv', // rv_hookup
      'solar_storage', // solar_power
      'home_energy', // electric_bolt
      'house_bank', // battery_charging_full
      'engine_car', // garage
      'auxiliary_other', // agriculture
    ];
    if (stored >= 0 && stored < legacy.length) return legacy[stored];
  }
  return defaultBankIconId;
}

/// Иконка банка: SVG из набора, красится в заданный цвет.
class BankIcon extends StatelessWidget {
  final String iconId;
  final double size;
  final Color color;

  const BankIcon(this.iconId,
      {super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/bank_icons/$iconId.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
