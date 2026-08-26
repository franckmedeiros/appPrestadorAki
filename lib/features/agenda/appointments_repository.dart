import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/api_exception.dart';
import 'models/appointment.dart';

/// Repositório de compromissos, direto no Firestore em
/// `providers/{uid}/appointments` (ver firebase/DATA_MODEL.md) — CRUD
/// simples, sem Cloud Function (não tem regra de negócio especial aqui,
/// diferente de Orçamentos).
class AppointmentsRepository {
  AppointmentsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore
      .collection('providers')
      .doc(_auth.currentUser!.uid)
      .collection('appointments');

  Future<List<Appointment>> list({DateTime? from, DateTime? to}) async {
    try {
      Query<Map<String, dynamic>> query = _collection.orderBy('scheduledAt');
      if (from != null) {
        query = query.where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from));
      }
      if (to != null) {
        query = query.where('scheduledAt', isLessThan: Timestamp.fromDate(to));
      }
      final snapshot = await query.get();
      return snapshot.docs.map(Appointment.fromFirestore).toList();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível carregar a agenda.');
    }
  }

  Future<Appointment> create({
    String? customerId,
    String? customerName,
    required AppointmentType type,
    required DateTime scheduledAt,
    int durationMinutes = 60,
    String? addressText,
    String? observations,
  }) async {
    try {
      final now = FieldValue.serverTimestamp();
      final doc = await _collection.add({
        if (customerId != null) 'customerId': customerId,
        if (customerName != null && customerName.isNotEmpty) 'customerName': customerName,
        'type': type.wireValue,
        'scheduledAt': Timestamp.fromDate(scheduledAt),
        'durationMinutes': durationMinutes,
        if (addressText != null && addressText.isNotEmpty) 'addressText': addressText,
        if (observations != null && observations.isNotEmpty) 'observations': observations,
        'status': AppointmentStatus.agendado.wireValue,
        'createdAt': now,
      });
      final snapshot = await doc.get();
      return Appointment.fromFirestore(snapshot);
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível salvar o compromisso.');
    }
  }

  Future<void> delete(String id) async {
    try {
      await _collection.doc(id).delete();
    } on FirebaseException catch (e) {
      throw ApiException(0, e.message ?? 'Não foi possível excluir o compromisso.');
    }
  }
}
