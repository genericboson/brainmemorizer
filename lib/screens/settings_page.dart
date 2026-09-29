import 'package:flutter/material.dart';

import '../services/auth_gateway.dart';
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

  StartupSettings? get _startup {
    final s = widget.startupSettings;
    return (s != null && s.isSupported) ? s : null;
  }

  @override
  void initState() {
    super.initState();
    _launchAtLogin = _startup?.isEnabled ?? false;
  }

  void _toggleLaunchAtLogin(bool value) {
    final ok = _startup!.setEnabled(value);
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('자동 실행 설정을 바꾸지 못했습니다.')));
    }
    setState(() => _launchAtLogin = _startup!.isEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final startup = _startup;
    final sync = widget.sync;
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          if (sync == null)
            const ListTile(
              title: Text('계정 및 동기화'),
              subtitle: Text('지금은 쓸 수 없습니다 (동기화 서비스 초기화 실패).'),
            )
          else
            AccountSection(sync: sync),
          const Divider(),
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
        ],
      ),
    );
  }
}

/// 로그인/회원가입/로그아웃과 자동 로그인 체크박스. 로그인하면 같은 계정의
/// 모든 기기가 학습데이터와 학습 상태를 공유한다.
class AccountSection extends StatefulWidget {
  const AccountSection({super.key, required this.sync});

  final SyncService sync;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  SyncService get sync => widget.sync;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate() {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이메일과 비밀번호를 입력하세요.')));
      return false;
    }
    return true;
  }

  Future<void> _signIn() async {
    if (!_validate()) return;
    if (await sync.signIn(_email.text, _password.text)) _password.clear();
  }

  Future<void> _signUp() async {
    if (!_validate()) return;
    if (await sync.signUp(_email.text, _password.text)) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final user = sync.user;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('계정 및 동기화', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (user == null) ..._loggedOut(context) else ..._loggedIn(user),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('자동 로그인'),
                subtitle: const Text('앱을 다시 켤 때 로그인 상태를 유지합니다.'),
                value: sync.autoLogin,
                onChanged: (v) => sync.setAutoLogin(v ?? true),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _loggedOut(BuildContext context) => [
    const Text('로그인하면 같은 계정으로 로그인한 폰과 컴퓨터가 학습데이터와 학습 상태를 자동으로 공유합니다.'),
    const SizedBox(height: 12),
    TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: '이메일',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      textInputAction: TextInputAction.next,
    ),
    const SizedBox(height: 8),
    TextField(
      controller: _password,
      obscureText: !_showPassword,
      decoration: InputDecoration(
        labelText: '비밀번호',
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          tooltip: _showPassword ? '비밀번호 숨기기' : '비밀번호 보기',
          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _showPassword = !_showPassword),
        ),
      ),
      onSubmitted: (_) => _signIn(),
    ),
    if (sync.lastError != null) ...[
      const SizedBox(height: 8),
      Text(
        sync.lastError!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ],
    const SizedBox(height: 12),
    Row(
      children: [
        FilledButton(
          onPressed: sync.busy ? null : _signIn,
          child: const Text('로그인'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: sync.busy ? null : _signUp,
          child: const Text('회원가입'),
        ),
        if (sync.busy) ...[
          const SizedBox(width: 12),
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    ),
    const SizedBox(height: 8),
  ];

  List<Widget> _loggedIn(AuthUser user) => [
    Text('로그인됨: ${user.email}'),
    const SizedBox(height: 4),
    Text(
      sync.connected
          ? '동기화 중 · 학습데이터나 학습 상태가 바뀔 때마다 바로 반영됩니다.'
          : '동기화 연결 안 됨: ${sync.lastError ?? '네트워크를 확인하세요. 자동으로 다시 시도합니다.'}',
      style: Theme.of(context).textTheme.bodySmall,
    ),
    const SizedBox(height: 12),
    OutlinedButton(onPressed: sync.signOut, child: const Text('로그아웃')),
    const SizedBox(height: 8),
  ];
}
