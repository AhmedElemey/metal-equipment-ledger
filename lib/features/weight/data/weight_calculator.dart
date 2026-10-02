import 'dart:math';

/// Densities in kg/m³.
enum Metal {
  steel('حديد', 7850),
  stainless('استانلس', 7930),
  aluminum('ألومنيوم', 2700);

  const Metal(this.label, this.density);
  final String label;
  final double density;
}

/// Cross-section shapes. Every dimension is in millimetres except the
/// length, which is in metres.
enum SectionShape {
  plate('صاج / لوح', ['العرض (مم)', 'السمك (مم)']),
  flatBar('خوصة', ['العرض (مم)', 'السمك (مم)']),
  roundBar('سيخ / عمود مصمت', ['القطر (مم)']),
  roundPipe('ماسورة مستديرة', ['القطر الخارجي (مم)', 'سمك الجدار (مم)']),
  hollowSection('مربع / مستطيل مجوف', [
    'الضلع أ (مم)',
    'الضلع ب (مم)',
    'السمك (مم)',
  ]),
  angle('زاوية', ['الضلع أ (مم)', 'الضلع ب (مم)', 'السمك (مم)']);

  const SectionShape(this.label, this.dimensionLabels);
  final String label;
  final List<String> dimensionLabels;
}

/// Cross-section area in mm², or null if the dimensions are impossible
/// (e.g. a wall thicker than half the pipe).
double? sectionArea(SectionShape shape, List<double> d) {
  if (d.length != shape.dimensionLabels.length || d.any((v) => v <= 0)) {
    return null;
  }
  switch (shape) {
    case SectionShape.plate:
    case SectionShape.flatBar:
      return d[0] * d[1];
    case SectionShape.roundBar:
      return pi * d[0] * d[0] / 4;
    case SectionShape.roundPipe:
      final inner = d[0] - 2 * d[1];
      if (inner < 0) return null;
      return pi / 4 * (d[0] * d[0] - inner * inner);
    case SectionShape.hollowSection:
      final (a, b, t) = (d[0], d[1], d[2]);
      if (2 * t > min(a, b)) return null;
      return a * b - (a - 2 * t) * (b - 2 * t);
    case SectionShape.angle:
      final (a, b, t) = (d[0], d[1], d[2]);
      if (t >= min(a, b)) return null;
      return t * (a + b - t);
  }
}

/// Weight in kg of [pieces] pieces, each [lengthM] metres long.
double? weightKg({
  required SectionShape shape,
  required Metal material,
  required List<double> dimensionsMm,
  required double lengthM,
  int pieces = 1,
}) {
  final area = sectionArea(shape, dimensionsMm);
  if (area == null || lengthM <= 0 || pieces <= 0) return null;
  return area * 1e-6 * lengthM * material.density * pieces;
}

/// A short item name for the calculated piece, e.g. "ماسورة مستديرة 60×3 مم".
String describe(SectionShape shape, Metal material, List<double> d) {
  String n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  final prefix = material == Metal.steel ? '' : ' ${material.label}';
  return '${shape.label}$prefix ${d.map(n).join('×')} مم';
}
