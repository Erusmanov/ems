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
          const BottomNavigationBarItem(
              icon: Icon(Icons.home_filled), label: 'Домой'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.battery_charging_full), label: 'Банки'),
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
              label: 'Уведомления'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Настройки'),
        ],
      ),
    );
  }
}
