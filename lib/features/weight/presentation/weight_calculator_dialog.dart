import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../data/weight_calculator.dart';

typedef WeightResult = ({double kg, String description});

Future<WeightResult?> showWeightCalculator(BuildContext context) =>
    showDialog<WeightResult>(
      context: context,
      builder: (_) => const _WeightCalculatorDialog(),
    );

class _WeightCalculatorDialog extends StatefulWidget {
  const _WeightCalculatorDialog();

  @override
  State<_WeightCalculatorDialog> createState() =>
      _WeightCalculatorDialogState();
}

class _WeightCalculatorDialogState extends State<_WeightCalculatorDialog> {
  Metal _metal = Metal.steel;
  SectionShape _shape = SectionShape.plate;
  // Up to three section dimensions; labels change with the shape.
  final _dims = List.generate(3, (_) => TextEditingController());
  final _length = TextEditingController(text: '6');
  final _pieces = TextEditingController(text: '1');

  @override
  void dispose() {
    for (final c in _dims) {
      c.dispose();
    }
    _length.dispose();
    _pieces.dispose();
    super.dispose();
  }

  List<double> get _dimensions => [
    for (var i = 0; i < _shape.dimensionLabels.length; i++)
      parseNumber(_dims[i].text) ?? 0,
  ];

  double? get _weight => weightKg(
    shape: _shape,
    material: _metal,
    dimensionsMm: _dimensions,
    lengthM: parseNumber(_length.text) ?? 0,
    pieces: parseNumber(_pieces.text)?.round() ?? 0,
  );

  Widget _number(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final weight = _weight;
    return AlertDialog(
      title: const Text('حاسبة الوزن'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<Metal>(
              showSelectedIcon: false,
              segments: [
                for (final m in Metal.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {_metal},
              onSelectionChanged: (s) => setState(() => _metal = s.first),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in SectionShape.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _shape == s,
                    onSelected: (_) => setState(() => _shape = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _shape.dimensionLabels.length; i++)
              _number(_dims[i], _shape.dimensionLabels[i]),
            _number(
              _length,
              _shape == SectionShape.plate ? 'الطول (متر)' : 'طول القطعة (متر)',
            ),
            _number(_pieces, 'عدد القطع'),
            const SizedBox(height: 4),
            Text(
              weight == null
                  ? 'أدخل المقاسات'
                  : 'الوزن: ${formatQuantity(weight)} كيلو'
                        '${weight >= 1000 ? ' (${formatQuantity(weight / 1000)} طن)' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: weight == null
              ? null
              : () => Navigator.pop<WeightResult>(context, (
                  kg: weight,
                  description: describe(_shape, _metal, _dimensions),
                )),
          child: const Text('استخدام الوزن'),
        ),
      ],
    );
  }
}
