// lib/pages/chat_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cativerse/pages/chat_detail_page.dart';
import 'package:cativerse/theme/colors.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final users = FirebaseFirestore.instance.collection('users');
    final rooms = FirebaseFirestore.instance.collection('rooms');

    return Scaffold(
      backgroundColor: white,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: users.doc(currentUid).snapshots(),
        builder: (context, meSnap) {
          final me = meSnap.data?.data() ?? const <String, dynamic>{};
          final activeCatId = (me['activeCatId'] as String?)?.trim();

          final Stream<QuerySnapshot<Map<String, dynamic>>> roomsStream =
              (activeCatId != null && activeCatId.isNotEmpty)
                  ? rooms
                      .where('catIds', arrayContains: activeCatId)
                      .orderBy('updatedAt', descending: true)
                      .snapshots()
                  : rooms
                      .where('userIds', arrayContains: currentUid)
                      .orderBy('updatedAt', descending: true)
                      .snapshots();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: roomsStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    (activeCatId != null && activeCatId.isNotEmpty)
                        ? 'No messages for the selected cat yet'
                        : 'No messages yet',
                  ),
                );
              }

              final items = docs.toList()
                ..sort((a, b) {
                  final ta = (a.data()['updatedAt'] as Timestamp?)
                          ?.toDate() ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  final tb = (b.data()['updatedAt'] as Timestamp?)
                          ?.toDate() ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  return tb.compareTo(ta);
                });

              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final roomDoc = items[i];
                  final data = roomDoc.data();

                  final userIds =
                      List<String>.from(data['userIds'] ?? const <String>[]);
                  final ownerUids =
                      List<String>.from(data['ownerUids'] ?? const <String>[]);
                  final catIds =
                      List<String>.from(data['catIds'] ?? const <String>[]);

                  String otherUid = currentUid;
                  if (userIds.isNotEmpty) {
                    otherUid = userIds.firstWhere(
                      (u) => u != currentUid,
                      orElse: () => currentUid,
                    );
                  } else if (ownerUids.isNotEmpty) {
                    otherUid = ownerUids.firstWhere(
                      (u) => u != currentUid,
                      orElse: () => currentUid,
                    );
                  }

                  String? otherCatId;
                  if (activeCatId != null &&
                      activeCatId.isNotEmpty &&
                      catIds.contains(activeCatId)) {
                    otherCatId = catIds.firstWhere(
                      (x) => x != activeCatId,
                      orElse: () => catIds.isNotEmpty ? catIds.first : '',
                    );
                  } else {
                    otherCatId = catIds.isNotEmpty ? catIds.first : null;
                  }

                  return _RoomTile(
                    roomId: roomDoc.id,
                    otherUid: otherUid,
                    otherCatId: otherCatId,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final String roomId;
  final String otherUid;
  final String? otherCatId;
  const _RoomTile({
    required this.roomId,
    required this.otherUid,
    required this.otherCatId,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    if (otherCatId == null || otherCatId!.isEmpty) {
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: db.collection('users').doc(otherUid).get(),
        builder: (context, usnap) {
          String name = 'Unknown';
          String avatar = '';

          if (usnap.hasData && usnap.data!.exists) {
            final u = usnap.data!.data()!;
            final fn = (u['firstName'] as String?)?.trim() ?? '';
            final ln = (u['lastName'] as String?)?.trim() ?? '';
            final imageUrl = (u['imageUrl'] as String?)?.trim() ?? '';
            final ava = (u['avatar'] as String?)?.trim() ?? '';
            final candidate = ('$fn $ln').trim();
            if (candidate.isNotEmpty) name = candidate;
            avatar = imageUrl.isNotEmpty ? imageUrl : ava;
          }

          return _tile(
            context: context,
            title: name,
            avatarUrl: avatar,
          );
        },
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('cats').doc(otherCatId).snapshots(),
      builder: (context, catSnap) {
        String title = 'Cat';
        String avatar = '';

        if (catSnap.hasData && catSnap.data!.exists) {
          final cat = catSnap.data!.data()!;
          title = (cat['name'] as String?)?.trim() ?? 'Cat';
          final imgs =
              (cat['imageUrls'] as List?)?.cast<String>() ?? const [];
          if (imgs.isNotEmpty) avatar = imgs.first;
        }

        return _tile(
          context: context,
          title: title,
          avatarUrl: avatar,
        );
      },
    );
  }

  Widget _tile({
    required BuildContext context,
    required String title,
    required String avatarUrl,
  }) {
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey.shade300,
        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
        child: avatarUrl.isEmpty
            ? const Icon(Icons.pets, color: Colors.white70)
            : null,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: _LastMessage(roomId: roomId),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            roomId: roomId,
            otherUid: otherUid,
            otherCatId: otherCatId, // ✅ ส่งไปให้หัวแชทใช้
          ),
        ),
      ),
    );
  }
}

class _LastMessage extends StatelessWidget {
  final String roomId;
  const _LastMessage({required this.roomId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rooms')
          .doc(roomId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Text(
            'Start chatting',
            style: TextStyle(color: Colors.grey),
          );
        }
        final m = snap.data!.docs.first.data();
        final text = (m['text'] as String?) ?? '';
        return Text(
          text.isNotEmpty ? text : 'Photo/sticker',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(color: Colors.grey),
        );
      },
    );
  }
}
