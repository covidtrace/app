double _sampleUnixSeconds(DateTime d, int minutes) =>
    d.millisecondsSinceEpoch / 1000 / 60 / minutes;

int ceilUnixSeconds(DateTime d, int minutes) =>
    _sampleUnixSeconds(d, minutes).ceil() * minutes * 60;

int roundedUnixSeconds(DateTime d, int minutes) =>
    _sampleUnixSeconds(d, minutes).round() * minutes * 60;
