import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_navigation.dart';
import 'app_state.dart';
import 'desktop/desktop_shell.dart';
import 'firebase_options.dart';
import 'screens/input_tab.dart';
import 'screens/settings_page.dart';
import 'screens/study_tab.dart';
import 'services/startup_settings.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.load();
  final navigation = AppNavigation();
  StartupSettings? startupSettings;
  if (DesktopShell.isSupported) {
    await DesktopShell(state: state, navigation: navigation).init();
    startupSettings = NativeStartupSettings(appName: DesktopShell.appName);
  }
  final sync = await _startSync(state);
  runApp(
    BrainMemorizerApp(
      state: state,
      navigation: navigation,
      startupSettings: startupSettings,
      sync: sync,
    ),
  );
}

/// 디버그 빌드에서만: 이 앱 프로세스가 Firebase 서버에 HTTPS 로 닿는지 기록한다.
Future<void> _probeNetwork() async {
  if (!kDebugMode) return;
  for (final host in ['identitytoolkit.googleapis.com', 'www.google.com']) {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final response = await client
          .getUrl(Uri.https(host, '/'))
          .then((r) => r.close());
      debugPrint('네트워크 진단 $host: HTTP ${response.statusCode}');
      client.close(force: true);
    } catch (e) {
      debugPrint('네트워크 진단 $host: 실패 $e');
    }
  }
}

/// Firebase 를 켜고 동기화를 시작한다. 실패해도 앱은 로컬 데이터로 그냥 돈다.
Future<SyncService?> _startSync(AppState state) async {
  unawaited(_probeNetwork());
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final sync = SyncService(
      state: state,
      firestore: FirebaseFirestore.instance,
      prefs: await SharedPreferences.getInstance(),
      signIn: () async {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
      },
    );
    // 연결은 기다리지 않는다. 오프라인이면 설정 화면에 "연결 안 됨"으로 보인다.
    unawaited(sync.start());
    return sync;
  } catch (e) {
    debugPrint('동기화 초기화 실패: $e');
    return null;
  }
}

class BrainMemorizerApp extends StatelessWidget {
  const BrainMemorizerApp({
    super.key,
    required this.state,
    this.navigation,
    this.startupSettings,
    this.sync,
  });

  final AppState state;
  final AppNavigation? navigation;
  final StartupSettings? startupSettings;
  final SyncService? sync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: DesktopShell.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomePage(
        state: state,
        navigation: navigation,
        startupSettings: startupSettings,
        sync: sync,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.state,
    this.navigation,
    this.startupSettings,
    this.sync,
  });

  final AppState state;
  final AppNavigation? navigation;
  final StartupSettings? startupSettings;
  final SyncService? sync;

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
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsPage(
                  startupSettings: widget.startupSettings,
                  sync: widget.sync,
                ),
              ),
            ),
          ),
        ],
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
