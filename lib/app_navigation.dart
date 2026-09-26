import 'package:flutter/foundation.dart';

/// 화면 밖(트레이 메뉴, 알림 클릭)에서 앱 화면을 옮길 때 쓰는 통로.
class AppNavigation extends ChangeNotifier {
  static const inputTab = 0;
  static const studyTab = 1;

  int _requestedTab = inputTab;

  int get requestedTab => _requestedTab;

  void showStudyTab() {
    _requestedTab = studyTab;
    notifyListeners();
  }
}
