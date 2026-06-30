import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  Future<UserCredential> registerUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }
  ) async {
    UserCredential? userCredential;

    try {
      userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-user',
          message: 'Account created, but user data was not returned.',
        );
      }

      final userDocument = _firestore.collection('users').doc(user.uid);

      await _firestore.runTransaction((transaction) async {
        final existingDocument = await transaction.get(userDocument);

        if (existingDocument.exists) {
          throw Exception('User profile already exists.');
        }

        transaction.set(userDocument, {
          'uid': user.uid,
          'fullName': fullName,
          'email': email,
          'role': role.toLowerCase(),
          'accountStatus': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'pairedDeviceIds': <String>[],
          'privacyBoundary': {
            'doesNotMonitorMessages': true,
            'doesNotMonitorSmsContent': true,
            'doesNotMonitorCalls': true,
            'doesNotCollectPasswords': true,
            'doesNotAccessPhotosVideosOrSensitiveFiles': true,
          },
        });
      });

      return userCredential;
    } catch (_) {
      if (userCredential?.user != null) {
        try {
          await userCredential!.user!.delete();
        } catch (_) {
          // Ignore cleanup error.
        }
      }

      rethrow;
    }
  }
  Future<UserCredential> loginUser({
    required String email,
    required String password,
  }) async {
    return _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}