import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:empower_bms/models/bank.dart';
import 'package:empower_bms/models/bms_data.dart';
import 'package:empower_bms/state/app_state.dart';
import 'package:empower_bms/ui/widgets/battery_card.dart';

void main() {
  for (final width in [320.0, 375.0, 443.0, 768.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('Battery card width=$width textScale=$scale', (tester) async {
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState();
        addTearDown(state.dispose);
        final bank = Bank(
          id: 'test',
          name: 'Battery 1',
          iconId: 'house_bank',
          type: BankType.single,
          batteries: [
            BatteryData(
              deviceId: 'test',
              bleName: 'BMS',
              totalVoltage: 13.3,
              current: 0,
              soc: 90,
              remainingCapacity: 148.8,
              fullCapacity: 165,
              tempAvg: 19,
              tempMax: 19,
              tempMin: 19,
              cycles: 1,
              status: ChargeStatus.standby,
              mosCharge: true,
              mosDischarge: true,
              cells: const [3.325, 3.325, 3.325, 3.325],
              tempSensorCount: 1,
              faults: const [],
              lastUpdate: DateTime(2026, 9, 18, 10, 35, 3),
            ),
          ],
        );
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: state,
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(child: BatteryCard(bank: bank)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final updated = tester.getRect(
          find.text('Последнее обновление: 10:35:03'),
        );
        for (final value in [
          '13.30\u00a0V',
          '148.8\u00a0Ah',
          '165.0\u00a0Ah',
          '19.0\u00a0°C',
        ]) {
          final finder = find.text(value);
          expect(finder, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: value.length),
          );
          expect(
            boxes.map((b) => b.top).toSet().length,
            1,
            reason: '$value must stay on one line',
          );
          expect(tester.getRect(finder).bottom, lessThan(updated.top));
        }
      });
    }
  }
}
