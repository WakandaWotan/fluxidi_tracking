/// Guards one opening of Mijn boekingen so a late response cannot overwrite
/// a newer customer or a newer open.
class CustomerSavedListOpenGuard {
  int _generation = 0;
  String? _customerKey;
  Future<void>? _inFlightNetwork;

  int get generation => _generation;
  String? get customerKey => _customerKey;

  /// Starts a new open. A different customer clears the previous identity.
  int begin(String? customerKey) {
    _customerKey = _normalizeCustomerKey(customerKey);
    return ++_generation;
  }

  bool accepts(int generation, String? customerKey) {
    return generation == _generation &&
        _normalizeCustomerKey(customerKey) == _customerKey;
  }

  /// Joins an in-flight network refresh for the same customer.
  Future<void> runExclusiveNetwork(Future<void> Function() work) {
    if (_inFlightNetwork != null) return _inFlightNetwork!;
    final future = work();
    _inFlightNetwork = future.whenComplete(() {
      _inFlightNetwork = null;
    });
    return _inFlightNetwork!;
  }

  bool get hasInFlightNetwork => _inFlightNetwork != null;

  static String? _normalizeCustomerKey(String? customerKey) {
    final trimmed = (customerKey ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
