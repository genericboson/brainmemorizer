import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../models.dart';

/// 기기 간 동기화. 로컬 [AppState] 를 Firestore 의 `spaces/{연결 코드}` 아래에
/// 비추고, 같은 코드를 쓰는 다른 기기의 변경을 받아 온다.
///
/// 로컬이 원본이다: 앱은 네트워크 없이도 그대로 동작하고, 연결되면
/// 양쪽 변경이 `updatedAt` 이 최신인 쪽으로 합쳐진다.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.state,
    required FirebaseFirestore firestore,
    required SharedPreferences prefs,
    Future<void> Function()? signIn,
    this.initialRetry = const Duration(seconds: 5),
    this.maxRetry = const Duration(minutes: 5),
  }) : _firestore = firestore, // ignore: prefer_initializing_formals
       _prefs = prefs, // ignore: prefer_initializing_formals
       _signIn = signIn, // ignore: prefer_initializing_formals
       _retryDelay = initialRetry;

  /// 연결에 실패했을 때 다시 시도하기까지의 간격. 실패할 때마다 두 배로 늘어
  /// [maxRetry] 까지 간다.
  final Duration initialRetry;
  final Duration maxRetry;
  Duration _retryDelay;
  Timer? _retryTimer;

  static const _keyPref = 'brainmemorizer.syncKey';

  /// 연결 코드에 쓰는 글자. 헷갈리는 0/O, 1/I 는 뺐다.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final AppState state;
  final FirebaseFirestore _firestore;
  final SharedPreferences _prefs;
  final Future<void> Function()? _signIn;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  StreamSubscription<StateChange>? _localSubscription;

  late String _syncKey = _prefs.getString(_keyPref) ?? _storeKey(newKey());

  /// 이 기기의 연결 코드. 다른 기기에 이 코드를 넣으면 같은 데이터를 쓴다.
  String get syncKey => _syncKey;

  bool _connected = false;
  bool get connected => _connected;

  String? _lastError;
  String? get lastError => _lastError;

  /// `ABCD-EFGH-JKLM` 꼴의 새 코드.
  static String newKey() {
    final rng = Random.secure();
    final chars = List.generate(
      12,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
    return '${chars.substring(0, 4)}-${chars.substring(4, 8)}-${chars.substring(8)}';
  }

  /// 사용자가 입력한 코드를 정리한다. 형식이 틀리면 null.
  static String? normalizeKey(String input) {
    final chars = input.toUpperCase().replaceAll(RegExp('[^A-Z2-9]'), '');
    if (chars.length != 12 ||
        chars.split('').any((c) => !_alphabet.contains(c))) {
      return null;
    }
    return '${chars.substring(0, 4)}-${chars.substring(4, 8)}-${chars.substring(8)}';
  }

  String _storeKey(String key) {
    _prefs.setString(_keyPref, key);
    return key;
  }

  DocumentReference<Map<String, dynamic>> get _space =>
      _firestore.collection('spaces').doc(_syncKey);

  Future<void> start() async {
    _localSubscription ??= state.changes.listen(_pushChange);
    await _connect();
  }

  /// 로그인하고, 원격을 구독하고, 로컬 전체를 밀어 넣는다.
  /// 실패하면 [_retryDelay] 뒤에 다시 시도한다 (오프라인 시작, 일시적 네트워크 오류).
  Future<void> _connect() async {
    _retryTimer?.cancel();
    try {
      await _signIn?.call();
      if (_subscriptions.isEmpty) _subscribeRemote();
      await _pushAll();
      _connected = true;
      _lastError = null;
      _retryDelay = initialRetry;
      debugPrint('동기화 연결됨: 연결 코드 $_syncKey');
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

  /// 다른 기기의 코드로 갈아탄다. 이 기기의 데이터도 그 코드 아래로 밀어 넣어
  /// 양쪽이 합쳐진다 (id 가 다르므로 겹치지 않는다).
  Future<void> useKey(String key) async {
    if (key == _syncKey) return;
    await _cancelRemote();
    _storeKey(key);
    _syncKey = key;
    _subscribeRemote();
    try {
      await _pushAll();
      _connected = true;
      _lastError = null;
    } catch (e) {
      _connected = false;
      _lastError = '$e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _cancelRemote();
    _localSubscription?.cancel();
    super.dispose();
  }

  // ---- 원격 → 로컬 --------------------------------------------------------

  void _subscribeRemote() {
    _subscriptions.addAll([
      _space.collection('categories').snapshots().listen(_onCategories),
      _space.collection('cards').snapshots().listen(_onCards),
      _space.collection('meta').doc('profile').snapshots().listen(_onProfile),
    ]);
  }

  Future<void> _cancelRemote() async {
    for (final s in _subscriptions) {
      await s.cancel();
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
