// lib/data/health_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class HealthRepo {
  static final _db = FirebaseFirestore.instance;

  // ====== READ: เอกสารล่าสุดในคอลเลคชันย่อย ======
  static Stream<Map<String, dynamic>?> latestRecordStream(String subPath) {
    return _db
        .collection(subPath)
        .orderBy('date', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : snap.docs.first.data());
  }

  // ====== WRITE: เพิ่มรายการในหมวดต่างๆ ======
  static Future<void> addVaccine(String catId, Map<String, dynamic> data) {
    return _db.collection('cats/$catId/vaccineRecords').add(data);
  }

  static Future<void> addIllness(String catId, Map<String, dynamic> data) {
    return _db.collection('cats/$catId/illnessRecords').add(data);
  }

  static Future<void> addCheckup(String catId, Map<String, dynamic> data) {
    return _db.collection('cats/$catId/checkupRecords').add(data);
  }

  // ⭐ ใหม่: ประวัติ "การรักษา"
  static Future<void> addTreatment(String catId, Map<String, dynamic> data) {
    return _db.collection('cats/$catId/treatmentRecords').add(data);
  }

  static Future<void> addDeworm(String catId, Map<String, dynamic> data) {
    return _db.collection('cats/$catId/dewormingRecords').add(data);
  }
}

