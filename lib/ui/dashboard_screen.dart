import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'device_scan_screen.dart';
import 'widgets/battery_card.dart';
import 'widgets/em_power_logo.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context); // Rebuild open routes when the locale changes.
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 16,
        title: const EmPowerLogo(),
        actions: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: app.anyConnected ? AppColors.socGreen : AppColors.textLabel,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(app.anyConnected ? tr('connected') : tr('disconnected'),
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          IconButton(
            tooltip: tr('connect_device'),
            icon: Icon(Icons.bluetooth_searching, color: AppColors.accent),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
            ),
          ),
        ],
      ),
      body: app.banks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.battery_unknown,
                      size: 44, color: AppColors.textLabel),
                  const SizedBox(height: 12),
                  Text(tr('no_banks_yet'),
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(tr('no_banks_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DeviceScanScreen()),
                    ),
                    icon: const Icon(Icons.bluetooth_searching, size: 18),
                    label:  Text(tr('connect_device')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (final bank in app.banks) BatteryCard(bank: bank),
                const SizedBox(height: 12),
              ],
            ),
    );
  }
}

