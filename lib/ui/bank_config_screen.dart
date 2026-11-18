import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bank.dart';
import '../models/bank_icons.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'banks_screen.dart' show BankEditDialog;
import 'battery_detail_screen.dart';
import 'device_scan_screen.dart';

/// Экран конфигурации банка (решение Михаила 15.07): сюда ведёт тап по банку
/// с главного экрана и из вкладки «Банки». Здесь: список батарей банка
/// (добавить/убрать), переименование и смена иконки, удаление банка.
/// Ячейки конкретной батареи — тапом по батарее из этого списка.
class BankConfigScreen extends StatelessWidget {
  final String bankId;
  const BankConfigScreen({super.key, required this.bankId});

  Future<void> _edit(BuildContext context, Bank bank) async {
    final result = await showDialog<(String, String, BankType)>(
      context: context,
      builder: (_) => BankEditDialog(bank: bank),
    );
    if (result == null || !context.mounted) return;
    final (name, iconId, type) = result;
    final app = context.read<AppState>();
    final err =
        app.renameBank(bank.id, name: name, iconId: iconId, type: type);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    // Лазейка из видео 03.08: одиночный -> параллельный с одной АКБ.
    // Смена типа сразу ведёт в поиск второй батареи; выйти, оставив одну,
    // не даст requireTwo (предложит вернуть одиночный или удалить банк).
    final updated = app.banks.where((b) => b.id == bank.id).firstOrNull;
    if (updated != null &&
        updated.type != BankType.single &&
        updated.batteries.length < 2 &&
        context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            DeviceScanScreen(targetBankId: bank.id, requireTwo: true),
      ));
    }
  }

  Future<void> _delete(BuildContext context, Bank bank) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(tr('delete_bank_q'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          tr('message_055', [bank.name, bank.batteries.isNotEmpty ? AppStrings.plural('message_152', bank.batteries.length) : '']),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'),
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                 Text(tr('delete'), style: TextStyle(color: AppColors.socRed)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().deleteBank(bank.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _unbindBattery(
      BuildContext context, Bank bank, String deviceId, String name) async {
    // Ограничения состава (тест 26.07 п.8): в параллельном/последовательном
    // банке не может остаться меньше двух АКБ; последняя АКБ одиночного —
    // только вместе с банком.
    if (bank.type != BankType.single && bank.batteries.length == 2) {
      // Тупик из видео 31.07: parallel(2) нельзя было ни ужать, ни сделать
      // одиночным. Решение: отвязка второй АКБ автоматически превращает
      // банк в одиночный — с явным подтверждением.
      final okSingle = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(tr('message_056'),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
          content: Text(
            tr('message_057', [name, bank.name]),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'),
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('message_058'),
                  style: TextStyle(color: AppColors.socRed)),
            ),
          ],
        ),
      );
      if (okSingle == true && context.mounted) {
        final app = context.read<AppState>();
        await app.removeBattery(bank.id, deviceId);
        app.renameBank(bank.id, type: BankType.single);
      }
      return;
    }
    if (bank.batteries.length <= 1) {
      // последняя батарея — банк пустым не оставляем
      final okDel = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(tr('message_059'),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
          content: Text(
            tr('message_060', [name, bank.name]),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'),
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('delete_bank'),
                  style: TextStyle(color: AppColors.socRed)),
            ),
          ],
        ),
      );
      if (okDel == true && context.mounted) {
        await context.read<AppState>().deleteBank(bank.id);
        if (context.mounted) Navigator.of(context).pop();
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(tr('message_061'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          tr('message_062', [name, bank.name]),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'),
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:  Text(tr('message_058'),
                style: TextStyle(color: AppColors.socRed)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().removeBattery(bank.id, deviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context); // Rebuild open routes when the locale changes.
    final app = context.watch<AppState>();
    final bank = app.banks.where((b) => b.id == bankId).firstOrNull;

    if (bank == null) {
      // Банк удалён — экран закрывается кнопкой назад
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.bg),
        body: Center(
          child: Text(tr('message_044'),
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final agg = bank.aggregate;

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
              child: Text(bank.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: tr('rename_icon'),
            icon: Icon(Icons.drive_file_rename_outline,
                size: 20, color: AppColors.accent),
            onPressed: () => _edit(context, bank),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${bank.type.label} • SOC ${agg.soc.toStringAsFixed(0)} % • '
              '${agg.voltage.toStringAsFixed(1)} V',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          // Неполный parallel/series банк — просим добавить вторую АКБ (26.07)
          if (bank.type != BankType.single && bank.batteries.length < 2)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.socYellow.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.socYellow.withValues(alpha: 0.55)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.socYellow),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        tr('message_063', [bank.type.label]),
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 13)),
                  ),
                ],
              ),
            ),
          _sectionTitle(tr('message_064', [bank.batteries.length])),
          if (bank.batteries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(tr('no_batteries'),
                  style:
                      TextStyle(color: AppColors.textLabel, fontSize: 13)),
            ),
          for (final b in bank.batteries)
            _batteryRow(context, bank, b.deviceId, b.bleName,
                '${b.totalVoltage.toStringAsFixed(1)} V • ${b.soc.toStringAsFixed(0)} %'),
          // Одиночный банк с батареей — добавлять больше нельзя (22.07 п.2)
          if (app.canAddBatteryTo(bank) == null)
            _actionRow(
              context,
              icon: Icons.bluetooth_searching,
              label: tr('add_battery'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DeviceScanScreen(targetBankId: bank.id),
              )),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                tr('message_065'),
                style: TextStyle(color: AppColors.textLabel, fontSize: 12),
              ),
            ),
          _sectionTitle(tr('message_066')),
          _actionRow(
            context,
            icon: Icons.drive_file_rename_outline,
            label: tr('rename_icon'),
            onTap: () => _edit(context, bank),
          ),
          _actionRow(
            context,
            icon: Icons.delete_outline,
            label: tr('delete_bank'),
            color: AppColors.socRed,
            onTap: () => _delete(context, bank),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text,
            style: TextStyle(
                color: AppColors.textLabel,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0)),
      );

  Widget _batteryRow(BuildContext context, Bank bank, String deviceId,
      String name, String value) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            BatteryDetailScreen(bankId: bank.id, deviceId: deviceId),
      )),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.battery_std, size: 15, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14)),
            ),
            Text(value,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            IconButton(
              tooltip: tr('unbind_battery'),
              visualDensity: VisualDensity.compact,
              // Красный «минус» — заметный, как просили после теста
              // дистрибьютора (26.07 п.9: кнопку никто не находил)
              icon: const Icon(Icons.remove_circle,
                  size: 20, color: AppColors.socRed),
              onPressed: () => _unbindBattery(context, bank, deviceId, name),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textLabel),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color ?? AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color ?? AppColors.textPrimary, fontSize: 14)),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textLabel),
          ],
        ),
      ),
    );
  }
}
