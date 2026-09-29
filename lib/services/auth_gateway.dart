import 'package:firebase_auth/firebase_auth.dart';

class AuthUser {
  const AuthUser({required this.uid, required this.email});

  final String uid;
  final String email;
}

/// 사용자에게 보여 줄 수 있는 메시지를 가진 로그인 오류.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 로그인 상태. 동기화는 로그인한 사용자 id 아래에 데이터를 둔다.
abstract class AuthGateway {
  /// 구독하면 현재 상태를 먼저 내보내고, 이후 바뀔 때마다 내보낸다.
  Stream<AuthUser?> get userChanges;

  AuthUser? get currentUser;

  Future<void> signIn(String email, String password);

  Future<void> signUp(String email, String password);

  Future<void> signOut();
}

class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway(this._auth);

  final FirebaseAuth _auth;

  static AuthUser? _toUser(User? user) => (user == null || user.email == null)
      ? null
      : AuthUser(uid: user.uid, email: user.email!);

  @override
  Stream<AuthUser?> get userChanges => _auth.authStateChanges().map(_toUser);

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Future<void> signIn(String email, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> signUp(String email, String password) => _guard(
    () =>
        _auth.createUserWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> signOut() => _auth.signOut();

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  static String _message(FirebaseAuthException e) => switch (e.code) {
    'invalid-email' => '이메일 주소 형식이 올바르지 않습니다.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => '이메일 또는 비밀번호가 맞지 않습니다.',
    'email-already-in-use' => '이미 가입된 이메일입니다. 로그인해 주세요.',
    'weak-password' => '비밀번호는 6자 이상이어야 합니다.',
    'too-many-requests' => '시도가 너무 많습니다. 잠시 뒤 다시 해 주세요.',
    'network-request-failed' => '네트워크에 연결할 수 없습니다.',
    'user-disabled' => '사용이 중지된 계정입니다.',
    _ => '로그인에 실패했습니다 (${e.code}).',
  };
}
