// lib/models/cat_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// ===================
/// Cat (โปรไฟล์แมว)
/// ===================
class Cat {
  final String id;
  final String ownerId;
  final String name;
  final String breed;
  final String gender;            // 'male' | 'female'
  final DateTime? birthdate;      // วันเกิด (อ่านได้ทั้ง 'birthdate' และ 'birthday')
  final String description;
  final List<String> imageUrls;

  /// พิกัดเจ้าของแมว (ใช้คู่กับ GPS ใน Explore)
  final double? ownerLat;
  final double? ownerLng;

  Cat({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.breed,
    required this.gender,
    required this.birthdate,
    required this.description,
    required this.imageUrls,
    this.ownerLat,
    this.ownerLng,
  });

  /// อ่านจาก Firestore Document
  factory Cat.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() ?? {}) as Map<String, dynamic>;

    // รองรับทั้ง birthdate และ birthday
    final ts = (d['birthdate'] ?? d['birthday']);
    final DateTime? birth =
        ts is Timestamp ? ts.toDate() : (ts is DateTime ? ts : null);

    // พิกัด (บางตัวอาจไม่มี => null)
    final double? lat = (d['ownerLat'] as num?)?.toDouble();
    final double? lng = (d['ownerLng'] as num?)?.toDouble();

    return Cat(
      id: doc.id,
      ownerId: (d['ownerId'] as String?) ?? '',
      name: (d['name'] as String?) ?? '',
      breed: (d['breed'] as String?) ?? 'Other',
      gender: (d['gender'] as String?) ?? 'unknown',
      birthdate: birth,
      description: (d['description'] as String?) ?? '',
      imageUrls: (d['imageUrls'] as List?)?.cast<String>() ?? const [],
      ownerLat: lat,
      ownerLng: lng,
    );
  }

  /// เขียนกลับเป็น Map สำหรับ Firestore
  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'name': name,
        'breed': breed,
        'gender': gender,
        'birthdate': birthdate != null ? Timestamp.fromDate(birthdate!) : null,
        'description': description,
        'imageUrls': imageUrls,
        'ownerLat': ownerLat,
        'ownerLng': ownerLng,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// ข้อความอายุพร้อมใช้ใน UI
  String get ageText => ageLabel(birthdate);
}

/// ===================
/// Records (หลายครั้ง)
/// ===================

class VaccineRecord {
  final String id;
  final DateTime date;
  final String type;
  final String? notes;

  VaccineRecord({
    required this.id,
    required this.date,
    required this.type,
    this.notes,
  });

  factory VaccineRecord.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() ?? {}) as Map<String, dynamic>;
    return VaccineRecord(
      id: doc.id,
      date: (d['date'] as Timestamp).toDate(),
      type: (d['type'] as String?) ?? '',
      notes: d['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'type': type,
        'notes': notes,
      };
}

class IllnessRecord {
  final String id;
  final DateTime date;
  final String diagnosis;
  final String? treatment;
  final String? notes;

  IllnessRecord({
    required this.id,
    required this.date,
    required this.diagnosis,
    this.treatment,
    this.notes,
  });

  factory IllnessRecord.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() ?? {}) as Map<String, dynamic>;
    return IllnessRecord(
      id: doc.id,
      date: (d['date'] as Timestamp).toDate(),
      diagnosis: (d['diagnosis'] as String?) ?? '',
      treatment: d['treatment'] as String?,
      notes: d['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'diagnosis': diagnosis,
        'treatment': treatment,
        'notes': notes,
      };
}

class CheckupRecord {
  final String id;
  final DateTime date;
  final String? clinic;
  final double? weightKg;
  final String? notes;

  CheckupRecord({
    required this.id,
    required this.date,
    this.clinic,
    this.weightKg,
    this.notes,
  });

  factory CheckupRecord.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() ?? {}) as Map<String, dynamic>;
    return CheckupRecord(
      id: doc.id,
      date: (d['date'] as Timestamp).toDate(),
      clinic: d['clinic'] as String?,
      weightKg: (d['weightKg'] as num?)?.toDouble(),
      notes: d['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'clinic': clinic,
        'weightKg': weightKg,
        'notes': notes,
      };
}

class BirthRecord {
  final String id;
  final DateTime date;
  final int kittens;
  final String? notes;

  BirthRecord({
    required this.id,
    required this.date,
    required this.kittens,
    this.notes,
  });

  factory BirthRecord.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() ?? {}) as Map<String, dynamic>;
    return BirthRecord(
      id: doc.id,
      date: (d['date'] as Timestamp).toDate(),
      kittens: (d['kittens'] as int?) ?? 0,
      notes: d['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        'kittens': kittens,
        'notes': notes,
      };
}

/// ===================
/// Helpers
/// ===================

/// แปลงวันเกิดเป็นข้อความอายุ เช่น "1y 2m" หรือ "5m"
String ageLabel(DateTime? birth) {
  if (birth == null) return '—';

  final now = DateTime.now();
  if (birth.isAfter(now)) return '—'; // กันข้อมูลผิด

  int y = now.year - birth.year;
  int m = now.month - birth.month;
  int d = now.day - birth.day;

  if (d < 0) m -= 1; // ยืมวัน
  if (m < 0) {
    y -= 1;
    m += 12;
  }

  if (y > 0) return '${y}y ${m}m';
  return '${m}m';
}
