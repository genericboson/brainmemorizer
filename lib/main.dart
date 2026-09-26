import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'app_state.dart';
import 'desktop/desktop_shell.dart';
import 'screens/input_tab.dart';
import 'screens/study_tab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();
  final navigation = AppNavigation();
  if (DesktopShell.isSupported) {
    await DesktopShell(state: state, navigation: navigation).init();
  }
  runApp(BrainMemorizerApp(state: state, navigation: navigation));
}

class BrainMemorizerApp extends StatelessWidget {
  const BrainMemorizerApp({super.key, required this.state, this.navigation});

  final AppState state;
  final AppNavigation? navigation;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: DesktopShell.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomePage(state: state, navigation: navigation),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, this.navigation});

  final AppState state;
  final AppNavigation? navigation;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    widget.navigation?.addListener(_onNavigationRequest);
  }

  @override
  void dispose() {
    widget.navigation?.removeListener(_onNavigationRequest);
    _tabs.dispose();
    super.dispose();
  }

  void _onNavigationRequest() {
    _tabs.animateTo(widget.navigation!.requestedTab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(DesktopShell.appName),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '학습데이터 주입'),
            Tab(text: '학습'),
          ],
        ),
      ),
      // 탭을 오가도 입력 중인 내용과 진행 중인 퀴즈가 사라지지 않도록
      // TabBarView 대신 IndexedStack 을 쓴다.
      body: IndexedStack(
        index: _tabs.index,
        children: [
          InputTab(state: widget.state),
          StudyTab(state: widget.state),
        ],
      ),
    );
  }
}
