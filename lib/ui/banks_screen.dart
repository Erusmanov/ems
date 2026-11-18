import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bank.dart';
import '../models/bank_icons.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'bank_config_screen.dart';
import 'device_scan_screen.dart';


/// Вкладка «Банки»: список банков + создание/переименование/удаление (этап Э3/M4).
/// Стиль строк — как экран поиска устройств (решение Михаила 30.06/12.07).
class BanksScreen extends StatelessWidget {
  const BanksScreen({super.key});

  void _openScan(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
    );
  }

  /// Создание банка: параметры -> сразу подключение первой АКБ.
  /// Банк появляется только вместе с батареей (пустых не бывает, 22.07 п.3).
  Future<void> _createBank(BuildContext context) async {
    final result = await showDialog<(String, String, BankType)>(
      context: context,
      builder: (_) => const BankEditDialog(),
    );
    if (result == null || !context.mounted) return;
    final (name, iconId, type) = result;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeviceScanScreen(
          pendingBank: (name: name, iconId: iconId, type: type)),
    ));
  }

  /// Тап по банку — всегда экран КОНФИГУРАЦИИ банка (решение Михаила 15.07);
  /// к ячейкам конкретной батареи — уже оттуда.
  void _openBank(BuildContext context, Bank bank) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BankConfigScreen(bankId: bank.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context); // Rebuild open routes when the locale changes.
    final app = context.watch<AppState>();
    final banks = app.banks;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text(tr('nav_banks'),
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: tr('connect_device'),
            onPressed: () => _openScan(context),
            icon: Icon(Icons.bluetooth_searching,
                color: AppColors.accent),
          ),
          IconButton(
            tooltip: tr('create_bank'),
            onPressed: () => _createBank(context),
            icon: Icon(Icons.add, color: AppColors.accent),
          ),
        ],
      ),
      body: banks.isEmpty
          ? _emptyState(context)
          : ListView(
              children: [
                for (final bank in banks) _bankRow(context, bank),
              ],
            ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.battery_unknown,
              size: 44, color: AppColors.textLabel),
          const SizedBox(height: 12),
          Text(tr('no_banks'),
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _openScan(context),
            icon: Icon(Icons.bluetooth_searching, size: 18),
            label: Text(tr('connect_device')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bankRow(BuildContext context, Bank bank) {
    final agg = bank.aggregate;
    final subtitle =
        tr('message_052', [bank.type.label, AppStrings.plural('battery_count', bank.batteries.length), agg.soc.toStringAsFixed(0)]);
    return InkWell(
      onTap: () => _openBank(context, bank),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            BankIcon(bank.iconId, size: 32, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bank.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textLabel, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.bluetooth,
                size: 16,
                color: bank.connected
                    ? AppColors.bluetooth
                    : AppColors.textLabel),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textLabel),
          ],
        ),
      ),
    );
  }
}

/// Диалог создания/редактирования банка: имя, иконка из библиотеки, тип
/// (редактируется и после создания — решение Михаила 15.07).
/// Используется здесь и на экране конфигурации банка.
class BankEditDialog extends StatefulWidget {
  final Bank? bank;
  const BankEditDialog({super.key, this.bank});

  @override
  State<BankEditDialog> createState() => _BankEditDialogState();
}

class _BankEditDialogState extends State<BankEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.bank?.name ?? '');
  final _scroll = ScrollController();
  String? _nameError;
  late String _icon = widget.bank?.iconId ?? bankIconLibrary.first.id;
  late BankType _type = widget.bank?.type ?? BankType.single;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context); // Rebuild open routes when the locale changes.
    final isEdit = widget.bank != null;
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(isEdit ? tr('bank') : tr('new_bank'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
      content: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: !isEdit,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: tr('bank_name'),
                errorText: _nameError,
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.cardBorder)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent)),
              ),
            ),
            const SizedBox(height: 16),
            Text(tr('bank_icon'),
                style: TextStyle(
                    color: AppColors.textLabel,
                    fontSize: 10,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final def in bankIconChoices)
                  Tooltip(
                    message: def.label,
                    child: InkWell(
                      onTap: () => setState(() => _icon = def.id),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: def.id == _icon
                              ? AppColors.accent.withValues(alpha: 0.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: def.id == _icon
                                  ? AppColors.accent
                                  : AppColors.cardBorder),
                        ),
                        child: BankIcon(def.id,
                            size: 30,
                            color: def.id == _icon
                                ? AppColors.accent
                                : AppColors.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
            ...[
              const SizedBox(height: 16),
              Text(tr('bank_type'),
                  style: TextStyle(
                      color: AppColors.textLabel,
                      fontSize: 10,
                      letterSpacing: 0.8)),
              const SizedBox(height: 4),
              for (final t in BankType.values)
                RadioListTile<BankType>(
                  value: t,
                  groupValue: _type,
                  onChanged: (v) => setState(() => _type = v!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.accent,
                  title: Text(t.label,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14)),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('cancel'),
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              // Раньше кнопка молча не работала — юзер не понимал, в чём дело
              setState(() => _nameError = tr('message_053'));
              _scroll.animateTo(0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut); // ошибка всегда на виду (видео 02.08)
              return;
            }
            // Имена банков уникальны (тест 26.07 п.7): дубль запутает юзера
            final dup = context.read<AppState>().banks.any((b) =>
                b.name.trim().toLowerCase() == name.toLowerCase() &&
                b.id != widget.bank?.id);
            if (dup) {
              setState(() => _nameError = tr('message_054'));
              _scroll.animateTo(0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut);
              return;
            }
            Navigator.pop(context, (name, _icon, _type));
          },
          child: Text(tr('save'),
              style: TextStyle(color: AppColors.accent)),
        ),
      ],
    );
  }
}

