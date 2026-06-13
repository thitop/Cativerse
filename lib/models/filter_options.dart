// lib/models/filter_options.dart
class FilterOptions {
  final String? gender;          // null = ไม่กรองเพศ
  final int? minAge;
  final int? maxAge;
  final String? province;
  final List<String> breedIds;   // id ของสายพันธุ์แมว

  const FilterOptions({
    this.gender,
    this.minAge,
    this.maxAge,
    this.province,
    this.breedIds = const [],
  });

  FilterOptions copyWith({
    String? gender,
    int? minAge,
    int? maxAge,
    String? province,
    List<String>? breedIds,
  }) {
    return FilterOptions(
      gender: gender ?? this.gender,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      province: province ?? this.province,
      breedIds: breedIds ?? this.breedIds,
    );
  }

  static const empty = FilterOptions();
}
