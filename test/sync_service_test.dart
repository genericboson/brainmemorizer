import 'package:brainmemorizer/app_state.dart';
import 'package:brainmemorizer/models.dart';
import 'package:brainmemorizer/services/sync_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 두 "기기": 각자 AppState 를 갖고 같은 (가짜) Firestore 를 본다.
class Device {
  Device(this.state, this.sync);
  final AppState state;
  final SyncService sync;
}

void main() {
  late FakeFirebaseFirestore firestore;
  var clockMs = DateTime(2026, 1, 1, 9).millisecondsSinceEpoch;
  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(clockMs);
  void tick() => clockMs += 1000;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    clockMs = DateTime(2026, 1, 1, 9).millisecondsSinceEpoch;
  });

  Future<Device> device({String? key}) async {
    // 기기마다 다른 로컬 저장소.
    SharedPreferences.setMockInitialValues({'brainmemorizer.syncKey': ?key});
    final prefs = await SharedPreferences.getInstance();
    final state = await AppState.load(clock: clock);
    final sync = SyncService(state: state, firestore: firestore, prefs: prefs);
    await sync.start();
    return Device(state, sync);
  }

  // 가짜 Firestore 가 스냅샷을 돌리는 데 이벤트 루프 몇 바퀴가 걸린다.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('generates and stores a well-formed key', () async {
    final d = await device();
    expect(SyncService.normalizeKey(d.sync.syncKey), d.sync.syncKey);
    expect(d.sync.syncKey, matches(r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$'));
    expect(d.sync.connected, isTrue);
  });

  test('normalizeKey accepts sloppy input and rejects bad input', () {
    expect(SyncService.normalizeKey(' abcd efgh-jklm '), 'ABCD-EFGH-JKLM');
    expect(SyncService.normalizeKey('ABCD-EFGH-JKL'), isNull);
    expect(SyncService.normalizeKey('ABCD-EFGH-JKL0'), isNull); // 0 은 안 쓴다
  });

  test('local changes are pushed to Firestore', () async {
    final d = await device(key: 'AAAA-AAAA-AAAA');
    final category = d.state.addCategory('수도');
    d.state.addCard(category.id, 'q', 'a', grade: 3);
    await settle();

    final space = firestore.collection('spaces').doc('AAAA-AAAA-AAAA');
    final cat = await space.collection('categories').doc(category.id).get();
    expect(cat.data()!['name'], '수도');
    final cards = await space.collection('cards').get();
    expect(cards.docs.single.data()['grade'], 3);
  });

  test('a second device with the same key receives the data', () async {
    final a = await device(key: 'AAAA-AAAA-AAAA');
    final category = a.state.addCategory('수도');
    a.state.addCard(category.id, '프랑스의 수도', '파리');
    await settle();

    final b = await device(key: 'AAAA-AAAA-AAAA');
    await settle();
    expect(b.state.categories.single.name, '수도');
    expect(b.state.cards.single.question, '프랑스의 수도');
    // 원격에서 받은 것은 다시 밀어 보내지 않는다 (문서 수 그대로).
    final cards = await firestore
        .collection('spaces')
        .doc('AAAA-AAAA-AAAA')
        .collection('cards')
        .get();
    expect(cards.docs.length, 1);
  });

  test('review on one device updates due time on the other', () async {
    final a = await device(key: 'AAAA-AAAA-AAAA');
    final category = a.state.addCategory('c');
    a.state.addCard(category.id, 'q', 'a');
    await settle();
    final b = await device(key: 'AAAA-AAAA-AAAA');
    await settle();

    tick();
    final cardOnB = b.state.cards.single;
    b.state.recordAnswer(cardOnB, correct: true, failedThisSession: false);
    await settle();

    final cardOnA = a.state.cards.single;
    expect(cardOnA.dueAt, cardOnB.dueAt);
    expect(cardOnA.reviewCount, 1);
    expect(cardOnA.isDue(clock()), isFalse);
  });

  test('newer copy wins regardless of direction', () async {
    final a = await device(key: 'AAAA-AAAA-AAAA');
    final category = a.state.addCategory('c');
    a.state.addCard(category.id, 'q', 'a');
    await settle();
    final b = await device(key: 'AAAA-AAAA-AAAA');
    await settle();

    // B 가 먼저 복습(t+1), A 가 나중에 복습(t+2): A 의 결과가 남아야 한다.
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

    expect(a.state.cards.single.reviewCount, 2);
    expect(b.state.cards.single.reviewCount, 2);
    expect(b.state.cards.single.dueAt, a.state.cards.single.dueAt);

    // 오래된 원격 사본은 무시된다.
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

  test(
    'deleting a category on one device removes it and its cards on the other',
    () async {
      final a = await device(key: 'AAAA-AAAA-AAAA');
      final category = a.state.addCategory('c');
      a.state.addCard(category.id, 'q1', 'a');
      a.state.addCard(category.id, 'q2', 'a');
      await settle();
      final b = await device(key: 'AAAA-AAAA-AAAA');
      await settle();
      expect(b.state.cards.length, 2);

      a.state.deleteCategory(category.id);
      await settle();
      expect(b.state.categories, isEmpty);
      expect(b.state.cards, isEmpty);
    },
  );

  test('memory factor syncs to the newer value', () async {
    final a = await device(key: 'AAAA-AAAA-AAAA');
    final category = a.state.addCategory('c');
    a.state.addCard(category.id, 'q', 'a');
    final b = await device(key: 'AAAA-AAAA-AAAA');
    await settle();

    // 두 번째 복습부터 배율이 움직인다.
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

  test('useKey joins another device and merges both sides', () async {
    final a = await device(key: 'AAAA-AAAA-AAAA');
    a.state.addCard(a.state.addCategory('A쪽').id, 'qa', 'a');
    final b = await device(key: 'BBBB-BBBB-BBBB');
    b.state.addCard(b.state.addCategory('B쪽').id, 'qb', 'b');
    await settle();

    await b.sync.useKey('AAAA-AAAA-AAAA');
    await settle();

    expect(b.sync.syncKey, 'AAAA-AAAA-AAAA');
    expect(b.state.categories.map((c) => c.name), containsAll(['A쪽', 'B쪽']));
    expect(a.state.categories.map((c) => c.name), containsAll(['A쪽', 'B쪽']));
    expect(a.state.cards.length, 2);
  });

  test('keeps retrying sign-in until it succeeds, then syncs', () async {
    SharedPreferences.setMockInitialValues({
      'brainmemorizer.syncKey': 'AAAA-AAAA-AAAA',
    });
    final prefs = await SharedPreferences.getInstance();
    final state = await AppState.load(clock: clock);
    var attempts = 0;
    final sync = SyncService(
      state: state,
      firestore: firestore,
      prefs: prefs,
      initialRetry: const Duration(milliseconds: 10),
      signIn: () async {
        if (++attempts < 3) throw Exception('network-request-failed');
      },
    );
    await sync.start();
    expect(sync.connected, isFalse);
    expect(sync.lastError, contains('network-request-failed'));

    // 연결 전 변경은 재연결 때 전체 푸시로 따라간다.
    state.addCategory('오프라인에서 만듦');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(attempts, 3);
    expect(sync.connected, isTrue);
    final docs = await firestore
        .collection('spaces')
        .doc('AAAA-AAAA-AAAA')
        .collection('categories')
        .get();
    expect(docs.docs.single.data()['name'], '오프라인에서 만듦');
    sync.dispose();
  });

  test('old local data without timestamps loads and syncs', () async {
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
