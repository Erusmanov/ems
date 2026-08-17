import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final settingsBox = await Hive.openBox(SettingsState.boxName);
  final banksBox = await Hive.openBox(AppState.banksBoxName);
  await NotificationService.init();
  runApp(EmPowerApp(settingsBox: settingsBox, banksBox: banksBox));
}

class _ClampedScrollBehavior extends MaterialScrollBehavior {
  const _ClampedScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child; // без stretch/glow-эффекта на краях
}

class EmPowerApp extends StatefulWidget {
  final Box settingsBox;
  final Box banksBox;
  const EmPowerApp(
      {super.key, required this.settingsBox, required this.banksBox});

  @override
  State<EmPowerApp> createState() => _EmPowerAppState();
}

class _EmPowerAppState extends State<EmPowerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Режим «Как в системе»: перерисоваться при смене системной темы.
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsState>(
            create: (_) => SettingsState(widget.settingsBox)),
        // Старт с нуля как в реале: восстановление сохранённых банков;
        // демо-банки — только если включены в настройках.
        ChangeNotifierProvider<AppState>(create: (context) {
          final settings = context.read<SettingsState>();
          final app = AppState(
            banksBox: widget.banksBox,
            socWarning: settings.socWarning,
            socCritical: settings.socCritical,
          );
          final demo = settings.demoMode;
          demo ? app.initMock() : app.initFromStore();
          return app;
        }),
      ],
      child: Consumer<SettingsState>(
        builder: (context, settings, _) {
          NotificationService.enabled = settings.lowSocNotify;
          final dark = settings.resolveDark(
              WidgetsBinding.instance.platformDispatcher.platformBrightness);
          AppColors.apply(dark: dark);
          // Явные цвета системных полос: без них статус-бар и нижняя
          // навигация Android зависали в цвете старой темы до первого тапа
          // (баг Михаила 03.08, стабильно повторялся на планшете)
          final overlay = SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: AppColors.bg,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
          );
          SystemChrome.setSystemUIOverlayStyle(overlay);
          return MaterialApp(
            title: 'EM-Power',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.of(dark: dark),
            // Без «резинового» оверскролла: списки упираются в край,
            // пустоту вниз не потянуть (комментарий Михаила 15.07, п.9)
            scrollBehavior: const _ClampedScrollBehavior(),
            // KeyedSubtree по теме: полная пересборка дерева при переключении.
            // Иначе const-виджеты и неактивные вкладки оставались в цветах
            // старой темы («экзотические раскрасы», видео Михаила 17.08) —
            // статическая палитра AppColors не пробивает их кэш.
            home: AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlay,
              child: KeyedSubtree(
                key: ValueKey('theme-$dark'),
                child: const HomeShell(),
              ),
            ),
          );
        },
      ),
    );
  }
}
