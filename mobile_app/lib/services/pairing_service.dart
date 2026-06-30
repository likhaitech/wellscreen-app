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

  Future<void> connectChildWithPairingCode({
    required String code,
  }) async {
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      throw FirebaseAuthException(
        code: 'not-logged-in',
        message: 'Child must be logged in before connecting to a parent.',
      );
    }

    final cleanedCode = code.trim();

    if (cleanedCode.length != 6) {
      throw Exception('Please enter a valid 6-digit pairing code.');
    }

    final pairingDocument =
    _firestore.collection('pairingCodes').doc(cleanedCode);
    final childDocument = _firestore.collection('users').doc(currentUser.uid);

    await _firestore.runTransaction((transaction) async {
      final pairingSnapshot = await transaction.get(pairingDocument);

      if (!pairingSnapshot.exists) {
        throw Exception('Pairing code was not found.');
      }

      final pairingData = pairingSnapshot.data();

      if (pairingData == null) {
        throw Exception('Pairing code data is missing.');
      }

      final status = pairingData['status'] as String?;
      final parentUid = pairingData['parentUid'] as String?;
      final expiresAt = pairingData['expiresAt'];

      if (status != 'active') {
        throw Exception('This pairing code is no longer active.');
      }

      if (parentUid == null || parentUid.isEmpty) {
        throw Exception('Parent account was not found for this pairing code.');
      }

      if (parentUid == currentUser.uid) {
        throw Exception('A child account cannot pair with the same account.');
      }

      if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
        transaction.update(pairingDocument, {
          'status': 'expired',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        throw Exception('This pairing code has expired.');
      }

      final parentDocument = _firestore.collection('users').doc(parentUid);
      final parentSnapshot = await transaction.get(parentDocument);

      if (!parentSnapshot.exists) {
        throw Exception('Parent profile was not found.');
      }

      transaction.update(pairingDocument, {
        'status': 'paired',
        'pairedChildUid': currentUser.uid,
        'pairedChildEmail': currentUser.email,
        'pairedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(
        childDocument,
        {
          'parentUid': parentUid,
          'pairingCodeUsed': cleanedCode,
          'pairedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      transaction.set(
        parentDocument,
        {
          'pairedChildUids': FieldValue.arrayUnion([currentUser.uid]),
          'pairedDeviceIds': FieldValue.arrayUnion([currentUser.uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  String _generateSixDigitCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }
}