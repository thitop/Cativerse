// lib/data/breed_and_vaccines.dart
// ===== Helper: parse JSON + batch upload to Firestore lookups =====

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

/// JSON schema ที่คาดหวังจากไฟล์ที่อัปโหลด:
/// {
///   "breeds": [
///     {"id":"abys", "name_th":"อะบิสซิเนียน", "name_en":"Abyssinian"},
///     {"id":"bsho", "name_th":"บริติชชอร์ตแฮร์", "name_en":"British Shorthair"}
///   ],
///   "vaccines": [
///     {"code":"FVRCP", "name":"FVRCP (ไข้หวัดแมวรวม)", "desc":"เข็มพื้นฐาน"},
///     {"code":"RABIES", "name":"พิษสุนัขบ้า", "desc":"ตามกฎหมาย"}
///   ]
/// }

class CatBreed {
  final String id;
  final String nameTh;
  final String nameEn;

  CatBreed({required this.id, required this.nameTh, required this.nameEn});

  factory CatBreed.fromMap(Map<String, dynamic> m) => CatBreed(
        id: (m['id'] ?? '').toString().trim(),
        nameTh: (m['name_th'] ?? m['nameTh'] ?? '').toString().trim(),
        nameEn: (m['name_en'] ?? m['nameEn'] ?? '').toString().trim(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name_th': nameTh,
        'name_en': nameEn,
      };
}

class VaccineType {
  final String code;
  final String name;
  final String desc;

  VaccineType({required this.code, required this.name, this.desc = ''});

  factory VaccineType.fromMap(Map<String, dynamic> m) => VaccineType(
        code: (m['code'] ?? '').toString().trim(),
        name: (m['name'] ?? '').toString().trim(),
        desc: (m['desc'] ?? m['description'] ?? '').toString().trim(),
      );

  Map<String, dynamic> toMap() => {
        'code': code,
        'name': name,
        'desc': desc,
      };
}

class BreedVaccineBundle {
  final List<CatBreed> breeds;
  final List<VaccineType> vaccines;

  BreedVaccineBundle({required this.breeds, required this.vaccines});

  factory BreedVaccineBundle.fromJsonStr(String jsonStr) {
    final root = json.decode(jsonStr) as Map<String, dynamic>;
    final breeds = ((root['breeds'] ?? []) as List)
        .map((e) => CatBreed.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    final vaccines = ((root['vaccines'] ?? []) as List)
        .map((e) => VaccineType.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    return BreedVaccineBundle(breeds: breeds, vaccines: vaccines);
  }

  static Future<BreedVaccineBundle> fromFile(File f) async {
    final text = await f.readAsString();
    return BreedVaccineBundle.fromJsonStr(text);
  }
}

/// อัปโหลดขึ้น Firestore:
/// - lookups/catBreeds (subcollection 'items' แบบ doc id = breed.id)
/// - lookups/vaccineTypes (subcollection 'items' แบบ doc id = vaccine.code)
class LookupUploader {
  static final _db = FirebaseFirestore.instance;

  static Future<void> uploadBreeds(List<CatBreed> breeds) async {
    final root = _db.collection('lookups').doc('catBreeds');
    final items = root.collection('items');
    final batch = _db.batch();

    // สร้าง doc แม่ไว้เก็บ meta เฉยๆ (ถ้ายังไม่มี)
    batch.set(root, {'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

    for (final b in breeds) {
      if (b.id.isEmpty) continue;
      batch.set(items.doc(b.id), b.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  static Future<void> uploadVaccines(List<VaccineType> vaccines) async {
    final root = _db.collection('lookups').doc('vaccineTypes');
    final items = root.collection('items');
    final batch = _db.batch();

    batch.set(root, {'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

    for (final v in vaccines) {
      if (v.code.isEmpty) continue;
      batch.set(items.doc(v.code), v.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  static Future<void> uploadBundle(BreedVaccineBundle bundle) async {
    await uploadBreeds(bundle.breeds);
    await uploadVaccines(bundle.vaccines);
  }
}

/// ตัวช่วยอ่าน (เช็คมีค่า ถ้าไม่มีให้ fallback เป็น [])
Future<List<CatBreed>> fetchBreeds() async {
  final snap = await FirebaseFirestore.instance
      .collection('lookups')
      .doc('catBreeds')
      .collection('items')
      .orderBy('name_th')
      .get();
  return snap.docs
      .map((d) => CatBreed.fromMap(d.data()))
      .toList();
}

Future<List<VaccineType>> fetchVaccineTypes() async {
  final snap = await FirebaseFirestore.instance
      .collection('lookups')
      .doc('vaccineTypes')
      .collection('items')
      .orderBy('name')
      .get();
  return snap.docs
      .map((d) => VaccineType.fromMap(d.data()))
      .toList();
}
