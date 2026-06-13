// lib/widgets/match_filter_bottom_sheet.dart
import 'package:flutter/material.dart';
import '../models/filter_options.dart';

Future<FilterOptions?> showMatchFilterBottomSheet(
  BuildContext context,
  FilterOptions current,
) async {
  final genderOptions = ['male', 'female', 'other'];
  final provinces = ['Bangkok', 'Chiang Mai', 'Rayong']; // ภายหลังดึงจาก DB ได้
  final breedOptions = <String, String>{
    'beng': 'Bengal',
    'siam': 'Siamese',
    'ragdoll': 'Ragdoll',
  };

  String? gender = current.gender;
  String? province = current.province;
  int? minAge = current.minAge ?? 18;
  int? maxAge = current.maxAge ?? 35;
  final selectedBreeds = current.breedIds.toSet();

  return showModalBottomSheet<FilterOptions>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
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
                    'ตัวกรองการแมช',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // เพศ
                  DropdownButtonFormField<String>(
                    value: gender,
                    decoration: const InputDecoration(
                      labelText: 'เพศ',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('ไม่ระบุ'),
                      ),
                      ...genderOptions.map(
                        (g) => DropdownMenuItem(
                          value: g,
                          child: Text(g),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => gender = val),
                  ),
                  const SizedBox(height: 12),

                  // อายุ
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: minAge.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'อายุต่ำสุด',
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
                            labelText: 'อายุมากสุด',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) =>
                              maxAge = int.tryParse(val) ?? maxAge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // จังหวัด
                  DropdownButtonFormField<String>(
                    value: province,
                    decoration: const InputDecoration(
                      labelText: 'จังหวัด',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('ไม่ระบุ'),
                      ),
                      ...provinces.map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(p),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => province = val),
                  ),
                  const SizedBox(height: 12),

                  // สายพันธุ์
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: breedOptions.entries.map((entry) {
                        final selected = selectedBreeds.contains(entry.key);
                        return FilterChip(
                          label: Text(entry.value),
                          selected: selected,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                selectedBreeds.add(entry.key);
                              } else {
                                selectedBreeds.remove(entry.key);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, FilterOptions.empty),
                        child: const Text('ล้างตัวกรอง'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(
                            ctx,
                            FilterOptions(
                              gender: gender,
                              minAge: minAge,
                              maxAge: maxAge,
                              province: province,
                              breedIds: selectedBreeds.toList(),
                            ),
                          );
                        },
                        child: const Text('ใช้ตัวกรอง'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
