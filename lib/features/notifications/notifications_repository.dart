import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/app_notification.dart';

/// Central de notificações do usuário logado (sininho — ver
/// NotificationBell/NotificationsScreen), salva em
/// `clients/{uid}/notifications` — ver DATA_MODEL.md e firestore.rules.
/// As notificações em si são criadas pelas Cloud Functions (ver
/// functions/src/notifications.ts), junto com o push; este repositório só
/// lê, marca como lida e apaga.
class NotificationsRepository {
  NotificationsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore
      .collection('clients')
      .doc(_auth.currentUser!.uid)
      .collection('notifications');

  /// As últimas notificações, mais recentes primeiro. Limita a 50 pra não
  /// carregar um histórico infinito na central.
  Stream<List<AppNotification>> watchAll() {
    return _collection
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AppNotification.fromFirestore).toList());
  }

  /// Contagem de não lidas, pro badge do sininho — só pede a contagem
  /// (mais barato que baixar os documentos inteiros toda vez).
  Stream<int> watchUnreadCount() {
    return _collection.where('read', isEqualTo: false).snapshots().map((snapshot) => snapshot.size);
  }

  Future<void> markAsRead(String id) => _collection.doc(id).update({'read': true});

  /// Marca todas de uma vez (botão "marcar tudo como lida").
  Future<void> markAllAsRead() async {
    final snapshot = await _collection.where('read', isEqualTo: false).get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _collection.doc(id).delete();
}
