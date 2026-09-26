import 'dart:io';

import 'package:nativeapi/nativeapi.dart';

/// OS 로그인 시 자동 실행 설정.
abstract class StartupSettings {
  /// 이 플랫폼에서 자동 실행을 설정할 수 있는지.
  bool get isSupported;

  bool get isEnabled;

  /// 성공하면 true.
  bool setEnabled(bool enabled);
}

/// OS 의 로그인 시작 프로그램 목록(Windows 는 레지스트리 Run 키)에 앱을 등록한다.
///
/// 등록할 때 `--hidden` 인자를 붙여서, 부팅 후에는 창 없이 트레이에만 뜬다.
class NativeStartupSettings implements StartupSettings {
  NativeStartupSettings({required this.appName});

  static const startHiddenFlag = '--hidden';

  final String appName;
  LaunchAtLogin? _launch;

  LaunchAtLogin? get _entry =>
      _launch ??= LaunchAtLogin.createWithIdAndDisplayName(
        appName.replaceAll(' ', ''),
        appName,
      );

  @override
  bool get isSupported => LaunchAtLogin.isSupported() && _entry != null;

  @override
  bool get isEnabled => _entry?.isEnabled ?? false;

  @override
  bool setEnabled(bool enabled) {
    final entry = _entry;
    if (entry == null) return false;
    if (!enabled) return entry.disable();
    // 실행 파일 경로를 매번 다시 적는다. 앱을 옮겨도 등록이 깨지지 않도록.
    if (!entry.setProgram(Platform.resolvedExecutable, [startHiddenFlag])) {
      return false;
    }
    return entry.enable();
  }
}
