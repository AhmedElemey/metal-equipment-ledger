import 'package:flutter_test/flutter_test.dart';
import 'package:metal_ledger/features/weight/data/weight_calculator.dart';

void main() {
  // Reference values from standard steel tables (density 7,850 kg/m³).
  test('plate: 1 m × 1 m × 1 mm steel weighs 7.85 kg', () {
    final w = weightKg(
      shape: SectionShape.plate,
      material: Metal.steel,
      dimensionsMm: [1000, 1],
      lengthM: 1,
    );
    expect(w, closeTo(7.85, 1e-9));
  });

  test('rebar Ø12: 0.888 kg/m', () {
    final w = weightKg(
      shape: SectionShape.roundBar,
      material: Metal.steel,
      dimensionsMm: [12],
      lengthM: 12,
      pieces: 10,
    );
    expect(w! / 120, closeTo(0.888, 0.001));
  });

  test('pipe 60.3 × 3.2: about 4.51 kg/m', () {
    final w = weightKg(
      shape: SectionShape.roundPipe,
      material: Metal.steel,
      dimensionsMm: [60.3, 3.2],
      lengthM: 6,
    );
    expect(w! / 6, closeTo(4.51, 0.01));
  });

  // Tables list 3.77 kg/m; their root fillets add a little the formula skips.
  test('angle 50×50×5: about 3.73 kg/m', () {
    final w = weightKg(
      shape: SectionShape.angle,
      material: Metal.steel,
      dimensionsMm: [50, 50, 5],
      lengthM: 1,
    );
    expect(w, closeTo(3.73, 0.05));
  });

  test('square tube 40×40×2: about 2.39 kg/m', () {
    final w = weightKg(
      shape: SectionShape.hollowSection,
      material: Metal.steel,
      dimensionsMm: [40, 40, 2],
      lengthM: 1,
    );
    expect(w, closeTo(2.39, 0.03));
  });

  test('aluminium is about a third of steel', () {
    double w(Metal m) => weightKg(
      shape: SectionShape.flatBar,
      material: m,
      dimensionsMm: [50, 5],
      lengthM: 6,
    )!;
    expect(w(Metal.aluminum) / w(Metal.steel), closeTo(2700 / 7850, 1e-9));
  });

  test('impossible or missing dimensions give null', () {
    expect(
      sectionArea(SectionShape.roundPipe, [20, 11]),
      isNull,
    ); // wall > radius
    expect(sectionArea(SectionShape.hollowSection, [40, 40, 25]), isNull);
    expect(sectionArea(SectionShape.angle, [50, 50, 50]), isNull);
    expect(sectionArea(SectionShape.plate, [1000]), isNull);
    expect(sectionArea(SectionShape.roundBar, [0]), isNull);
    expect(
      weightKg(
        shape: SectionShape.roundBar,
        material: Metal.steel,
        dimensionsMm: [12],
        lengthM: 0,
      ),
      isNull,
    );
  });

  test('describe makes a readable item name', () {
    expect(
      describe(SectionShape.roundPipe, Metal.steel, [60, 3]),
      'ماسورة مستديرة 60×3 مم',
    );
    expect(
      describe(SectionShape.plate, Metal.stainless, [1250, 1.5]),
      'صاج / لوح استانلس 1250×1.5 مم',
    );
  });
}
