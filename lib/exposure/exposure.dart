abstract class Exposure<T> {
  final List<T> items;
  const Exposure(this.items);
  Future<List<T>> getExposures(String data);
}
