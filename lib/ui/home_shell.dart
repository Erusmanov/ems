import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'alarms_screen.dart';
import 'banks_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';

/// Корневой каркас с нижней навигацией.
/// 4 вкладки (решение Михаила 23.06): Домой · Банки · Алармы · Настройки.
/// Привязка устройств — внутри флоу «Банки».
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context); // Rebuild open routes when the locale changes.
    final alerts = context.watch<AppState>().activeAlertCount;
    final screens = [
      const DashboardScreen(),
      const BanksScreen(),
      const AlarmsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        backgroundColor: AppColors.card,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textSecondary,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: [
           BottomNavigationBarItem(
              icon: Icon(Icons.home_filled), label: tr('nav_home')),
           BottomNavigationBarItem(
              icon: Icon(Icons.battery_charging_full), label: tr('nav_banks')),
          BottomNavigationBarItem(
              // Бейдж-восклицательный знак при активных событиях (02.08)
              icon: alerts > 0
                  ? Badge(
                      backgroundColor: AppColors.socRed,
                      label: Text('$alerts',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9)),
                      child: const Icon(Icons.notifications_none),
                    )
                  : const Icon(Icons.notifications_none),
              label: tr('nav_alerts')),
           BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: tr('nav_settings')),
        ],
      ),
    );
  }
}
