import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PairingService {
  PairingService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  Future<String> createPairingCode() async {
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'Parent must be logged in before creating a pairing code.',
      );
    }

    for (int attempt = 0; attempt < 5; attempt++) {
      final code = _generateSixDigitCode();
      final pairingDocument = _firestore.collection('pairingCodes').doc(code);

      final wasCreated = await _firestore.runTransaction<bool>((
          transaction,
          ) async {
        final existingDocument = await transaction.get(pairingDocument);

        if (existingDocument.exists) {
          return false;
        }

        final now = DateTime.now();
        final expiresAt = now.add(const Duration(minutes: 15));

        transaction.set(pairingDocument, {
          'code': code,
          'parentUid': currentUser.uid,
          'parentEmail': currentUser.email,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'pairedChildUid': null,
          'pairingMethod': 'code',
        });

        return true;
      });

      if (wasCreated) {
        return code;
      }
    }

    throw Exception('Unable to generate a unique pairing code. Please try again.');
  }

  String _generateSixDigitCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }
}