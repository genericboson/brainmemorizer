import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../models.dart';
import 'auth_gateway.dart';

/// 기기 간 동기화. 로그인한 계정의 `users/{uid}` 아래에 로컬 [AppState] 를
/// 비추고, 같은 계정으로 로그인한 다른 기기의 변경을 받아 온다.
///
/// 로컬이 원본이다: 앱은 로그인하지 않아도, 네트워크가 없어도 그대로 동작하고,
/// 연결되면 양쪽 변경이 `updatedAt` 이 최신인 쪽으로 합쳐진다.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.state,
    required FirebaseFirestore firestore,
    required SharedPreferences prefs,
    required AuthGateway auth,
    this.initialRetry = const Duration(seconds: 5),
    this.maxRetry = const Duration(minutes: 5),
  }) : _firestore = firestore, // ignore: prefer_initializing_formals
       _prefs = prefs, // ignore: prefer_initializing_formals
       _auth = auth, // ignore: prefer_initializing_formals
       _retryDelay = initialRetry;

  static const _autoLoginPref = 'brainmemorizer.autoLogin';

  final AppState state;
  final FirebaseFirestore _firestore;
  final SharedPreferences _prefs;
  final AuthGateway _auth;

  /// 연결에 실패했을 때 다시 시도하기까지의 간격. 실패할 때마다 두 배로 늘어
  /// [maxRetry] 까지 간다.
  final Duration initialRetry;
  final Duration maxRetry;
  Duration _retryDelay;
  Timer? _retryTimer;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StreamSubscription<StateChange>? _localSubscription;
  StreamSubscription<AuthUser?>? _authSubscription;

  String? _uid;

  AuthUser? get user => _auth.currentUser;
  bool get signedIn => _uid != null;

  /// 앱을 다시 켤 때 로그인을 유지할지. 끄면 다음 시작 때 로그아웃된 상태로 뜬다.
  bool get autoLogin => _prefs.getBool(_autoLoginPref) ?? true;

  bool _connected = false;
  bool get connected => _connected;

  bool _busy = false;
  bool get busy => _busy;

  String? _lastError;
  String? get lastError => _lastError;

  Future<void> setAutoLogin(bool value) async {
    await _prefs.setBool(_autoLoginPref, value);
    notifyListeners();
  }

  Future<void> start() async {
    if (!autoLogin && _auth.currentUser != null) {
      await _auth.signOut();
    }
    _localSubscription ??= state.changes.listen(_pushChange);
    _authSubscription ??= _auth.userChanges.listen(_onUserChanged);
  }

  Future<bool> signIn(String email, String password) =>
      _authAction(() => _auth.signIn(email.trim(), password));

  Future<bool> signUp(String email, String password) =>
      _authAction(() => _auth.signUp(email.trim(), password));

  Future<void> signOut() => _auth.signOut();

  Future<bool> _authAction(Future<void> Function() action) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      _lastError = e.message;
      return false;
    } catch (e) {
      _lastError = '$e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _cancelRemote();
    _localSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  // ---- 로그인 상태 ---------------------------------------------------------

  Future<void> _onUserChanged(AuthUser? user) async {
    _retryTimer?.cancel();
    _cancelRemote();
    _connected = false;
    _uid = user?.uid;
    notifyListeners();
    if (user != null) await _connect();
  }

  /// 원격을 구독하고 로컬 전체를 밀어 넣는다.
  /// 실패하면 [_retryDelay] 뒤에 다시 시도한다 (오프라인 시작, 일시적 네트워크 오류).
  Future<void> _connect() async {
    _retryTimer?.cancel();
    if (_uid == null) return;
    try {
      if (_subscriptions.isEmpty) _subscribeRemote();
      await _pushAll();
      _connected = true;
      _lastError = null;
      _retryDelay = initialRetry;
      debugPrint('동기화 연결됨: ${user?.email}');
    } catch (e) {
      _connected = false;
      _lastError = '$e';
      debugPrint('동기화 연결 실패 (${_retryDelay.inSeconds}초 뒤 재시도): $e');
      _retryTimer = Timer(_retryDelay, _connect);
      final doubled = _retryDelay * 2;
      _retryDelay = doubled > maxRetry ? maxRetry : doubled;
    }
    notifyListeners();
  }

  // ---- 원격 → 로컬 --------------------------------------------------------

  DocumentReference<Map<String, dynamic>> get _space =>
      _firestore.collection('users').doc(_uid);

  void _subscribeRemote() {
    _subscriptions.addAll([
      _space.collection('categories').snapshots().listen(_onCategories),
      _space.collection('cards').snapshots().listen(_onCards),
      _space.collection('meta').doc('profile').snapshots().listen(_onProfile),
    ]);
  }

  // 구독 해제 완료를 기다리지 않는다. 기다리면 로그아웃 처리가 그 뒤로 밀린다.
  void _cancelRemote() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
  }

  void _onCategories(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      final data = change.doc.data();
      if (change.type == DocumentChangeType.removed) {
        state.applyRemoteCategoryDeleted(change.doc.id);
      } else if (data != null) {
        state.applyRemoteCategory(
          StudyCategory.fromJson({...data, 'id': change.doc.id}),
        );
      }
    }
  }

  void _onCards(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      final data = change.doc.data();
      if (change.type == DocumentChangeType.removed) {
        state.applyRemoteCardDeleted(change.doc.id);
      } else if (data != null) {
        state.applyRemoteCard(
          StudyCard.fromJson({...data, 'id': change.doc.id}),
        );
      }
    }
  }

  void _onProfile(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return;
    state.applyRemoteProfile(
      (data['memoryFactor'] as num).toDouble(),
      DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int),
    );
  }

  // ---- 로컬 → 원격 --------------------------------------------------------

  Future<void> _pushAll() => _write(state.snapshotChanges());

  Future<void> _pushChange(StateChange change) async {
    if (!_connected) return; // 재연결될 때 _pushAll 이 전체를 다시 보낸다.
    try {
      await _write([change]);
    } catch (e) {
      // 이 변경은 못 보냈다. 재연결하면서 전체를 다시 밀어 넣는다.
      _connected = false;
      _lastError = '$e';
      _retryTimer?.cancel();
      _retryTimer = Timer(_retryDelay, _connect);
      notifyListeners();
    }
  }

  Future<void> _write(List<StateChange> changes) async {
    if (changes.isEmpty) return;
    final categories = _space.collection('categories');
    final cards = _space.collection('cards');
    final profile = _space.collection('meta').doc('profile');

    // Firestore 배치는 500개까지라 나눠서 보낸다.
    var batch = _firestore.batch();
    var count = 0;
    Future<void> flushIfFull() async {
      if (++count < 400) return;
      await batch.commit();
      batch = _firestore.batch();
      count = 0;
    }

    for (final change in changes) {
      switch (change) {
        case CategoryUpserted(:final category):
          batch.set(categories.doc(category.id), category.toJson());
          await flushIfFull();
        case CategoryDeleted(:final id, :final cardIds):
          batch.delete(categories.doc(id));
          await flushIfFull();
          for (final cardId in cardIds) {
            batch.delete(cards.doc(cardId));
            await flushIfFull();
          }
        case CardUpserted(:final card):
          batch.set(cards.doc(card.id), card.toJson());
          await flushIfFull();
        case CardDeleted(:final id):
          batch.delete(cards.doc(id));
          await flushIfFull();
        case ProfileChanged(:final memoryFactor, :final updatedAt):
          batch.set(profile, {
            'memoryFactor': memoryFactor,
            'updatedAt': updatedAt.millisecondsSinceEpoch,
          });
          await flushIfFull();
      }
    }
    if (count > 0) await batch.commit();
  }
}
