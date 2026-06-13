// lib/pages/explore_page.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swipable_stack/swipable_stack.dart';

import '../models/cat_models.dart'; // Cat, ageLabel
import 'cat_detail_page.dart';

/// Breed structure (same as add-cat page)
class _BreedOption {
  final String id; // e.g. "beng"
  final String nameEn; // e.g. "Bengal"
  final String nameTh; // e.g. "เบงกอล"
  const _BreedOption(this.id, this.nameEn, this.nameTh);

  String get label => nameTh.isNotEmpty ? '$nameEn ($nameTh)' : nameEn;
}

/// Filter options for Explore page
class CatFilterOptions {
  final String? gender; // 'male' | 'female' | null = no filter
  final int? minAgeYears;
  final int? maxAgeYears;

  /// Breed (store English name same as cat.breed field)
  final String? breed;

  /// Vaccine (store label such as 'FPV — Panleukopenia')
  final String? vaccine;

  /// Max distance in km. If null = no distance filter.
  final double? maxDistanceKm;

  const CatFilterOptions({
    this.gender,
    this.minAgeYears,
    this.maxAgeYears,
    this.breed,
    this.vaccine,
    this.maxDistanceKm,
  });

  CatFilterOptions copyWith({
    String? gender,
    int? minAgeYears,
    int? maxAgeYears,
    String? breed,
    String? vaccine,
    double? maxDistanceKm,
  }) {
    return CatFilterOptions(
      gender: gender ?? this.gender,
      minAgeYears: minAgeYears ?? this.minAgeYears,
      maxAgeYears: maxAgeYears ?? this.maxAgeYears,
      breed: breed ?? this.breed,
      vaccine: vaccine ?? this.vaccine,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
    );
  }

  static const empty = CatFilterOptions();

  bool get isEmpty =>
      gender == null &&
      minAgeYears == null &&
      maxAgeYears == null &&
      breed == null &&
      vaccine == null &&
      maxDistanceKm == null;
}

/// Convert birthdate to age in years
int? _ageInYears(DateTime? birthdate) {
  if (birthdate == null) return null;
  final now = DateTime.now();
  int years = now.year - birthdate.year;
  final beforeBirthday = (now.month < birthdate.month) ||
      (now.month == birthdate.month && now.day < birthdate.day);
  if (beforeBirthday) years -= 1;
  if (years < 0) years = 0;
  return years;
}

/// Check if a cat matches the filter (excluding distance)
bool _matchFilter(Cat cat, CatFilterOptions filter) {
  if (filter.isEmpty) return true;

  // --- Gender ---
  if (filter.gender != null && filter.gender!.isNotEmpty) {
    if (cat.gender != filter.gender) {
      return false;
    }
  }

  // --- Age ---
  if (filter.minAgeYears != null || filter.maxAgeYears != null) {
    final ageYears = _ageInYears(cat.birthdate);
    if (ageYears != null) {
      if (filter.minAgeYears != null && ageYears < filter.minAgeYears!) {
        return false;
      }
      if (filter.maxAgeYears != null && ageYears > filter.maxAgeYears!) {
        return false;
      }
    }
  }

  // --- Breed ---
  if (filter.breed != null && filter.breed!.isNotEmpty) {
    // Compare with cat.breed (English name)
    if (cat.breed != filter.breed) {
      return false;
    }
  }

  // --- Vaccine ---
  //
  // Recommended: store summary field in cat document such as
  //   vaccineTypes: array<String> with labels like 'FPV — Panleukopenia'
  // and then add vaccineTypes to Cat model.
  if (filter.vaccine != null && filter.vaccine!.isNotEmpty) {
    try {
      final List<String> vaccineTypes =
          (cat as dynamic).vaccineTypes as List<String>? ?? <String>[];
      if (!vaccineTypes.contains(filter.vaccine)) {
        return false;
      }
    } catch (_) {
      // If Cat model doesn't have this field yet, skip this filter
      // (avoid crashing the app).
    }
  }

  return true;
}

/// BottomSheet for selecting cat filters (English UI, data from Firestore)
Future<CatFilterOptions?> showCatFilterBottomSheet(
  BuildContext context,
  CatFilterOptions current, {
  required List<_BreedOption> breedOptions,
  required List<String> vaccineOptions,
}) async {
  final genderOptions = ['male', 'female'];

  String? gender = current.gender;
  String? breed = current.breed;
  String? vaccine = current.vaccine;

  int? minAge = current.minAgeYears ?? 0;
  int? maxAge = current.maxAgeYears ?? 20;

  // Default max distance 10 km
  double? maxDistanceKm = current.maxDistanceKm ?? 10;

  return showModalBottomSheet<CatFilterOptions>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Match Filters 🐾',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // Gender
                    DropdownButtonFormField<String?>(
                      isExpanded: true, // ✅ prevent horizontal overflow
                      value: gender,
                      decoration: const InputDecoration(
                        labelText: 'Cat gender',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Any'),
                        ),
                        ...genderOptions.map(
                          (g) => DropdownMenuItem<String?>(
                            value: g,
                            child:
                                Text(g == 'male' ? 'Male (♂)' : 'Female (♀)'),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => gender = val),
                    ),
                    const SizedBox(height: 12),

                    // Age
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: minAge.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Min age (years)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) =>
                                minAge = int.tryParse(val) ?? minAge,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: maxAge.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max age (years)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) =>
                                maxAge = int.tryParse(val) ?? maxAge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Breed (Dropdown) - from Firestore (lookups/catBreeds/items)
                    DropdownButtonFormField<String?>(
                      isExpanded: true, // ✅ prevent horizontal overflow
                      value: breed,
                      decoration: const InputDecoration(
                        labelText: 'Breed',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Any'),
                        ),
                        ...breedOptions.map(
                          (b) => DropdownMenuItem<String?>(
                            value: b.nameEn, // Use English name for filtering
                            child: Text(
                              b.label, // Show English (Thai)
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => breed = val),
                    ),
                    const SizedBox(height: 12),

                    // Vaccine (Dropdown) - from Firestore (lookups/vaccineTypes/items)
                    DropdownButtonFormField<String?>(
                      isExpanded: true, // ✅ prevent horizontal overflow
                      value: vaccine,
                      decoration: const InputDecoration(
                        labelText: 'Vaccination',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Any')),
                        ...vaccineOptions.map(
                          (v) => DropdownMenuItem<String?>(
                            value: v,
                            child: Text(
                              v,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => vaccine = val),
                    ),
                    const SizedBox(height: 16),

                    // Max distance
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text('Maximum distance from you'),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(maxDistanceKm ?? 10).round()} km',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: ((maxDistanceKm ?? 10).clamp(1, 100)).toDouble(),
                          min: 1,
                          max: 100,
                          divisions: 99,
                          label: '${(maxDistanceKm ?? 10).round()} km',
                          onChanged: (v) => setState(() => maxDistanceKm = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(ctx, CatFilterOptions.empty),
                          child: const Text('Clear filters'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(
                              ctx,
                              CatFilterOptions(
                                gender: gender,
                                minAgeYears: minAge,
                                maxAgeYears: maxAge,
                                breed: breed,
                                vaccine: vaccine,
                                maxDistanceKm: maxDistanceKm,
                              ),
                            );
                          },
                          child: const Text('Apply filters'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});
  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _auth = FirebaseAuth.instance;
  late final String _me;

  late SwipableStackController _controller;
  bool _liking = false;

  // ===== states per active cat =====
  String _activeCatId = '';
  Set<String> _localSwiped = {};
  Key _deckKey = UniqueKey(); // Used to hard-reset deck when active cat changes

  // Current filter
  CatFilterOptions _currentFilter = CatFilterOptions.empty;

  // User location (as reference point)
  double? _myLat;
  double? _myLng;

  // Breed/vaccine options from Firestore
  List<_BreedOption> _breedOptions = [];
  List<String> _vaccineOptions = [];
  bool _loadingLookups = true;

  String _prefsKeyFor(String uid, String catId) =>
      'swipedCats_v3__${uid}__${catId}';

  @override
  void initState() {
    super.initState();
    _me = _auth.currentUser!.uid;
    _controller = SwipableStackController();
    _loadMyLocation();
    _loadLookups();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ===== Load breed / vaccine lookups from Firestore =====
  Future<void> _loadLookups() async {
    try {
      // /lookups/catBreeds/items
      final breedsQs = await FirebaseFirestore.instance
          .collection('lookups')
          .doc('catBreeds')
          .collection('items')
          .orderBy(FieldPath.documentId)
          .get();

      final breeds = breedsQs.docs.map((d) {
        final m = d.data();
        final en = (m['name_en'] ?? '').toString().trim();
        final th = (m['name_th'] ?? '').toString().trim();
        final id = (m['id'] ?? d.id).toString().trim();
        final nameEn = en.isNotEmpty ? en : id;
        return _BreedOption(id, nameEn, th);
      }).toList();

      // /lookups/vaccineTypes/items
      final vaccinesQs = await FirebaseFirestore.instance
          .collection('lookups')
          .doc('vaccineTypes')
          .collection('items')
          .orderBy(FieldPath.documentId)
          .get();

      final vaccines = vaccinesQs.docs.map((d) {
        final m = d.data();
        final code = (m['code'] ?? d.id).toString().trim();
        final desc = (m['desc'] ?? m['name'] ?? '').toString().trim();
        return desc.isNotEmpty ? '$code — $desc' : code;
      }).toList();

      setState(() {
        _breedOptions = breeds;
        _vaccineOptions = vaccines;
        _loadingLookups = false;
      });
    } catch (e) {
      debugPrint('Failed to load breed/vaccine lookups: $e');
      setState(() {
        _loadingLookups = false;
      });
    }
  }

  // ===== GPS / Location =====
  Future<void> _loadMyLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location service disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _myLat = pos.latitude;
        _myLng = pos.longitude;
      });

      // Save location to users/{uid}
      await FirebaseFirestore.instance.collection('users').doc(_me).set(
        {
          'location': {
            'lat': _myLat,
            'lng': _myLng,
            'updatedAt': FieldValue.serverTimestamp(),
          }
        },
        SetOptions(merge: true),
      );

      // Update all cats owned by this user
      final catsSnap = await FirebaseFirestore.instance
          .collection('cats')
          .where('ownerId', isEqualTo: _me)
          .get();

      for (final doc in catsSnap.docs) {
        await doc.reference.update({
          'ownerLat': _myLat,
          'ownerLng': _myLng,
        });
      }
    } catch (e) {
      debugPrint('loadMyLocation error: $e');
    }
  }

  double _deg2rad(double deg) => deg * (pi / 180.0);

  /// Calculate distance between user (_myLat/_myLng) and this cat (ownerLat/ownerLng)
  double? _distanceKmFromMe(Cat cat) {
    if (_myLat == null || _myLng == null) return null;
    final ownerLat = (cat as dynamic).ownerLat as double?;
    final ownerLng = (cat as dynamic).ownerLng as double?;
    if (ownerLat == null || ownerLng == null) return null;

    const earthRadius = 6371.0; // km
    final dLat = _deg2rad(ownerLat - _myLat!);
    final dLon = _deg2rad(ownerLng - _myLng!);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(_myLat!)) *
            cos(_deg2rad(ownerLat)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  // ===== streams / loaders =====
  Stream<String?> _activeCatStream(String uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => (d.data()?['activeCatId'] as String?)?.trim());

  Stream<List<Cat>> _candidates() => FirebaseFirestore.instance
      .collection('cats')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (qs) => qs.docs
            .where((d) {
              final data = d.data();
              final owner = (data['ownerUid'] ?? data['ownerId']) as String?;
              return owner != _me; // exclude my own cats
            })
            .map((d) => Cat.fromDoc(d))
            .toList(),
      );

  Stream<Set<String>> _remoteSwiped(String catId) {
    if (catId.isEmpty) return Stream.value(<String>{});
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_me)
        .collection('swipedByCat')
        .doc(catId)
        .collection('items')
        .snapshots()
        .map((qs) => qs.docs.map((d) => d.id).toSet());
  }

  Future<void> _loadLocalFor(String catId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKeyFor(_me, catId)) ?? const [];
    if (!mounted) return;
    setState(() => _localSwiped = list.toSet());
  }

  Future<void> _saveLocal(String catId, String otherCatId) async {
    _localSwiped.add(otherCatId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyFor(_me, catId),
      _localSwiped.toList(),
    );
  }

  // ===== match / room helpers =====
  Future<bool> _isMyCatExists(String catId) async {
    if (catId.isEmpty) return false;
    final d =
        await FirebaseFirestore.instance.collection('cats').doc(catId).get();
    if (!d.exists) return false;
    final owner =
        (d.data()?['ownerUid'] ?? d.data()?['ownerId']) as String?;
    return owner == _me;
  }

  Future<void> _ensureRoom({
    required String pairId,
    required String catA,
    required String catB,
  }) async {
    final db = FirebaseFirestore.instance;
    final roomRef = db.collection('rooms').doc(pairId);
    await db.runTransaction((tx) async {
      final a = await tx.get(db.collection('cats').doc(catA));
      final b = await tx.get(db.collection('cats').doc(catB));
      final uidA =
          (a.data()?['ownerUid'] ?? a.data()?['ownerId'] ?? '') as String;
      final uidB =
          (b.data()?['ownerUid'] ?? b.data()?['ownerId'] ?? '') as String;

      final now = FieldValue.serverTimestamp();
      final snap = await tx.get(roomRef);
      if (snap.exists) {
        tx.set(
          roomRef,
          {
            'catIds': [catA, catB],
            'uids': [uidA, uidB],
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      } else {
        tx.set(roomRef, {
          'catIds': [catA, catB],
          'uids': [uidA, uidB],
          'createdAt': now,
          'updatedAt': now,
          'lastMessage': '',
        });
      }
    });
  }

  Future<bool> _isMatched(String pairId) async {
    final d = await FirebaseFirestore.instance
        .collection('matches')
        .doc(pairId)
        .get();
    return (d.data()?['matched'] as bool?) == true;
  }

  // ===== persist swiped (per active cat) =====
  Future<void> _markSwiped({
    required String myCatId,
    required String otherCatId,
    required String type, // 'like' | 'pass'
  }) async {
    await _saveLocal(myCatId, otherCatId); // local first
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_me)
          .collection('swipedByCat')
          .doc(myCatId)
          .collection('items')
          .doc(otherCatId)
          .set(
        {'type': type, 'at': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Failed to save swipe status (remote): $e');
    }
  }

  // ===== swipe handlers =====
  Future<void> _handleLike(String myCatId, String otherCatId) async {
    if (_liking) return;
    setState(() => _liking = true);
    try {
      if (!(await _isMyCatExists(myCatId))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please select an active cat for matching on your profile page.',
              ),
            ),
          );
        }
        return;
      }

      final a = (myCatId.compareTo(otherCatId) <= 0) ? myCatId : otherCatId;
      final b = (myCatId.compareTo(otherCatId) <= 0) ? otherCatId : myCatId;
      final pairId = '${a}__${b}';
      final ref =
          FirebaseFirestore.instance.collection('matches').doc(pairId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final now = FieldValue.serverTimestamp();
        if (!snap.exists) {
          tx.set(ref, {
            'catA': a,
            'catB': b,
            'lastLikeBy': myCatId,
            'likedBy': [myCatId],
            'passedBy': [],
            'matched': false,
            'timestamp': now,
          });
          return;
        }
        final data = snap.data() ?? {};
        final likedBy =
            (data['likedBy'] as List?)?.cast<String>().toSet() ?? <String>{};
        likedBy.add(myCatId);
        final becameMatched = likedBy.contains(a) && likedBy.contains(b);
        tx.set(
          ref,
          {
            'catA': data['catA'] ?? a,
            'catB': data['catB'] ?? b,
            'lastLikeBy': myCatId,
            'likedBy': likedBy.toList(),
            'matched': becameMatched,
            'timestamp': now,
          },
          SetOptions(merge: true),
        );
      });

      await _markSwiped(
        myCatId: myCatId,
        otherCatId: otherCatId,
        type: 'like',
      );

      if (await _isMatched(pairId)) {
        await _ensureRoom(pairId: pairId, catA: a, catB: b);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('It\'s a match! Your chat room is ready 🥳'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Like sent')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _handlePass(String myCatId, String otherCatId) async {
    try {
      if (!(await _isMyCatExists(myCatId))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please select an active cat for matching on your profile page.',
              ),
            ),
          );
        }
        return;
      }

      final a = (myCatId.compareTo(otherCatId) <= 0) ? myCatId : otherCatId;
      final b = (myCatId.compareTo(otherCatId) <= 0) ? otherCatId : myCatId;
      final pairId = '${a}__${b}';
      final ref =
          FirebaseFirestore.instance.collection('matches').doc(pairId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final now = FieldValue.serverTimestamp();
        if (!snap.exists) {
          tx.set(ref, {
            'catA': a,
            'catB': b,
            'likedBy': [],
            'passedBy': [myCatId],
            'matched': false,
            'timestamp': now,
          });
          return;
        }
        final data = snap.data() ?? {};
        final passedBy =
            (data['passedBy'] as List?)?.cast<String>().toSet() ?? <String>{};
        passedBy.add(myCatId);
        tx.set(
          ref,
          {
            'catA': data['catA'] ?? a,
            'catB': data['catB'] ?? b,
            'passedBy': passedBy.toList(),
            'matched': false,
            'timestamp': now,
          },
          SetOptions(merge: true),
        );
      });

      await _markSwiped(
        myCatId: myCatId,
        otherCatId: otherCatId,
        type: 'pass',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save left swipe: $e')),
        );
      }
    }
  }

  // ===== overlay (background color changes based on swipe direction) =====
  Widget _swipeOverlay(
    BuildContext context, {
    required double progress,
    required SwipeDirection? direction,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final opacity = (0.15 + 0.85 * p).clamp(0.0, 1.0);
    Color color;
    if (direction == SwipeDirection.right) {
      color = Colors.green.withOpacity(opacity);
    } else if (direction == SwipeDirection.left) {
      color = Colors.red.withOpacity(opacity);
    } else {
      color = Colors.transparent;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(color: color),
    );
  }

  // ===== hard reset deck when activeCat changes =====
  void _hardResetFor(String newCatId) {
    _deckKey = UniqueKey();
    _localSwiped = {};
    _controller.dispose();
    _controller = SwipableStackController();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadLocalFor(newCatId));
  }

  Future<void> _openFilter() async {
    final result = await showCatFilterBottomSheet(
      context,
      _currentFilter,
      breedOptions: _breedOptions,
      vaccineOptions: _vaccineOptions,
    );
    if (result != null) {
      setState(() {
        _currentFilter = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to active-cat changes in real-time
    return StreamBuilder<String?>(
      stream: _activeCatStream(_me),
      builder: (context, activeSnap) {
        final myCatId = (activeSnap.data ?? '').trim();

        if (activeSnap.hasError) {
          return Center(
            child: Text('Failed to load profile: ${activeSnap.error}'),
          );
        }
        if (activeSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (myCatId.isEmpty) {
          return const Center(
            child: Text(
              'Please select an active cat for matching in your profile first 🐾',
              textAlign: TextAlign.center,
            ),
          );
        }

        if (myCatId != _activeCatId) {
          _activeCatId = myCatId;
          _hardResetFor(myCatId);
        }

        return StreamBuilder<Set<String>>(
          stream: _remoteSwiped(myCatId),
          initialData: const <String>{},
          builder: (context, swipedSnap) {
            final remote = swipedSnap.data ?? <String>{};
            final effectiveSwiped = <String>{...remote, ..._localSwiped};

            return StreamBuilder<List<Cat>>(
              stream: _candidates(),
              builder: (context, catsSnap) {
                if (catsSnap.hasError) {
                  return Center(
                    child: Text('Failed to load cats: ${catsSnap.error}'),
                  );
                }
                if (catsSnap.connectionState == ConnectionState.waiting &&
                    (catsSnap.data == null || catsSnap.data!.isEmpty)) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = catsSnap.data ?? [];

                // Filter: swiped + general filters + distance
                final filtered = all
                    .where(
                      (c) => !effectiveSwiped.contains(c.id),
                    ) // not swiped yet
                    .where((c) => _matchFilter(c, _currentFilter))
                    .where((c) {
                      final maxDist = _currentFilter.maxDistanceKm;
                      if (maxDist == null) return true; // no distance filter
                      final dist = _distanceKmFromMe(c);
                      if (dist == null) {
                        // If we don't have distance, keep the cat (avoid empty results)
                        return true;
                      }
                      return dist <= maxDist;
                    })
                    .toList();

                return Column(
                  children: [
                    // Filter bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: _loadingLookups ? null : _openFilter,
                            icon: const Icon(Icons.filter_list),
                            label: const Text('Filters'),
                          ),
                          const SizedBox(width: 8),
                          if (_loadingLookups)
                            const Text(
                              'Loading filter data...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            )
                          else if (!_currentFilter.isEmpty)
                            Text(
                              _currentFilter.maxDistanceKm != null
                                  ? 'Filters applied • ≤ ${_currentFilter.maxDistanceKm!.round()} km'
                                  : 'Filters applied',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text(
                                  'No cats to swipe right now 😿\nTry changing filters or come back later.',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : KeyedSubtree(
                                key: _deckKey,
                                child: SwipableStack(
                                  controller: _controller,
                                  itemCount: filtered.length,
                                  detectableSwipeDirections: const {
                                    SwipeDirection.left,
                                    SwipeDirection.right,
                                  },
                                  overlayBuilder: (context, props) =>
                                      _swipeOverlay(
                                    context,
                                    progress: props.swipeProgress.abs(),
                                    direction: props.direction,
                                  ),
                                  onSwipeCompleted:
                                      (index, direction) async {
                                    final otherId = filtered[index].id;
                                    if (direction ==
                                        SwipeDirection.right) {
                                      await _handleLike(myCatId, otherId);
                                    } else if (direction ==
                                        SwipeDirection.left) {
                                      await _handlePass(myCatId, otherId);
                                    }
                                  },
                                  builder: (context, props) {
                                    final cat = filtered[props.index];
                                    final dist = _distanceKmFromMe(cat);
                                    return _SwipeCard(
                                      cat: cat,
                                      distanceKm: dist,
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SwipeCard extends StatelessWidget {
  final Cat cat;
  final double? distanceKm; // ✅ ระยะห่างจากเรา (กม.)

  const _SwipeCard({
    required this.cat,
    this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        cat.imageUrls.isNotEmpty ? cat.imageUrls.first : null;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CatDetailPage(catId: cat.id),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.grey.shade300,
              image: imageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(16)),
                gradient: LinearGradient(
                  colors: [Colors.black54, Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
              child: _CatFooter(
                cat: cat,
                distanceKm: distanceKm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatFooter extends StatelessWidget {
  final Cat cat;
  final double? distanceKm;

  const _CatFooter({
    required this.cat,
    this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    final ageText = ageLabel(cat.birthdate);
    final genderText = (cat.gender == 'male')
        ? '♂'
        : (cat.gender == 'female')
            ? '♀'
            : '-';

    String? distanceText;
    if (distanceKm != null) {
      final d = distanceKm!;
      if (d < 1) {
        // < 1 km แสดงเป็น เมตร คร่าว ๆ
        distanceText = '≈ ${(d * 1000).round()} m away';
      } else {
        distanceText = '≈ ${d.toStringAsFixed(1)} km away';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${cat.name}, $ageText ($genderText)',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        if (distanceText != null) ...[
          const SizedBox(height: 2),
          Text(
            distanceText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.2,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          cat.description.isNotEmpty ? cat.description : '—',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
