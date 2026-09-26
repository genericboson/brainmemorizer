import 'package:flutter/material.dart';

import '../services/startup_settings.dart';

/// 톱니바퀴 아이콘으로 여는 설정 화면.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.startupSettings});

  /// null 이면 이 플랫폼에서는 자동 실행을 설정할 수 없다.
  final StartupSettings? startupSettings;

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
        ],
      ),
    );
  }
}
