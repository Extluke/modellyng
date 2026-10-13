/// Label rujukan paper yang dipakai di Matriks dan Maps:
/// "Paper 1", "Paper 1 & 2", "Paper 1, 2 & 4".
String paperNumbersLabel(Iterable<int> numbers) {
  final sorted = numbers.toSet().toList()..sort();
  if (sorted.isEmpty) return 'Paper';
  if (sorted.length == 1) return 'Paper ${sorted.single}';
  final head = sorted.sublist(0, sorted.length - 1).join(', ');
  return 'Paper $head & ${sorted.last}';
}
