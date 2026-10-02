/// Folds common Arabic spelling variants so "اسطوانة" finds "أسطوانه":
/// hamza forms of alef → ا, ة → ه, ى → ي, and drops diacritics and tatweel.
String normalizeArabic(String input) => input
    .trim()
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp('[ً-ْـ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// True if every word of [query] appears in [text], ignoring spelling
/// variants and word order ("2 صاج" matches "صاج حديد 2 مم").
bool arabicMatches(String text, String query) {
  final haystack = normalizeArabic(text);
  return normalizeArabic(query)
      .split(' ')
      .where((w) => w.isNotEmpty)
      .every(haystack.contains);
}
