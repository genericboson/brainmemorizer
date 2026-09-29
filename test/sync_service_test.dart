import 'dart:async';

import 'package:brainmemorizer/app_state.dart';
import 'package:brainmemorizer/models.dart';
import 'package:brainmemorizer/services/auth_gateway.dart';
import 'package:brainmemorizer/services/sync_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 가짜 로그인. 계정은 이메일 -> 비밀번호 표로 들고 있고, uid 는 이메일에서 만든다.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.accounts = const {}, AuthUser? initialUser})
    : _user = initialUser;

  final Map<String, String> accounts;
  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => _user;

  /// 구독 즉시 현재 사용자를 내보내고, 그 자리에서 컨트롤러 구독을 걸어
  /// 이후 이벤트를 놓치지 않는다 (async* 로 하면 첫 yield 뒤에야 구독된다).
  @override
  Stream<AuthUser?> get userChanges => Stream.multi((listener) {
    listener.add(_user);
    final sub = _controller.stream.listen(listener.add);
    listener.onCancel = sub.cancel;
  });

  void _set(AuthUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (accounts[email] != password) {
      throw AuthException('이메일 또는 비밀번호가 맞지 않습니다.');
    }
    _set(AuthUser(uid: 'uid-$email', email: email));
  }

  @override
  Future<void> signUp(String email, String password) async {
    if (accounts.containsKey(email)) throw AuthException('이미 가입된 이메일입니다.');
    _set(AuthUser(uid: 'uid-$email', email: email));
  }

  @override
  Future<void> signOut() async => _set(null);
}

class Device {
  Device(this.state, this.sync, this.auth);
  final AppState state;
  final SyncService sync;
  final FakeAuthGateway auth;
}

void main() {
  late FakeFirebaseFirestore firestore;
  var clockMs = DateTime(2026, 1, 1, 9).millisecondsSinceEpoch;
  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(clockMs);
  void tick() => clockMs += 1000;
  const accounts = {'me@test.com': 'secret123'};
  const me = AuthUser(uid: 'uid-me@test.com', email: 'me@test.com');

  setUp(() {
    firestore = FakeFirebaseFirestore();
    clockMs = DateTime(2026, 1, 1, 9).millisecondsSinceEpoch;
  });

  /// 기기마다 다른 로컬 저장소와 로그인 상태를 가진 "기기"를 만든다.
  Future<Device> device({AuthUser? loggedInAs, bool? autoLogin}) async {
    SharedPreferences.setMockInitialValues({
      'brainmemorizer.autoLogin': ?autoLogin,
    });
    final prefs = await SharedPreferences.getInstance();
    final state = await AppState.load(clock: clock);
    final auth = FakeAuthGateway(accounts: accounts, initialUser: loggedInAs);
    final sync = SyncService(
      state: state,
      firestore: firestore,
      prefs: prefs,
      auth: auth,
    );
    await sync.start();
    return Device(state, sync, auth);
  }

  // 가짜 Firestore 가 스냅샷을 돌리는 데 이벤트 루프 몇 바퀴가 걸린다.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<List<String>> remoteCardQuestions() async =>
      (await firestore
              .collection('users')
              .doc(me.uid)
              .collection('cards')
              .get())
          .docs
          .map((d) => d.data()['question'] as String)
          .toList();

  test('nothing is synced while logged out', () async {
    final d = await device();
    await settle();
    expect(d.sync.signedIn, isFalse);
    expect(d.sync.connected, isFalse);
    d.state.addCard(d.state.addCategory('c').id, 'q', 'a');
    await settle();
    expect((await firestore.collectionGroup('cards').get()).docs, isEmpty);
  });

  test('signing in connects and pushes existing local data', () async {
    final d = await device();
    d.state.addCard(d.state.addCategory('c').id, '오프라인에서 만듦', 'a');
    expect(
      await d.sync.signIn('me@test.com', 'secret123'),
      isTrue,
      reason: d.sync.lastError,
    );
    await settle();
    expect(d.sync.signedIn, isTrue);
    expect(d.sync.connected, isTrue);
    expect(d.sync.user?.email, 'me@test.com');
    expect(await remoteCardQuestions(), ['오프라인에서 만듦']);
  });

  test('wrong password reports a message and stays logged out', () async {
    final d = await device();
    expect(await d.sync.signIn('me@test.com', 'nope'), isFalse);
    expect(d.sync.lastError, contains('맞지 않습니다'));
    expect(d.sync.signedIn, isFalse);
  });

  test('sign up creates the account and connects', () async {
    final d = await device();
    expect(
      await d.sync.signUp('new@test.com', 'secret123'),
      isTrue,
      reason: d.sync.lastError,
    );
    await settle();
    expect(d.sync.connected, isTrue);
    expect(await d.sync.signUp('me@test.com', 'x'), isFalse);
  });

  test('auto login keeps the session; turning it off signs out', () async {
    final kept = await device(loggedInAs: me);
    await settle();
    expect(kept.sync.signedIn, isTrue);
    expect(kept.sync.autoLogin, isTrue);

    final dropped = await device(loggedInAs: me, autoLogin: false);
    await settle();
    expect(dropped.sync.signedIn, isFalse);
    expect(dropped.auth.currentUser, isNull);
  });

  test('two devices on the same account share data both ways', () async {
    final a = await device(loggedInAs: me);
    final b = await device(loggedInAs: me);
    await settle();

    final category = a.state.addCategory('수도');
    a.state.addCard(category.id, '프랑스의 수도', '파리');
    await settle();
    expect(b.state.cards.single.question, '프랑스의 수도');

    // B 에서 복습하면 A 의 복습 시점도 바뀐다.
    tick();
    b.state.recordAnswer(
      b.state.cards.single,
      correct: true,
      failedThisSession: false,
    );
    await settle();
    expect(a.state.cards.single.dueAt, b.state.cards.single.dueAt);
    expect(a.state.cards.single.isDue(clock()), isFalse);

    // 원격에서 받은 것은 되돌려 보내지 않는다.
    expect((await remoteCardQuestions()).length, 1);
  });

  test('newest copy wins and stale remote copies are ignored', () async {
    final a = await device(loggedInAs: me);
    final b = await device(loggedInAs: me);
    final category = a.state.addCategory('c');
    a.state.addCard(category.id, 'q', 'a');
    await settle();

    tick();
    b.state.recordAnswer(
      b.state.cards.single,
      correct: false,
      failedThisSession: false,
    );
    await settle();
    tick();
    a.state.recordAnswer(
      a.state.cards.single,
      correct: true,
      failedThisSession: false,
    );
    await settle();
    expect(b.state.cards.single.reviewCount, 2);
    expect(b.state.cards.single.dueAt, a.state.cards.single.dueAt);

    final stale = StudyCard(
      id: a.state.cards.single.id,
      categoryId: category.id,
      question: 'q',
      answer: 'a',
      dueAt: epoch,
      updatedAt: epoch,
    );
    expect(a.state.applyRemoteCard(stale), isFalse);
  });

  test('deleting a category on one device removes it on the other', () async {
    final a = await device(loggedInAs: me);
    final b = await device(loggedInAs: me);
    final category = a.state.addCategory('c');
    a.state.addCard(category.id, 'q1', 'a');
    a.state.addCard(category.id, 'q2', 'a');
    await settle();
    expect(b.state.cards.length, 2);

    a.state.deleteCategory(category.id);
    await settle();
    expect(b.state.categories, isEmpty);
    expect(b.state.cards, isEmpty);
  });

  test('memory factor syncs to the newer value', () async {
    final a = await device(loggedInAs: me);
    final b = await device(loggedInAs: me);
    a.state.addCard(a.state.addCategory('c').id, 'q', 'a');
    await settle();
    tick();
    a.state.recordAnswer(
      a.state.cards.single,
      correct: true,
      failedThisSession: false,
    );
    await settle();
    tick();
    a.state.recordAnswer(
      a.state.cards.single,
      correct: false,
      failedThisSession: false,
    );
    await settle();
    expect(a.state.memoryFactor, isNot(1.0));
    expect(b.state.memoryFactor, a.state.memoryFactor);
  });

  test('signing out stops syncing; signing back in catches up', () async {
    final a = await device(loggedInAs: me);
    final b = await device(loggedInAs: me);
    await settle();
    await b.sync.signOut();
    await settle();
    expect(b.sync.signedIn, isFalse);

    a.state.addCard(a.state.addCategory('c').id, '로그아웃 중 추가', 'a');
    await settle();
    expect(b.state.cards, isEmpty);

    await b.sync.signIn('me@test.com', 'secret123');
    await settle();
    expect(b.state.cards.single.question, '로그아웃 중 추가');
  });

  test('old local data without timestamps loads', () async {
    SharedPreferences.setMockInitialValues({
      'brainmemorizer.data.v1':
          '{"memoryFactor":1.0,"categories":[{"id":"c","name":"옛날"}],'
          '"cards":[{"id":"k","categoryId":"c","question":"q","answer":"a",'
          '"stability":1.0,"reviewCount":0,"lapseCount":0,"lastReviewedAt":null,'
          '"dueAt":"2026-01-01T00:00:00.000"}]}',
    });
    final state = await AppState.load(clock: clock);
    expect(state.cards.single.updatedAt, epoch);
    expect(state.snapshotChanges().whereType<ProfileChanged>(), isEmpty);
  });
}
