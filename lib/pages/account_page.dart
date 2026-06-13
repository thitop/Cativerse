// lib/pages/account_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_custom_clippers/flutter_custom_clippers.dart';

import 'package:cativerse/pages/setting_page.dart';
import 'package:cativerse/pages/formscreen.dart';
import 'package:cativerse/pages/cat_health_page.dart';
import 'package:cativerse/pages/cat_edit_and_match_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  /// Open health page for this user (choose cat if there are many)
  Future<void> _openHealthForUser(BuildContext context, String uid) async {
    final db = FirebaseFirestore.instance;

    QuerySnapshot<Map<String, dynamic>> q =
        await db.collection('cats').where('ownerId', isEqualTo: uid).get();

    if (q.docs.isEmpty) {
      q = await db.collection('cats').where('userId', isEqualTo: uid).get();
    }

    if (q.docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No cat profiles yet — please add a cat first.',
          ),
        ),
      );
      return;
    }

    if (q.docs.length == 1) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CatHealthPage(catId: q.docs.first.id)),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          itemCount: q.docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final d = q.docs[i];
            final data = d.data();
            final name = (data['name'] ?? '').toString();
            final breed = (data['breed'] ?? '').toString();
            final avatar = (data['imageUrl'] ?? data['avatar'] ?? '').toString();
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: avatar.isNotEmpty
                    ? NetworkImage(avatar)
                    : const AssetImage('assets/images/cat_placeholder.png')
                        as ImageProvider,
              ),
              title: Text(name.isEmpty ? 'My cat' : name),
              subtitle: breed.isEmpty ? null : Text(breed),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CatHealthPage(catId: d.id)),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final soft = cs.onSurfaceVariant;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: cs.surfaceVariant.withOpacity(0.2),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final uid = user.uid;
    final docStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: docStream,
      builder: (context, snap) {
        String avatarUrl = user.photoURL ?? '';
        String username = '';
        String displayName = user.displayName ?? (user.email ?? 'User');

        String activeCatId = '';
        String activeCatName = '';
        String activeCatAvatar = '';

        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          final img = (data['imageUrl'] as String?)?.trim() ?? '';
          final ava = (data['avatar'] as String?)?.trim() ?? '';
          avatarUrl = img.isNotEmpty ? img : (ava.isNotEmpty ? ava : avatarUrl);
          username = (data['username'] as String?)?.trim() ?? '';
          final fn = (data['firstName'] as String?)?.trim() ?? '';
          final ln = (data['lastName'] as String?)?.trim() ?? '';
          final full = ('$fn $ln').trim();
          if (full.isNotEmpty) displayName = full;

          activeCatId = (data['activeCatId'] as String?)?.trim() ?? '';
          activeCatName = (data['activeCatName'] as String?)?.trim() ?? '';
          activeCatAvatar = (data['activeCatAvatar'] as String?)?.trim() ?? '';
        }

        final size = MediaQuery.of(context).size;

        return Scaffold(
          backgroundColor: cs.surfaceVariant.withOpacity(0.2),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ===== Header (curved) =====
              ClipPath(
                clipper: OvalBottomBorderClipper(),
                child: Container(
                  width: size.width,
                  height: size.height * 0.6,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        spreadRadius: 10,
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.only(left: 30, right: 30, bottom: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Avatar
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            image: DecorationImage(
                              image: avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : const AssetImage(
                                          'assets/images/default_avatar.png')
                                      as ImageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),

                        // Display Name
                        Text(
                          displayName,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),

                        // Username / Email
                        Text(
                          username.isNotEmpty ? '@$username' : (user.email ?? ''),
                          style: TextStyle(
                            fontSize: 14,
                            color: soft.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ===== 3 action buttons row =====
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // SETTINGS — purple/pink
                            _CircleAction(
                              size: 60,
                              label: "SETTING",
                              icon: Icons.settings_rounded,
                              gradient: const [
                                Color(0xFFA18CD1),
                                Color(0xFFFBC2EB),
                              ],
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingPage(),
                                ),
                              ),
                            ),

                            // ADD YOUR PETS — pink/orange
                            _CircleAction(
                              size: 80,
                              label: "ADD YOUR PETS",
                              icon: Icons.pets_rounded,
                              gradient: const [
                                Color(0xFFFF5F8F),
                                Color(0xFFFF7E5F),
                              ],
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AddCatForm(),
                                  ),
                                );
                              },
                            ),

                            // MY CAT — green/cyan
                            _CircleAction(
                              size: 60,
                              label: "MY CAT",
                              icon: Icons.edit_rounded,
                              gradient: const [
                                Color(0xFF43E97B),
                                Color(0xFF38F9D7),
                              ],
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const CatEditAndMatchPage(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // HEALTH — blue
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CircleAction(
                              size: 60,
                              label: "HEALTH",
                              icon: Icons.health_and_safety_rounded,
                              gradient: const [
                                Color(0xFF36D1DC),
                                Color(0xFF5B86E5),
                              ],
                              onTap: () => _openHealthForUser(context, uid),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ===== Card: current active cat for matching =====
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: activeCatAvatar.isNotEmpty
                          ? NetworkImage(activeCatAvatar)
                          : null,
                      child: activeCatAvatar.isEmpty
                          ? const Icon(Icons.pets)
                          : null,
                    ),
                    title: const Text('Current active cat for matching'),
                    subtitle: Text(
                      activeCatId.isEmpty
                          ? 'Not set yet (tap to choose)'
                          : (activeCatName.isNotEmpty
                              ? activeCatName
                              : activeCatId),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CatEditAndMatchPage(),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// Circle gradient action button
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 60,
    this.gradient,
    this.solidColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final List<Color>? gradient; // use if you want gradient
  final Color? solidColor; // or a solid color

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelColor = cs.onSurfaceVariant.withOpacity(.8);

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gradient == null ? (solidColor ?? cs.primary) : null,
              gradient:
                  gradient != null ? LinearGradient(colors: gradient!) : null,
              boxShadow: [
                BoxShadow(
                  color:
                      (gradient?.last ?? (solidColor ?? cs.primary)).withOpacity(.28),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: size * 0.55, color: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ).copyWith(color: labelColor),
        ),
      ],
    );
  }
}
