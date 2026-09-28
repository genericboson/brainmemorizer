import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/startup_settings.dart';
import '../services/sync_service.dart';

/// 톱니바퀴 아이콘으로 여는 설정 화면.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.startupSettings, this.sync});

  /// null 이면 이 플랫폼에서는 자동 실행을 설정할 수 없다.
  final StartupSettings? startupSettings;

  /// null 이면 동기화를 쓸 수 없다 (Firebase 초기화 실패 등).
  final SyncService? sync;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _launchAtLogin;
  final _keyController = TextEditingController();
  bool _switching = false;

  StartupSettings? get _startup {
    final s = widget.startupSettings;
    return (s != null && s.isSupported) ? s : null;
  }

  @override
  void initState() {
    super.initState();
    _launchAtLogin = _startup?.isEnabled ?? false;
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _toggleLaunchAtLogin(bool value) {
    final ok = _startup!.setEnabled(value);
    if (!ok) _showMessage('자동 실행 설정을 바꾸지 못했습니다.');
    setState(() => _launchAtLogin = _startup!.isEnabled);
  }

  Future<void> _copyKey(String key) async {
    await Clipboard.setData(ClipboardData(text: key));
    if (mounted) _showMessage('연결 코드를 복사했습니다.');
  }

  Future<void> _useKey() async {
    final sync = widget.sync!;
    final key = SyncService.normalizeKey(_keyController.text);
    if (key == null) {
      _showMessage('연결 코드는 영문·숫자 12자리입니다 (예: ABCD-EFGH-JKLM).');
      return;
    }
    if (key == sync.syncKey) {
      _showMessage('이미 이 코드를 쓰고 있습니다.');
      return;
    }
    setState(() => _switching = true);
    await sync.useKey(key);
    if (!mounted) return;
    setState(() => _switching = false);
    _keyController.clear();
    _showMessage(
      sync.connected
          ? '연결했습니다. 두 기기의 데이터가 합쳐집니다.'
          : '연결하지 못했습니다: ${sync.lastError}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final startup = _startup;
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Windows 시작 시 자동 실행'),
            subtitle: Text(
              startup == null
                  ? '이 기기에서는 지원하지 않습니다.'
                  : '로그인하면 창을 열지 않고 트레이에만 떠서, 복습할 때가 되면 알림을 보냅니다.',
            ),
            value: _launchAtLogin,
            onChanged: startup == null ? null : _toggleLaunchAtLogin,
          ),
          const Divider(),
          _buildSyncSection(context),
        ],
      ),
    );
  }

  Widget _buildSyncSection(BuildContext context) {
    final sync = widget.sync;
    final textTheme = Theme.of(context).textTheme;
    if (sync == null) {
      return const ListTile(
        title: Text('기기 간 동기화'),
        subtitle: Text('지금은 쓸 수 없습니다 (동기화 서비스 초기화 실패).'),
      );
    }
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('기기 간 동기화', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              sync.connected
                  ? '연결됨 · 같은 연결 코드를 쓰는 기기끼리 학습데이터와 복습 기록을 공유합니다.'
                  : '연결 안 됨: ${sync.lastError ?? '네트워크를 확인하세요.'}',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('이 기기의 연결 코드', style: textTheme.labelLarge),
            Row(
              children: [
                SelectableText(sync.syncKey, style: textTheme.headlineSmall),
                IconButton(
                  tooltip: '복사',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyKey(sync.syncKey),
                ),
              ],
            ),
            const Text('다른 기기의 설정에서 이 코드를 입력하면 그 기기가 이쪽 데이터에 합류합니다.'),
            const SizedBox(height: 16),
            Text('다른 기기의 코드로 연결', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyController,
                    decoration: const InputDecoration(
                      hintText: 'ABCD-EFGH-JKLM',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _useKey(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _switching ? null : _useKey,
                  child: const Text('연결'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('연결하면 이 기기의 데이터도 그 코드 아래로 합쳐집니다. 이후 두 기기는 같은 코드를 씁니다.'),
          ],
        ),
      ),
    );
  }
}
