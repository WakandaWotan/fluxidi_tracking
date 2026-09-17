class CustomerBookingHomeNotice {
  static String? _pending;

  static void set(String message) {
    final text = message.trim();
    _pending = text.isEmpty ? null : text;
  }

  static String? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
