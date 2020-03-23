int roundedDateTime(DateTime d) {
  return (d.millisecondsSinceEpoch / 1000 / 60 / 60).ceil() * 60 * 60;
}