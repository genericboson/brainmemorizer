import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app_navigation.dart';
import '../app_state.dart';
import '../services/review_scheduler.dart';

/// 데스크탑에서 앱을 트레이에 상주시킨다.
///
/// - 창을 닫으면 종료되지 않고 트레이로 숨는다.
/// - 트레이 아이콘 클릭이나 메뉴로 창을 다시 연다.
/// - 복습할 카드가 새로 생기면 알림을 띄우고, 클릭하면 '학습' 탭을 연다.
class DesktopShell with WindowListener {
  DesktopShell({required this.state, required this.navigation});

  static const appName = 'Brain Memorizer';
  static const _trayIconAsset = 'assets/tray_icon.ico';

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  final AppState state;
  final AppNavigation navigation;
  late final ReviewScheduler scheduler;
  late final TrayIcon _trayIcon;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await localNotifier.setup(appName: appName);

    scheduler = ReviewScheduler(state, onDue: _notifyDue);
    _createTrayIcon();
    scheduler.start();
    _updateToolTip();
  }

  void _createTrayIcon() {
    final icon = ImageAsset.fromAsset(_trayIconAsset);
    if (icon == null) {
      throw StateError('트레이 아이콘을 읽지 못했습니다: $_trayIconAsset');
    }
    final trayIcon = TrayIcon.create();
    if (trayIcon == null) throw StateError('트레이 아이콘을 만들지 못했습니다.');
    _trayIcon = trayIcon
      ..icon = icon
      ..setContextMenu(_buildMenu())
      ..setContextMenuTrigger(ContextMenuTrigger.rightClicked)
      ..addListener((event) {
        if (event is TrayIconClickedEvent ||
            event is TrayIconDoubleClickedEvent) {
          _showWindow();
        }
      })
      ..setVisible(true);
  }

  Menu _buildMenu() {
    final menu = Menu.create();
    if (menu == null) throw StateError('트레이 메뉴를 만들지 못했습니다.');
    menu
      ..addItem(_menuItem('열기', _showWindow))
      ..addItem(_menuItem('지금 복습하기', _openStudy))
      ..addSeparator()
      ..addItem(_menuItem('종료', _quit));
    return menu;
  }

  MenuItem _menuItem(String label, Future<void> Function() onClick) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) throw StateError("메뉴 항목 '$label'을 만들지 못했습니다.");
    item.addListener((event) {
      if (event is MenuItemClickedEvent) onClick();
    });
    return item;
  }

  Future<void> _notifyDue(int count) async {
    _updateToolTip();
    final notification = LocalNotification(
      title: '복습할 시간입니다',
      body: '망각곡선상 지금 복습할 문제가 $count개 있습니다. 클릭하면 학습을 시작합니다.',
    );
    notification.onClick = _openStudy;
    await notification.show();
  }

  void _updateToolTip() {
    final count = scheduler.dueCount;
    _trayIcon.setTooltip(count == 0 ? appName : '$appName · 복습할 문제 $count개');
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _openStudy() async {
    await _showWindow();
    navigation.showStudyTab();
  }

  Future<void> _quit() async {
    scheduler.dispose();
    _trayIcon
      ..setVisible(false)
      ..dispose();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // 창을 닫으면 트레이로 숨긴다.
  @override
  void onWindowClose() => windowManager.hide();
}
