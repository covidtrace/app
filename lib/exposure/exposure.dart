abstract class Exposure<T> {
  final List<T> items;
  const Exposure(this.items);

  // `data` is a CSV string, so it needs to be parsed as a CSV and
  // then processed
  Future<Iterable<T>> getExposures(String data);
}
