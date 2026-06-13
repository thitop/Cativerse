import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> seedLookups() async {
  final db = FirebaseFirestore.instance;

  final breeds = [
    'Thai','Siamese','Persian','Maine Coon','British Shorthair','Scottish Fold',
    'Bengal','Ragdoll','American Shorthair','Sphynx','Norwegian Forest',
    'Russian Blue','Abyssinian','Birman','Oriental','Exotic Shorthair',
    'Savannah','Munchkin','Domestic Short Hair','Domestic Long Hair','Other',
  ];

  final vaccines = [
    'FVRCP (ไข้หัด_หวัดแมวรวม)',
    'Rabies (พิษสุนัขบ้า)',
    'FeLV (มะเร็งเม็ดเลือดขาวแมว)',
    'Chlamydia',
    'Bordetella',
  ];

  final wb = db.batch();

  final breedsCol = db.collection('lookups').doc('catBreeds').collection('items');
  for (var i = 0; i < breeds.length; i++) {
    final id = breeds[i].toLowerCase().replaceAll(' ', '-');
    wb.set(breedsCol.doc(id), {'name': breeds[i], 'active': true, 'order': i});
  }

  final vaccinesCol = db.collection('lookups').doc('vaccineTypes').collection('items');
  for (var i = 0; i < vaccines.length; i++) {
    final id = vaccines[i].toLowerCase().replaceAll(' ', '-');
    wb.set(vaccinesCol.doc(id), {'name': vaccines[i], 'active': true, 'order': i});
  }

  await wb.commit();
}
