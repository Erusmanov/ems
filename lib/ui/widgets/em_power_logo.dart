import 'package:flutter/material.dart';

/// Логотип «EM⚡Power» — PNG из референса Михаила (кадр с welcome-макета,
/// фон убран). Две версии под темы: белый/серый текст для тёмной, тёмный —
/// для светлой; молния фирменная жёлтая в обеих.
/// При получении официального вектора файлы в assets/ просто заменяются.
class EmPowerLogo extends StatelessWidget {
  final double height;
  const EmPowerLogo({super.key, this.height = 30});

  @override
  Widget build(BuildContext context) {
    // Через Theme.of — зависимость от InheritedWidget: виджет перерисуется
    // при смене темы даже будучи const (иначе логотип «залипает» на старой теме).
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? 'assets/logo_dark.png' : 'assets/logo_light.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
