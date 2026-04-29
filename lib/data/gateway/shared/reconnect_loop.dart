class ReconnectLoop {
  static const _cap = 30000;
  int _next = 1000;
  bool _afterReset = false;

  int nextBackoffMs() {
    if (_afterReset) {
      _afterReset = false;
      _next = 1600; // next-after-reset becomes 800 → 1600 → 3200 …
      return 800;
    }
    final v = _next > _cap ? _cap : _next;
    _next = (_next * 2).clamp(0, _cap);
    return v;
  }

  void reset() {
    _next = 1000;
    _afterReset = true;
  }
}
