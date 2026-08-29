import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/budget.dart';

/// Repositório do módulo formal de Orçamentos, direto no Firestore em
/// `providers/{uid}/budgets` — mesmo padrão de CustomersRepository/
/// AppointmentsRepository (CRUD simples, sem Cloud Function, isolamento
/// entre prestadores garantido pelo firestore.rules).
class BudgetsRepository {
  BudgetsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore
      .collection('providers')
      .doc(_auth.currentUser!.uid)
      .collection('budgets');

  /// Ao vivo, mais recente primeiro — mesma razão de
  /// AppointmentsRepository.watchRange: evita "salvei e não apareceu".
  Stream<List<Budget>> watchAll() {
    return _collection
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Budget.fromFirestore).toList());
  }

  Future<Budget> create(Budget budget) async {
    try {
      final now = FieldValue.serverTimestamp();
      final doc = await _collection.add({
        ...budget.toMap(),
        'createdAt': now,
        'updatedAt': now,
      });
      final snapshot = await doc.get();
      return Budget.fromFirestore(snapshot);
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível salvar o orçamento.');
    }
  }

  Future<void> update(Budget budget) async {
    try {
      await _collection.doc(budget.id).set({
        ...budget.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível atualizar o orçamento.');
    }
  }

  Future<void> delete(String id) async {
    try {
      await _collection.doc(id).delete();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível excluir o orçamento.');
    }
  }
}
