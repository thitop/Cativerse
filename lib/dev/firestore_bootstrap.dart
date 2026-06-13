// lib/dev/firestore_bootstrap.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ยูทิลิตีสำหรับเตรียม/ทดสอบโครง Firestore ให้ฟีเจอร์ "แมช & แชท" ทำงานครบ
class FirestoreBootstrap {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static FirebaseAuth get _auth => FirebaseAuth.instance;

  /// ตั้งค่า activeCatId ให้ user ปัจจุบัน
  static Future<void> setActiveCatForMe(String catId,
      {String? catName, String? catPhoto}) async {
    final uid = _auth.currentUser!.uid;
    await _db.collection('users').doc(uid).set({
      'activeCatId': catId,
      if (catName != null) 'activeCatName': catName,
      if (catPhoto != null) 'activeCatAvatar': catPhoto,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// สร้างแมวทดสอบ 1 ตัวให้ user ปัจจุบัน (คืนค่า docId)
  static Future<String> seedMyCat({
    String name = 'Mimi',
    String breed = 'British Shorthair',
    String gender = 'female',
    String? imageUrl,
  }) async {
    final uid = _auth.currentUser!.uid;
    final ref = await _db.collection('cats').add({
      'ownerId': uid,
      'name': name,
      'breed': breed,
      'gender': gender,
      'description': 'Cativerse demo',
      'imageUrl': imageUrl ?? '',
      'imageUrls': imageUrl != null ? [imageUrl] : [],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// สร้างแมวทดสอบของ "ผู้อื่น" 1 ตัว (คืนค่า catId และ ownerUid) — ใช้ทดสอบโดยไม่ต้องล็อกอินบัญชีที่สองจริง
  static Future<(String ownerUid, String catId)> seedOtherUserAndCat({
    required String otherUid,
    String name = 'Kuro',
    String breed = 'Maine Coon',
    String gender = 'male',
    String? imageUrl,
  }) async {
    // ให้มั่นใจว่ามี users/{otherUid} อยู่
    await _db.collection('users').doc(otherUid).set({
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final ref = await _db.collection('cats').add({
      'ownerId': otherUid,
      'name': name,
      'breed': breed,
      'gender': gender,
      'description': 'Demo opponent cat',
      'imageUrl': imageUrl ?? '',
      'imageUrls': imageUrl != null ? [imageUrl] : [],
      'createdAt': FieldValue.serverTimestamp(),
    });

    return (otherUid, ref.id);
  }

  /// สร้าง “ไลก์ไปก่อน” ระดับแมว→แมว (ยังไม่ matched)
  /// ใช้รูปแบบ id: like_{fromCatId}__{toCatId}
  static Future<void> putLike({
    required String fromOwnerUid,
    required String fromCatId,
    required String toOwnerUid,
    required String toCatId,
  }) async {
    final likeId = 'like_${fromCatId}__${toCatId}';
    final now = FieldValue.serverTimestamp();
    await _db.collection('matches').doc(likeId).set({
      'fromOwnerUid': fromOwnerUid,
      'fromCatId': fromCatId,
      'toOwnerUid': toOwnerUid,
      'toCatId': toCatId,
      'matched': false,
      'timestamp': now,
      'updatedAt': now,
    }, SetOptions(merge: true));
  }

  /// ทดสอบ flow ให้แมชสำเร็จ “ทันที” (สร้าง like ไป-กลับ แล้วเปิดห้อง)
  static Future<void> forceInstantMatch({
    required String myCatId,
    required String otherOwnerUid,
    required String otherCatId,
  }) async {
    final myUid = _auth.currentUser!.uid;

    // like ของเรา → คู่แข่ง
    await putLike(
      fromOwnerUid: myUid,
      fromCatId: myCatId,
      toOwnerUid: otherOwnerUid,
      toCatId: otherCatId,
    );

    // like กลับของเขา → เรา
    await putLike(
      fromOwnerUid: otherOwnerUid,
      fromCatId: otherCatId,
      toOwnerUid: myUid,
      toCatId: myCatId,
    );

    // อัปเดต matched ทั้งคู่
    final myLikeId = 'like_${myCatId}__${otherCatId}';
    final backId = 'like_${otherCatId}__${myCatId}';
    final now = FieldValue.serverTimestamp();

    final batch = _db.batch();
    batch.set(_db.collection('matches').doc(myLikeId),
        {'matched': true, 'updatedAt': now}, SetOptions(merge: true));
    batch.set(_db.collection('matches').doc(backId),
        {'matched': true, 'updatedAt': now}, SetOptions(merge: true));
    await batch.commit();

    // สร้าง/อัปเดตห้องแชท rooms/room_{uidA}__{uidB}
    final ids = [myUid, otherOwnerUid]..sort();
    final roomId = 'room_${ids[0]}__${ids[1]}';
    final roomRef = _db.collection('rooms').doc(roomId);

    // เก็บ catIds ของทั้งสอง
    await _db.runTransaction((tx) async {
      final snap = await tx.get(roomRef);
      final currCatIds =
          (snap.data()?['catIds'] as List?)?.cast<String>() ?? const <String>[];
      final nextCatIds = <String>{...currCatIds, myCatId, otherCatId}.toList();

      if (snap.exists) {
        tx.set(
          roomRef,
          {
            'userIds': ids,
            'ownerUids': ids,
            'catIds': nextCatIds,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      } else {
        tx.set(roomRef, {
          'id': roomId,
          'userIds': ids,
          'ownerUids': ids,
          'catIds': nextCatIds,
          'createdAt': now,
          'updatedAt': now,
          'lastMessage': 'เริ่มแชทกันเลย',
        });
      }
    });
  }
}
