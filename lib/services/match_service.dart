// lib/services/match_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MatchService {
  static final _db = FirebaseFirestore.instance;

  /// เรียกเมื่อพบว่าไลก์สวนทางกันแล้ว
  static Future<void> finalizeMatch(String uidA, String uidB) async {
    // บังคับ roomId เดียวกันเสมอด้วยการ sort
    final roomId = (uidA.compareTo(uidB) < 0) ? '${uidA}__${uidB}' : '${uidB}__${uidA}';
    final batch = _db.batch();

    // 1) เปลี่ยนทั้งสอง matches -> matched:true
    final idAB = '${uidA}__${uidB}';
    final idBA = '${uidB}__${uidA}';
    batch.set(
      _db.collection('matches').doc(idAB),
      {'matched': true, 'matchedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection('matches').doc(idBA),
      {'matched': true, 'matchedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    // 2) ดึง activeCat ของทั้งสองฝั่ง เพื่อติดให้ที่ room.catIds
    final userA = await _db.collection('users').doc(uidA).get();
    final userB = await _db.collection('users').doc(uidB).get();
    final catA = (userA.data() ?? {})['activeCatId'];
    final catB = (userB.data() ?? {})['activeCatId'];

    // 3) สร้าง/อัปเดต room
    final roomRef = _db.collection('rooms').doc(roomId);
    batch.set(
      roomRef,
      {
        'userIds': [uidA, uidB],
        // เผื่อโค้ดรุ่นเก่าที่อ่าน ownerUids/catIds
        'ownerUids': [uidA, uidB],
        'catIds': [
          if (catA != null && (catA as String).isNotEmpty) catA,
          if (catB != null && (catB as String).isNotEmpty) catB,
        ],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// ใช้ตอนเรากดไลก์: บันทึกไลก์ + ถ้ามีไลก์ย้อนกลับอยู่แล้ว ให้ finalizeMatch
  static Future<void> likeAndMaybeMatch(String me, String otherUid) async {
    final myDoc = _db.collection('matches').doc('${me}__${otherUid}');
    await myDoc.set({
      'userId': me,
      'likedUserId': otherUid,
      'matched': false,
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final back = await _db.collection('matches').doc('${otherUid}__${me}').get();
    if (back.exists) {
      await finalizeMatch(me, otherUid);
    }
  }
}
