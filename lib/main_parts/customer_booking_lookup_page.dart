part of '../main.dart';

/// Customer-facing booking lookup screen.
///
/// Lets a customer enter a booking reference (and optionally phone/email for
/// validation) and retrieves authoritative booking details via
/// `GET /bookings/{id}`. Read-only — does not touch payment, pricing, booking
/// creation or driver flows.
class CustomerBookingLookupPage extends StatefulWidget {
  const CustomerBookingLookupPage({super.key});

  @override
  State<CustomerBookingLookupPage> createState() =>
      _CustomerBookingLookupPageState();
}

class _CustomerBookingLookupPageState extends State<CustomerBookingLookupPage> {
  final _formKey = GlobalKey<FormState>();
  final _bookingIdCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  String _t({
    required String nl,
    required String en,
    required String fr,
    required String es,
  }) => _tr(nl: nl, en: en, fr: fr, es: es);

  @override
  void dispose() {
    _bookingIdCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String v) {
    final digits = StringBuffer();
    for (final ch in v.codeUnits) {
      if (ch >= 0x30 && ch <= 0x39) digits.writeCharCode(ch);
    }
    final out = digits.toString();
    if (out.length >= 7) {
      return out.substring(out.length - 7);
    }
    return out;
  }

  bool _matchesContact(CustomerBookingView view, String contact) {
    final c = contact.trim();
    if (c.isEmpty) return true;
    if (c.contains('@')) {
      final email = view.customerEmail.toLowerCase();
      return email.isNotEmpty && c.toLowerCase() == email;
    }
    final cNorm = _normalizePhone(c);
    final pNorm = _normalizePhone(view.customerPhone);
    if (cNorm.isEmpty || pNorm.isEmpty) return false;
    return pNorm.endsWith(cNorm) || cNorm.endsWith(pNorm);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final bookingId = _bookingIdCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final contactEmail = contact.contains('@') ? contact : null;
      final contactPhone = contact.contains('@') ? null : contact;
      final proof = await _customerOwnershipProof(
        bookingId: bookingId,
        fallbackEmail: contactEmail,
        fallbackPhone: contactPhone,
      );
      final uri = _withActiveBookingScope(
        kBookingBaseUrl,
        '/bookings/${Uri.encodeComponent(bookingId)}',
        extraQuery: proof.isEmpty ? null : proof,
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Boeking niet gevonden. Controleer de referentie.',
            en: 'Booking not found. Please check your reference.',
            fr: 'Reservation introuvable. Verifiez votre reference.',
            es: 'Reserva no encontrada. Verifica tu referencia.',
          );
        });
        return;
      }
      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Boeking niet gevonden. Controleer de referentie.',
            en: 'Booking not found. Please check your reference.',
            fr: 'Reservation introuvable. Verifiez votre reference.',
            es: 'Reserva no encontrada. Verifica tu referencia.',
          );
        });
        return;
      }
      final view = CustomerBookingView.fromResponse(bookingId, decoded);
      if (contact.isNotEmpty && !_matchesContact(view, contact)) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _t(
            nl: 'Gegevens komen niet overeen met deze boeking.',
            en: 'Details do not match this booking.',
            fr: 'Les coordonnees ne correspondent pas a cette reservation.',
            es: 'Los datos no coinciden con esta reserva.',
          );
        });
        return;
      }
      final stored = StoredCustomerBooking.fromAuthoritativeResponse(
        bookingId: bookingId,
        response: decoded,
      );
      await CustomerBookingsStore.instance.upsert(
        _hydrateStoredCustomerBookingFromView(
          stored: stored,
          view: view,
          source: 'customer_lookup',
        ),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomerBookingDetailPage(
            bookingId: bookingId,
            initialView: view,
            startsFromLocalCache: false,
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      debugPrint(
        '[CUSTOMER_LOOKUP][ERROR] bookingId=${_bookingIdCtrl.text.trim()} error=$err',
      );
      setState(() {
        _busy = false;
        _error = _t(
          nl: 'Verbinding mislukt. Probeer het opnieuw.',
          en: 'Connection failed. Please try again.',
          fr: 'Connexion echouee. Veuillez reessayer.',
          es: 'Conexion fallida. Intentalo de nuevo.',
        );
      });
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF111317),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: const Color(0xFFE5B641).withOpacity(0.18),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: const Color(0xFFE5B641).withOpacity(0.52),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1020),
          title: Text(
            _t(
              nl: 'Controleer of volg je boeking',
              en: 'Check or follow your booking',
              fr: 'Verifier ou suivre votre reservation',
              es: 'Consulta o sigue tu reserva',
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _t(
                    nl: 'Vul je boekingsreferentie in om je boeking terug te vinden.',
                    en: 'Enter your booking reference to look up your booking.',
                    fr: 'Entrez votre reference pour retrouver la reservation.',
                    es: 'Introduce tu referencia para encontrar tu reserva.',
                  ),
                  style: TextStyle(color: Colors.white.withOpacity(0.78)),
                ),
                const SizedBox(height: 14),
                _field(
                  label: _t(
                    nl: 'Boekingsreferentie',
                    en: 'Booking reference',
                    fr: 'Reference de reservation',
                    es: 'Referencia de reserva',
                  ),
                  controller: _bookingIdCtrl,
                  hintText: 'bv. 2026-04-538473',
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) {
                      return _t(
                        nl: 'Voer je boekingsreferentie in',
                        en: 'Enter your booking reference',
                        fr: 'Entrez votre reference',
                        es: 'Introduce tu referencia',
                      );
                    }
                    if (s.length < 4) {
                      return _t(
                        nl: 'Referentie lijkt te kort',
                        en: 'Reference looks too short',
                        fr: 'Reference trop courte',
                        es: 'La referencia es muy corta',
                      );
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _field(
                  label: _t(
                    nl: 'E-mail of telefoon (optioneel)',
                    en: 'Email or phone (optional)',
                    fr: 'E-mail ou telephone (optionnel)',
                    es: 'Email o telefono (opcional)',
                  ),
                  controller: _contactCtrl,
                  hintText: _t(
                    nl: 'Extra controle op je gegevens',
                    en: 'Extra check against your details',
                    fr: 'Verification supplementaire',
                    es: 'Verificacion adicional',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4B4)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.search),
                  label: Text(
                    _busy
                        ? _t(
                            nl: 'Zoeken...',
                            en: 'Searching...',
                            fr: 'Recherche...',
                            es: 'Buscando...',
                          )
                        : _t(
                            nl: 'Zoek mijn boeking',
                            en: 'Find my booking',
                            fr: 'Trouver ma reservation',
                            es: 'Buscar mi reserva',
                          ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5B641),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
