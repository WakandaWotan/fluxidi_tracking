part of '../main.dart';

enum _ReceiptPaymentStatus { pending, sent, paid }

enum _ReceiptQuickAction { viewPdf, sharePdf, whatsappPdf, emailPdf, printPdf }

class _ReceiptPdfBundle {
  final Uint8List bytes;
  final File file;

  const _ReceiptPdfBundle({required this.bytes, required this.file});
}

class _ReceiptPdfActionRunner {
  static String _resolveBookingIdForInvoicePdf(_TripHistoryItem item) {
    final direct = (item.bookingId ?? '').trim();
    if (direct.isNotEmpty) return direct;
    return (_firstPathText(item, const [
              ['booking_id'],
              ['bookingId'],
              ['id'],
              ['booking', 'booking_id'],
              ['booking', 'bookingId'],
              ['booking', 'id'],
              ['record', 'booking_id'],
              ['record', 'bookingId'],
              ['record', 'booking', 'booking_id'],
              ['record', 'booking', 'bookingId'],
              ['payload', 'booking_id'],
              ['payload', 'bookingId'],
              ['payload', 'booking', 'booking_id'],
              ['payload', 'booking', 'bookingId'],
            ]) ??
            '')
        .trim();
  }

  static Uri? _buildBackendInvoicePdfUri(_TripHistoryItem item) {
    final bookingId = _resolveBookingIdForInvoicePdf(item);
    if (bookingId.isEmpty) return null;
    return Uri.parse(
      '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/invoice/pdf',
    );
  }

  static Map<String, String> _backendInvoicePdfHeaders() {
    final headers = <String, String>{'Accept': 'application/pdf'};
    final admin = _adminHeaders();
    if (admin.isNotEmpty) {
      headers.addAll(admin);
      return headers;
    }

    final driverSessionToken =
        (activeDriverSessionNotifier.value?.driverSessionToken ?? '').trim();
    if (driverSessionToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $driverSessionToken';
      return headers;
    }

    final companySessionToken =
        (activeCompanySessionNotifier.value?.companySessionToken ?? '').trim();
    if (companySessionToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $companySessionToken';
    }

    return headers;
  }

  static Future<_ReceiptPdfBundle?> _tryFetchBackendInvoicePdfBundle({
    required _TripHistoryItem item,
    required String source,
  }) async {
    final uri = _buildBackendInvoicePdfUri(item);
    if (uri == null) {
      debugPrint('[PDF][BACKEND_FETCH][MISS] status=no_booking_id');
      return null;
    }
    debugPrint('[PDF][BACKEND_FETCH][START] source=$source');
    try {
      final response = await http
          .get(uri, headers: _backendInvoicePdfHeaders())
          .timeout(const Duration(seconds: 18));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        debugPrint('[PDF][BACKEND_FETCH][MISS] status=${response.statusCode}');
        return null;
      }
      final bytes = response.bodyBytes;
      final contentType = (response.headers['content-type'] ?? '')
          .trim()
          .toLowerCase();
      debugPrint('[PDF][BACKEND_FETCH][OK] contentType=$contentType');

      final tempDir = await getTemporaryDirectory();
      final receiptsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}fluxidi_receipts',
      );
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }

      final fileName = _sanitizeFilePart('${_customerReference(item)}_invoice');
      final file = File(
        '${receiptsDir.path}${Platform.pathSeparator}$fileName.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      return _ReceiptPdfBundle(bytes: bytes, file: file);
    } catch (err) {
      debugPrint('[PDF][BACKEND_FETCH][ERROR] $err');
      return null;
    }
  }

  static Future<void> previewReceiptPdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    // Allow backend invoice PDF fallback when a server-rendered artifact has
    // already been persisted (parity with sharePdf). Static layout still
    // serves as the in-app fallback when no backend artifact exists, and is
    // now driven by booking-hydrated data (see compliance register bridge).
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      if (!context.mounted) return;
      await _fallbackCopyText(context: context, item: item);
      return;
    }
    debugPrint('[PDF][ACTION][REGISTER_RECEIPT_VIEW] hasPdf=true');
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _receiptText('viewPdf'),
          bytes: bundle.bytes,
        ),
      ),
    );
  }

  static Future<void> previewInvoicePdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _tryFetchBackendInvoicePdfBundle(
      item: item,
      source: 'local_register_invoice',
    );
    if (bundle == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Geen factuur-PDF beschikbaar voor deze rit.',
              en: 'No invoice PDF available for this ride.',
              fr: 'Aucun PDF de facture disponible pour ce trajet.',
              es: 'No hay PDF de factura disponible para este viaje.',
            ),
          ),
        ),
      );
      return;
    }
    debugPrint('[PDF][ACTION][REGISTER_INVOICE_VIEW] hasPdf=true');
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _receiptText('viewPdf'),
          bytes: bundle.bytes,
        ),
      ),
    );
  }

  static Future<void> previewPdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      if (!context.mounted) return;
      await _fallbackCopyText(context: context, item: item);
      return;
    }
    debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_VIEW] hasPdf=true');
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReceiptPdfPreviewPage(
          title: _receiptText('viewPdf'),
          bytes: bundle.bytes,
        ),
      ),
    );
  }

  static Future<void> sharePdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      if (!context.mounted) return;
      await _fallbackCopyText(context: context, item: item);
      return;
    }
    debugPrint('[PDF][ACTION][CUSTOMER_DIRECT_SHARE] hasPdf=true');
    debugPrint('[PDF][ACTION][PDF_SHARE] hasPdf=true');
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: _receiptCustomerMessage(item),
      subject: _receiptText('receiptEmailSubject'),
    );
  }

  static Future<void> sharePdfViaWhatsApp({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      if (!context.mounted) return;
      await _fallbackWhatsAppText(context: context, item: item);
      return;
    }
    final contact = _resolvePdfContact(item);
    final phone = _normalizePhoneForWhatsApp(
      contact.phoneRaw,
      countryContext: _customerCountryContext(item),
    );
    final phoneFound = phone != null;
    const packageTarget = 'share_sheet';
    debugPrint(
      '[PDF][ACTION][WHATSAPP_PDF] phoneFound=$phoneFound hasPdf=true packageTarget=$packageTarget',
    );

    if (phoneFound && context.mounted) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Klantnummer gekopieerd. Kies WhatsApp en selecteer of plak de klant om de PDF te sturen.',
              en: 'Customer number copied. Choose WhatsApp and select or paste the customer to send the PDF.',
              fr: 'Numéro client copié. Choisissez WhatsApp puis sélectionnez ou collez le client pour envoyer le PDF.',
              es: 'Número del cliente copiado. Elija WhatsApp y seleccione o pegue el cliente para enviar el PDF.',
            ),
          ),
        ),
      );
    }

    final message = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );

    try {
      await Share.shareXFiles(
        <XFile>[XFile(bundle.file.path)],
        text: message,
        subject: _receiptText('whatsappPdf'),
      );
    } catch (_) {
      if (!context.mounted) return;
      await _fallbackWhatsAppText(context: context, item: item);
    }
  }

  static Future<void> sharePdfViaEmail({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final recipient = (contact.email ?? '').trim();
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      if (!context.mounted) return;
      await _fallbackEmailText(context: context, item: item);
      return;
    }
    final serverResult = await _sendReceiptEmailViaWorker(
      item: item,
      language: _currentLanguageCode(),
      source: 'flutter_receipt_button',
    );
    final serverStatus = (serverResult['status'] ?? '').toString();
    final serverOk = serverResult['ok'] == true;
    if (!context.mounted) return;
    if (serverOk && serverStatus == 'sent') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mail verzonden naar klant.',
              en: 'Email sent to customer.',
              fr: 'E-mail envoye au client.',
              es: 'Correo enviado al cliente.',
            ),
          ),
        ),
      );
      return;
    }
    if (serverOk && serverStatus == 'already_sent') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Factuur werd al verzonden.',
              en: 'Invoice was already sent.',
              fr: 'La facture a deja ete envoyee.',
              es: 'La factura ya fue enviada.',
            ),
          ),
        ),
      );
      return;
    }
    if (serverStatus == 'missing_email') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'Geen klantmail gevonden.',
              en: 'No customer email found.',
              fr: 'Aucun e-mail client trouve.',
              es: 'No se encontro correo del cliente.',
            ),
          ),
        ),
      );
      return;
    }
    if (!serverOk || serverStatus == 'skipped' || serverStatus == 'error') {
      debugPrint(
        '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=server_failed status=$serverStatus',
      );
      await _showEmailFallbackOptions(
        context: context,
        bundle: bundle,
        recipient: recipient,
        item: item,
      );
      return;
    }
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    if (recipient.isNotEmpty &&
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS)) {
      try {
        final email = Email(
          recipients: <String>[recipient],
          subject: _receiptText('receiptEmailSubject'),
          body: shortBody,
          attachmentPaths: <String>[bundle.file.path],
          isHTML: false,
        );
        await FlutterEmailSender.send(email);
        debugPrint(
          '[PDF][ACTION][EMAIL_PDF] emailFound=true hasPdf=true composer=native',
        );
        return;
      } catch (_) {
        // Fall through to share-sheet fallback.
      }
    }
    debugPrint(
      '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=share_fallback',
    );
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: shortBody,
      subject: _receiptText('receiptEmailSubject'),
    );
    if (!context.mounted) return;
    if (recipient.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: recipient));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mailadres gekopieerd. Deel de PDF nu via de gekozen mail-app.',
              en: 'Email copied. Share the PDF now via the selected mail app.',
              fr: 'E-mail copié. Partagez maintenant le PDF via l’application e-mail choisie.',
              es: 'Correo copiado. Comparta ahora el PDF mediante la app de correo elegida.',
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noCustomerContact'))),
      );
    }
  }

  static Future<void> printPdf({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final bundle = await _buildReceiptPdfBundle(context: context, item: item);
    if (bundle == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('printLater'))));
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => bundle.bytes);
  }

  static Future<void> _fallbackCopyText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    await Clipboard.setData(ClipboardData(text: _receiptCustomerMessage(item)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_receiptText('receiptCopied'))));
  }

  static Future<void> _fallbackWhatsAppText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final phone = _normalizePhoneForWhatsApp(
      contact.phoneRaw,
      countryContext: _customerCountryContext(item),
    );
    debugPrint(
      '[PDF][ACTION][WHATSAPP_TEXT] phoneFound=${phone != null} source=${contact.source}',
    );
    if (phone == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noValidWhatsappPhone'))),
      );
      return;
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.https('wa.me', '/$digits', <String, String>{
      'text': _tr(
        nl: 'Beste klant, uw betaalbewijs/ritbon is klaar. Ik stuur de PDF zo meteen door.',
        en: 'Dear customer, your ride receipt is ready. I will send the PDF shortly.',
        fr: 'Cher client, votre reçu de course est prêt. Je vais envoyer le PDF dans un instant.',
        es: 'Estimado cliente, su comprobante de viaje está listo. Enviaré el PDF en un momento.',
      ),
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('whatsappOpenFailed'))),
      );
    }
  }

  static Future<void> _fallbackEmailText({
    required BuildContext context,
    required _TripHistoryItem item,
  }) async {
    final contact = _resolvePdfContact(item);
    final recipient = (contact.email ?? '').trim();
    final encodedSubject = Uri.encodeComponent(
      _receiptText('receiptEmailSubject'),
    );
    final encodedBody = Uri.encodeComponent(_receiptCustomerMessage(item));
    final uri = Uri.parse(
      recipient.isNotEmpty
          ? 'mailto:${Uri.encodeComponent(recipient)}?subject=$encodedSubject&body=$encodedBody'
          : 'mailto:?subject=$encodedSubject&body=$encodedBody',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_receiptText('emailOpenFailed'))));
    }
  }

  static Future<Map<String, dynamic>> _sendReceiptEmailViaWorker({
    required _TripHistoryItem item,
    required String language,
    required String source,
  }) async {
    final bookingId = (item.bookingId ?? '').trim().isNotEmpty
        ? (item.bookingId ?? '').trim()
        : (_firstPathText(item, const [
                    ['booking_id'],
                    ['bookingId'],
                    ['id'],
                    ['booking', 'booking_id'],
                    ['booking', 'bookingId'],
                    ['booking', 'id'],
                    ['record', 'booking_id'],
                    ['record', 'bookingId'],
                    ['record', 'booking', 'booking_id'],
                    ['record', 'booking', 'bookingId'],
                    ['record', 'booking', 'id'],
                    ['payload', 'booking_id'],
                    ['payload', 'bookingId'],
                    ['payload', 'booking', 'booking_id'],
                    ['payload', 'booking', 'bookingId'],
                    ['public_reference'],
                    ['publicReference'],
                    ['receipt_reference'],
                    ['receiptReference'],
                    ['booking', 'public_reference'],
                    ['booking', 'publicReference'],
                    ['booking', 'receipt_reference'],
                    ['booking', 'receiptReference'],
                  ]) ??
                  '')
              .trim();
    if (bookingId.isEmpty) {
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': 'Missing booking id',
      };
    }
    final uri = Uri.parse(
      '$kBookingBaseUrl/bookings/${Uri.encodeComponent(bookingId)}/receipt/email',
    );
    final payload = <String, dynamic>{
      'manual': true,
      'language': _normalizeLanguageCode(language),
      'source': source,
    };
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ..._adminHeaders(),
    };
    try {
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(res.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': 'Unexpected server response',
      };
    } catch (err) {
      return <String, dynamic>{
        'ok': false,
        'status': 'error',
        'message': err.toString(),
      };
    }
  }

  static Future<void> _showEmailFallbackOptions({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: Text(
                _tr(
                  nl: 'Open mail-app',
                  en: 'Open mail app',
                  fr: 'Ouvrir app e-mail',
                  es: 'Abrir app de correo',
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('open_mail'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(
                _tr(
                  nl: 'Deel PDF',
                  en: 'Share PDF',
                  fr: 'Partager le PDF',
                  es: 'Compartir PDF',
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('share_pdf'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'open_mail') {
      await _openMailComposerFallback(
        context: context,
        bundle: bundle,
        recipient: recipient,
        item: item,
      );
      return;
    }
    await _sharePdfFallback(
      context: context,
      bundle: bundle,
      recipient: recipient,
      item: item,
    );
  }

  static Future<void> _openMailComposerFallback({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final email = Email(
          recipients: recipient.isNotEmpty
              ? <String>[recipient]
              : const <String>[],
          subject: _receiptText('receiptEmailSubject'),
          body: shortBody,
          attachmentPaths: <String>[bundle.file.path],
          isHTML: false,
        );
        await FlutterEmailSender.send(email);
        debugPrint(
          '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=native',
        );
        return;
      } catch (_) {
        // Fall through to share fallback.
      }
    }
    if (!context.mounted) return;
    await _sharePdfFallback(
      context: context,
      bundle: bundle,
      recipient: recipient,
      item: item,
    );
  }

  static Future<void> _sharePdfFallback({
    required BuildContext context,
    required _ReceiptPdfBundle bundle,
    required String recipient,
    required _TripHistoryItem item,
  }) async {
    final shortBody = _tr(
      nl: 'Beste klant, in bijlage vindt u uw betaalbewijs/ritbon (PDF).',
      en: 'Dear customer, your ride receipt PDF is attached.',
      fr: 'Cher client, votre reçu de course PDF est en pièce jointe.',
      es: 'Estimado cliente, su comprobante de viaje en PDF está adjunto.',
    );
    debugPrint(
      '[PDF][ACTION][EMAIL_PDF] emailFound=${recipient.isNotEmpty} hasPdf=true composer=share_fallback',
    );
    await Share.shareXFiles(
      <XFile>[XFile(bundle.file.path)],
      text: shortBody,
      subject: _receiptText('receiptEmailSubject'),
    );
    if (!context.mounted) return;
    if (recipient.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: recipient));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              nl: 'E-mailadres gekopieerd. Deel de PDF nu via de gekozen mail-app.',
              en: 'Email copied. Share the PDF now via the selected mail app.',
              fr: 'E-mail copie. Partagez maintenant le PDF via l app e-mail choisie.',
              es: 'Correo copiado. Comparta ahora el PDF mediante la app de correo elegida.',
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiptText('noCustomerContact'))),
      );
    }
  }

  static String _normalizeLanguageCode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'nl' ||
        normalized == 'en' ||
        normalized == 'fr' ||
        normalized == 'es') {
      return normalized;
    }
    return 'nl';
  }

  static String _currentLanguageCode() {
    switch (appConfig.currentLanguage) {
      case AppLanguage.en:
        return 'en';
      case AppLanguage.fr:
        return 'fr';
      case AppLanguage.es:
        return 'es';
      case AppLanguage.nl:
        return 'nl';
    }
  }

  static Future<_ReceiptPdfBundle?> _buildReceiptPdfBundle({
    required BuildContext context,
    required _TripHistoryItem item,
    bool skipBackendInvoice = false,
  }) async {
    if (!skipBackendInvoice) {
      final backendBundle = await _tryFetchBackendInvoicePdfBundle(
        item: item,
        source: 'receipt_pdf_bundle_static_layout',
      );
      if (backendBundle != null) return backendBundle;
    }
    try {
      final smartRef = _businessReferenceDisplayForItem(
        item,
        source: 'receipt_pdf_bundle_static_layout',
      );
      final contact = _resolvePdfContact(item);
      final keyList = contact.keys.join(',');
      debugPrint(
        '[PDF][CONTACT] emailFound=${contact.email != null} phoneFound=${contact.phoneRaw != null} source=${contact.source} keys=$keyList',
      );
      final route = _resolveRoute(item);
      debugPrint(
        '[PDF][ROUTE] fromFound=${route.from != _receiptText('currentLocation')} toFound=${route.to != '-'} source=${route.source}',
      );

      final seller = await _buildSellerProfile();
      final logoBytes = await _loadReceiptLogoBytes(seller['logoPath']);
      final doc = pw.Document();
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      final amounts = _resolvedReceiptAmounts(item);
      final paymentStatusRaw = _firstPathText(item, const [
        ['payment_status'],
        ['paymentStatus'],
        ['booking', 'payment_status'],
        ['booking', 'paymentStatus'],
        ['mollie', 'status'],
        ['record', 'mollie', 'status'],
      ]);
      final paymentProviderRaw = _firstPathText(item, const [
        ['payment_provider'],
        ['paymentProvider'],
        ['booking', 'payment_provider'],
        ['booking', 'paymentProvider'],
      ]);
      final paymentMethodRaw = _firstPathText(item, const [
        ['payment_method'],
        ['paymentMethod'],
        ['booking', 'payment_method'],
        ['booking', 'paymentMethod'],
      ]);
      final paymentSourceRaw = _firstPathText(item, const [
        ['payment_source'],
        ['paymentSource'],
        ['booking', 'payment_source'],
        ['booking', 'paymentSource'],
      ]);
      final paymentMethod = _localizedPaymentMethodValue(
        _paymentFieldWithMolliePaidFallback(
          value: paymentMethodRaw,
          paymentStatus: paymentStatusRaw,
          paymentProvider: paymentProviderRaw,
        ),
      );
      final paymentSource = _localizedPaymentSourceValue(
        _paymentFieldWithMolliePaidFallback(
          value: paymentSourceRaw,
          paymentStatus: paymentStatusRaw,
          paymentProvider: paymentProviderRaw,
        ),
      );
      final projection = _roundtripProjectionForPdf(item);
      final completedRoundtripReceipt = _isCompletedRoundtripProjection(
        projection,
      );
      final rideDateText = () {
        final activePickup = projection?['active_pickup_iso']
            ?.toString()
            .trim();
        if (activePickup != null && activePickup.isNotEmpty) {
          return _formatDate(activePickup);
        }
        return _firstPathText(item, const [
                  ['scheduled_pickup_at'],
                  ['booking', 'scheduled_pickup_at'],
                ]) !=
                null
            ? _formatDate(
                _firstPathText(item, const [
                  ['scheduled_pickup_at'],
                  ['booking', 'scheduled_pickup_at'],
                ]),
              )
            : _formatDate(item.startedAt);
      }();
      final serviceText = _displayServiceToken(
        _firstPathText(item, const [
          ['service_type'],
          ['booking', 'service_type'],
        ]),
      );
      final tierText = _displayTierToken(
        _firstPathText(item, const [
          ['tier'],
          ['booking', 'tier'],
        ]),
      );
      final durationText =
          _minutesText(
            _firstPathDouble(item, 'duration_route_min') ??
                _firstPathDouble(item, 'route_minutes'),
          ) ??
          _receiptText('notAvailable');
      final receiptLegType =
          _firstPathText(item, const [
            ['leg_type'],
            ['legType'],
            ['booking_details', 'leg_type'],
            ['booking_details', 'legType'],
          ]) ??
          '';
      if (receiptLegType.trim().isNotEmpty) {
        debugPrint(
          '[ROUNDTRIP_LEG_UI][RECEIPT_LEG_ONLY] booking=${_safeRefPreview(item.bookingId ?? item.tripId)} leg_type=${receiptLegType.trim()} route_source=${route.source}',
        );
      }
      final businessFields = _resolveBusinessFields(item);
      debugPrint(
        '[RECEIPT][BUSINESS_FIELDS] source=static_pdf booking=${_safeRefPreview(item.bookingId ?? item.tripId)} business=${businessFields.isBusinessDocument} invoiceRequested=${businessFields.invoiceRequested} companyFound=${businessFields.companyName.isNotEmpty} vatFound=${businessFields.vatNumber.isNotEmpty} invoiceEmailFound=${businessFields.invoiceEmail.isNotEmpty} invoiceAddressFound=${businessFields.invoiceAddress.isNotEmpty}',
      );
      // #region agent log H4 static receipt business projection
      unawaited(
        _agentDebugLog(
          runId: 'initial',
          hypothesisId: 'H4',
          location: 'main.dart:_ReceiptPdfActionRunner._buildReceiptPdfBundle',
          message: '[RECEIPT][BUSINESS_FIELDS]',
          data: <String, dynamic>{
            'source': 'static_pdf',
            'booking': _safeRefPreview(item.bookingId ?? item.tripId),
            'business': businessFields.isBusinessDocument,
            'invoiceRequested': businessFields.invoiceRequested,
            'companyFound': businessFields.companyName.isNotEmpty,
            'vatFound': businessFields.vatNumber.isNotEmpty,
            'invoiceEmailFound': businessFields.invoiceEmail.isNotEmpty,
            'invoiceAddressFound': businessFields.invoiceAddress.isNotEmpty,
          },
        ),
      );
      // #endregion
      final documentTitle = businessFields.isBusinessDocument
          ? _receiptText('invoiceLabel')
          : _receiptText('paymentReceiptLabel');
      final footerText = seller['footer']?.trim().isNotEmpty == true
          ? seller['footer']!.trim()
          : _receiptText('pdfFooterDefault');

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (pw.Context pdfContext) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoBytes != null)
                  pw.Container(
                    width: 82,
                    height: 82,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        seller['companyName'] ?? kCompanyName,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: boldFont,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                      if ((seller['legalName'] ?? '').trim().isNotEmpty &&
                          seller['legalName'] != seller['companyName'])
                        pw.Text(
                          seller['legalName']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['address'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          seller['address']!,
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['vatNumber'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyVat')}: ${seller['vatNumber']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['phone'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyPhone')}: ${seller['phone']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['email'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyEmail')}: ${seller['email']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                      if ((seller['website'] ?? '').trim().isNotEmpty)
                        pw.Text(
                          '${_receiptText('companyWebsite')}: ${seller['website']!}',
                          textAlign: pw.TextAlign.right,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              documentTitle,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 10),
            _pdfInfoRow(smartRef.label, smartRef.value),
            _pdfInfoRow(_receiptText('date'), rideDateText),
            _pdfInfoRow(_receiptText('type'), item.kindLabel),
            _pdfInfoRow(_receiptText('service'), serviceText),
            _pdfInfoRow(_receiptText('tier'), tierText),
            if (completedRoundtripReceipt)
              ..._completedRoundtripPdfRows(item, boldFont)
            else ...[
              _pdfInfoRow(_receiptText('from'), route.from),
              _pdfInfoRow(_receiptText('to'), route.to),
              ..._roundtripRouteNotePdfRows(item),
              _pdfInfoRow(_receiptText('distance'), _kmText(item)),
              _pdfInfoRow(_receiptText('duration'), durationText),
            ],
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('customerDetails'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('customerName'),
              contact.name ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerEmail'),
              contact.email ?? _receiptText('notAvailable'),
            ),
            _pdfInfoRow(
              _receiptText('customerPhone'),
              contact.phoneRaw ?? _receiptText('notAvailable'),
            ),
            if (businessFields.isBusinessDocument) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                _tr(
                  nl: 'Zakelijk / Factuur',
                  en: 'Business / Invoice',
                  fr: 'Professionnel / Facture',
                  es: 'Empresa / Factura',
                ),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                ),
              ),
              pw.SizedBox(height: 6),
              _pdfInfoRow(
                _tr(
                  nl: 'Bedrijfsnaam',
                  en: 'Company name',
                  fr: "Nom de l'entreprise",
                  es: 'Empresa',
                ),
                businessFields.companyName.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.companyName,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'BTW-nummer',
                  en: 'VAT number',
                  fr: 'Numero de TVA',
                  es: 'NIF/IVA',
                ),
                businessFields.vatNumber.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.vatNumber,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'Factuur e-mail',
                  en: 'Invoice email',
                  fr: 'E-mail facture',
                  es: 'Email de factura',
                ),
                businessFields.invoiceEmail.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.invoiceEmail,
              ),
              _pdfInfoRow(
                _tr(
                  nl: 'Factuuradres',
                  en: 'Invoice address',
                  fr: 'Adresse de facturation',
                  es: 'Direccion de factura',
                ),
                businessFields.invoiceAddress.isEmpty
                    ? _receiptText('notAvailable')
                    : businessFields.invoiceAddress,
              ),
            ],
            pw.SizedBox(height: 12),
            pw.Text(
              _receiptText('paymentActions'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: boldFont,
              ),
            ),
            pw.SizedBox(height: 6),
            _pdfInfoRow(
              _receiptText('paymentStatus'),
              _paymentStatusText(item),
            ),
            _pdfInfoRow(_receiptText('paymentMethod'), paymentMethod),
            _pdfInfoRow(_receiptText('paymentSource'), paymentSource),
            ..._roundtripProjectionPdfRows(item, boldFont),
            pw.Divider(color: PdfColors.grey400),
            _pdfInfoRow(
              _receiptText('subtotalExVat'),
              '€ ${amounts.subtotal.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              '${_receiptText('vatAmount')} (${(amounts.vatRate * 100).toStringAsFixed(0)}%)',
              '€ ${amounts.vatAmount.toStringAsFixed(2)}',
            ),
            _pdfInfoRow(
              _receiptText('total'),
              '€ ${amounts.total.toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              footerText,
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ],
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        ),
      );

      final bytes = await doc.save();
      final tempDir = await getTemporaryDirectory();
      final receiptsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}fluxidi_receipts',
      );
      if (!await receiptsDir.exists()) {
        await receiptsDir.create(recursive: true);
      }
      final fileName = _sanitizeFilePart(_customerReference(item));
      final file = File(
        '${receiptsDir.path}${Platform.pathSeparator}$fileName.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      return _ReceiptPdfBundle(bytes: bytes, file: file);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_receiptText('pdfGenerationFailed'))),
        );
      }
      return null;
    }
  }

  static ({String from, String to, String source}) _resolveRoute(
    _TripHistoryItem item,
  ) {
    bool looksLikeMapLiteral(String? value) {
      if (value == null) return false;
      final trimmed = value.trim();
      if (trimmed.length < 2) return false;
      final start = trimmed[0];
      final end = trimmed[trimmed.length - 1];
      return (start == '{' && end == '}') || (start == '[' && end == ']');
    }

    bool isPlaceholder(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return true;
      if (text == '-' || text == '—') return true;
      if (looksLikeMapLiteral(text)) return true;
      final lower = text.toLowerCase();
      if (lower == _receiptText('currentLocation').toLowerCase()) return true;
      // Localized fallback labels from `_sanitizeCustomerFacingRouteLabel`
      // are NOT valid route values — they exist only to fill a void when no
      // actual address could be resolved. Treat them as placeholders so the
      // wider path-based picker can still surface the real requested-booking
      // address for planned/online bookings.
      if (lower == _receiptStartPointFallback().toLowerCase()) return true;
      if (lower == _receiptStartLocationFallback().toLowerCase()) return true;
      return false;
    }

    String? routeFromValue(dynamic value) {
      if (value == null) return null;
      if (value is String) {
        final cleaned = _cleanContactText(value);
        if (cleaned == null) return null;
        if (isPlaceholder(cleaned)) return null;
        return cleaned;
      }
      if (value is Map) {
        for (final key in const <String>[
          'label',
          'address',
          'formatted_address',
          'formattedAddress',
          'name',
          'text',
          'value',
        ]) {
          final inner = value[key];
          if (inner is String) {
            final cleaned = _cleanContactText(inner);
            if (cleaned == null) continue;
            if (isPlaceholder(cleaned)) continue;
            return cleaned;
          }
        }
        return null;
      }
      if (value is Iterable) return null;
      final cleaned = _cleanContactText(value);
      if (cleaned == null) return null;
      if (isPlaceholder(cleaned)) return null;
      return cleaned;
    }

    String? pickLabel(List<List<String>> paths) {
      for (final path in paths) {
        final raw = _detailAt(item, path);
        final text = routeFromValue(raw);
        if (text != null) return text;
      }
      return null;
    }

    final roundtripProjection = _detailMap(item, 'roundtrip_price_projection');
    if (roundtripProjection != null && roundtripProjection.isNotEmpty) {
      final activeFrom = routeFromValue(roundtripProjection['active_from']);
      final activeTo = routeFromValue(roundtripProjection['active_to']);
      if (activeFrom != null && activeTo != null) {
        return (from: activeFrom, to: activeTo, source: 'roundtrip_active_leg');
      }
    }

    final normalizedFrom = isPlaceholder(item.origin)
        ? null
        : item.origin.trim();
    final normalizedTo = isPlaceholder(item.destination)
        ? null
        : item.destination.trim();
    final rawFrom = pickLabel(const [
      // Top-level mirrored by the hydration bridge — strongest signal.
      ['from'],
      ['pickup'],
      ['origin'],
      ['pickup_address'],
      ['pickupAddress'],
      ['pickup_from'],
      ['pickupFrom'],
      ['pickup_label'],
      ['pickupLabel'],
      ['requested_from'],
      ['requestedFrom'],
      ['pickupLocation'],
      ['pickup_location'],
      ['start_address'],
      ['startAddress'],
      // Booking subtree (requested booking route).
      ['booking', 'from'],
      ['booking', 'pickup'],
      ['booking', 'origin'],
      ['booking', 'pickup_address'],
      ['booking', 'pickupAddress'],
      ['booking', 'pickup_from'],
      ['booking', 'pickupFrom'],
      ['booking', 'pickup_label'],
      ['booking', 'pickupLabel'],
      ['booking', 'requested_from'],
      ['booking', 'requestedFrom'],
      // Authoritative record subtree returned by /bookings/{id}.
      ['record', 'from'],
      ['record', 'pickup'],
      ['record', 'origin'],
      ['record', 'pickup_address'],
      ['record', 'pickup_from'],
      ['record', 'pickup_label'],
      ['record', 'requested_from'],
      ['record', 'requestedFrom'],
      ['record', 'booking', 'from'],
      ['record', 'booking', 'pickup'],
      ['record', 'booking', 'origin'],
      ['record', 'booking', 'pickup_address'],
      ['record', 'booking', 'pickup_from'],
      // booking_details mirrors / nested.
      ['booking_details', 'from'],
      ['booking_details', 'pickup'],
      ['booking_details', 'origin'],
      ['booking_details', 'pickup_address'],
      ['record', 'booking_details', 'from'],
      ['record', 'booking_details', 'pickup'],
      ['record', 'booking_details', 'origin'],
      ['record', 'booking_details', 'pickup_address'],
      ['record', 'booking', 'booking_details', 'from'],
      ['record', 'booking', 'booking_details', 'pickup'],
      // Quote / payload (planned online bookings often originate here).
      ['quote', 'inputs', 'from'],
      ['quote', 'inputs', 'pickup'],
      ['record', 'quote', 'inputs', 'from'],
      ['record', 'quote', 'inputs', 'pickup'],
      ['payload', 'from'],
      ['payload', 'pickup'],
      ['payload', 'pickup_address'],
      ['payload', 'booking', 'from'],
      ['record', 'payload', 'from'],
      ['record', 'payload', 'pickup'],
      ['record', 'payload', 'pickup_address'],
    ]);
    final rawTo = pickLabel(const [
      ['to'],
      ['destination'],
      ['dropoff'],
      ['destination_address'],
      ['destinationAddress'],
      ['dropoff_address'],
      ['dropoffAddress'],
      ['dropoff_to'],
      ['dropoffTo'],
      ['dropoff_label'],
      ['dropoffLabel'],
      ['requested_to'],
      ['requestedTo'],
      ['end_address'],
      ['endAddress'],
      ['booking', 'to'],
      ['booking', 'destination'],
      ['booking', 'dropoff'],
      ['booking', 'destination_address'],
      ['booking', 'destinationAddress'],
      ['booking', 'dropoff_address'],
      ['booking', 'dropoffAddress'],
      ['booking', 'dropoff_to'],
      ['booking', 'dropoffTo'],
      ['booking', 'dropoff_label'],
      ['booking', 'dropoffLabel'],
      ['booking', 'requested_to'],
      ['booking', 'requestedTo'],
      ['record', 'to'],
      ['record', 'destination'],
      ['record', 'dropoff'],
      ['record', 'destination_address'],
      ['record', 'dropoff_address'],
      ['record', 'dropoff_to'],
      ['record', 'dropoff_label'],
      ['record', 'requested_to'],
      ['record', 'requestedTo'],
      ['record', 'booking', 'to'],
      ['record', 'booking', 'destination'],
      ['record', 'booking', 'dropoff'],
      ['record', 'booking', 'destination_address'],
      ['record', 'booking', 'dropoff_to'],
      ['booking_details', 'to'],
      ['booking_details', 'destination'],
      ['booking_details', 'dropoff'],
      ['booking_details', 'destination_address'],
      ['record', 'booking_details', 'to'],
      ['record', 'booking_details', 'destination'],
      ['record', 'booking_details', 'dropoff'],
      ['record', 'booking_details', 'destination_address'],
      ['record', 'booking', 'booking_details', 'to'],
      ['record', 'booking', 'booking_details', 'destination'],
      ['quote', 'inputs', 'to'],
      ['quote', 'inputs', 'destination'],
      ['record', 'quote', 'inputs', 'to'],
      ['record', 'quote', 'inputs', 'destination'],
      ['payload', 'to'],
      ['payload', 'destination'],
      ['payload', 'destination_address'],
      ['payload', 'booking', 'to'],
      ['record', 'payload', 'to'],
      ['record', 'payload', 'destination'],
      ['record', 'payload', 'destination_address'],
    ]);
    final from = _sanitizeCustomerFacingRouteLabel(
      normalizedFrom ?? rawFrom ?? _receiptText('currentLocation'),
      isFromField: true,
    );
    final to = _sanitizeCustomerFacingRouteLabel(
      normalizedTo ?? rawTo ?? '-',
      isFromField: false,
    );
    final source = (normalizedFrom != null || normalizedTo != null)
        ? 'normalized'
        : ((rawFrom != null || rawTo != null) ? 'raw' : 'fallback');
    return (from: from, to: to, source: source);
  }

  static _ResolvedPdfContact _resolvePdfContact(_TripHistoryItem item) {
    String? pick(
      List<List<String>> paths,
      List<String> usedKeys, {
      bool email = false,
    }) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(item, path));
        if (text == null || text.isEmpty) continue;
        final normalized = email ? _validEmail(text) : text;
        if (normalized == null || normalized.isEmpty) continue;
        usedKeys.add(path.join('.'));
        return normalized;
      }
      return null;
    }

    final keys = <String>[];
    final normalizedName = _cleanContactText(item.customerName);
    final normalizedPhone = _cleanContactText(item.customerPhone);
    final normalizedEmail = _validEmail(item.customerEmail);
    if (normalizedName != null) keys.add('normalized.customerName');
    if (normalizedPhone != null) keys.add('normalized.customerPhone');
    if (normalizedEmail != null) keys.add('normalized.customerEmail');
    final hasNormalized =
        normalizedName != null ||
        normalizedPhone != null ||
        normalizedEmail != null;
    if (hasNormalized) {
      return _ResolvedPdfContact(
        name: normalizedName,
        phoneRaw: normalizedPhone,
        email: normalizedEmail,
        keys: keys,
        source: 'normalized',
      );
    }

    final name = pick(const [
      ['customer', 'name'],
      ['customer_name'],
      ['customerName'],
      ['custName'],
      ['name'],
      ['booking', 'customer', 'name'],
      ['booking', 'customer_name'],
      ['booking', 'customerName'],
      ['booking', 'custName'],
      ['booking', 'name'],
      ['record', 'customer_name'],
      ['record', 'booking', 'customer_name'],
      ['record', 'booking', 'customerName'],
      ['payload', 'customer_name'],
      ['payload', 'booking', 'customer_name'],
      ['record', 'payload', 'customer_name'],
      ['record', 'payload', 'customerName'],
      ['record', 'payload', 'custName'],
      ['record', 'payload', 'name'],
      ['record', 'payload', 'booking', 'customer_name'],
      ['record', 'payload', 'booking', 'customerName'],
      ['record', 'payload', 'booking', 'custName'],
      ['record', 'payload', 'booking', 'name'],
    ], keys);

    final phoneRaw = pick(const [
      ['customer', 'phone'],
      ['customer_phone'],
      ['customerPhone'],
      ['custPhone'],
      ['phone'],
      ['tel'],
      ['mobile'],
      ['booking', 'customer', 'phone'],
      ['booking', 'customer_phone'],
      ['booking', 'customerPhone'],
      ['booking', 'custPhone'],
      ['booking', 'phone'],
      ['booking', 'tel'],
      ['booking', 'mobile'],
      ['record', 'customer_phone'],
      ['record', 'booking', 'customer_phone'],
      ['record', 'booking', 'customerPhone'],
      ['record', 'booking', 'custPhone'],
      ['payload', 'customer_phone'],
      ['payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'customer_phone'],
      ['record', 'payload', 'customerPhone'],
      ['record', 'payload', 'custPhone'],
      ['record', 'payload', 'phone'],
      ['record', 'payload', 'tel'],
      ['record', 'payload', 'mobile'],
      ['record', 'payload', 'booking', 'customer_phone'],
      ['record', 'payload', 'booking', 'customerPhone'],
      ['record', 'payload', 'booking', 'custPhone'],
      ['record', 'payload', 'booking', 'phone'],
    ], keys);

    final email = pick(
      const [
        ['customer', 'email'],
        ['customer_email'],
        ['customerEmail'],
        ['custEmail'],
        ['email'],
        ['invoice_email'],
        ['invoiceEmail'],
        ['booking', 'customer', 'email'],
        ['booking', 'customer_email'],
        ['booking', 'customerEmail'],
        ['booking', 'custEmail'],
        ['booking', 'email'],
        ['booking', 'invoice_email'],
        ['booking', 'invoiceEmail'],
        ['record', 'customer_email'],
        ['record', 'booking', 'customer_email'],
        ['record', 'booking', 'customerEmail'],
        ['record', 'booking', 'custEmail'],
        ['payload', 'customer_email'],
        ['payload', 'booking', 'customer_email'],
        ['record', 'payload', 'customer_email'],
        ['record', 'payload', 'customerEmail'],
        ['record', 'payload', 'custEmail'],
        ['record', 'payload', 'email'],
        ['record', 'payload', 'invoice_email'],
        ['record', 'payload', 'invoiceEmail'],
        ['record', 'payload', 'booking', 'customer_email'],
        ['record', 'payload', 'booking', 'customerEmail'],
        ['record', 'payload', 'booking', 'custEmail'],
        ['record', 'payload', 'booking', 'email'],
        ['record', 'payload', 'booking', 'invoice_email'],
        ['record', 'payload', 'booking', 'invoiceEmail'],
      ],
      keys,
      email: true,
    );

    final hasRaw = name != null || phoneRaw != null || email != null;
    return _ResolvedPdfContact(
      name: name,
      phoneRaw: phoneRaw,
      email: email,
      keys: keys,
      source: hasRaw ? 'raw' : 'none',
    );
  }

  static String? _customerCountryContext(_TripHistoryItem item) {
    final value = _firstPathText(item, const [
      ['phone_country_code'],
      ['phoneCountryCode'],
      ['dial_code'],
      ['dialCode'],
      ['customer_country'],
      ['customerCountry'],
      ['country'],
      ['countryCode'],
      ['country_iso'],
      ['countryIso'],
      ['locale'],
      ['language'],
    ]);
    if (value != null && value.trim().isNotEmpty) return value;
    if (kTenantId.toLowerCase().trim() == 'fluxidi') return 'BE';
    return null;
  }

  static dynamic _detailAt(_TripHistoryItem item, List<String> path) {
    dynamic current = item.bookingDetails;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        current = null;
        break;
      }
    }
    if (current != null) return current;
    current = item.rawSource;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  static String? _cleanContactText(dynamic value) {
    if (value == null) return null;
    // Defensive guard: never stringify Map/Iterable nodes. When path lookups
    // land on raw compliance/booking sub-trees (e.g. {label: ''}, {}, lists),
    // Dart's default toString() would surface "{}", "{label: }" or "[]" into
    // PDF route/contact fields. Treat those as "no scalar value found" so the
    // resolver can fall back to the next path. Route-aware extraction of
    // {label}/{lat,lon} happens upstream (e.g. _TripHistoryItem._placeLabel
    // and _TripHistoryItem._extractRouteLabel) before reaching this helper.
    if (value is Map || value is Iterable) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  static String? _firstPathText(
    _TripHistoryItem item,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      final text = _cleanContactText(_detailAt(item, path));
      if (text != null) return text;
    }
    return null;
  }

  static String? _validEmail(String? value) {
    final email = value?.trim();
    if (email == null || email.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return null;
    return email;
  }

  static String? _normalizePhoneForWhatsApp(
    String? raw, {
    String? countryContext,
  }) {
    final input = raw?.trim();
    if (input == null || input.isEmpty) return null;
    var cleaned = input.replaceAll(RegExp(r'[\s\-\(\)\/\.]'), '');
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned.startsWith('+')) {
      final digits = cleaned.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8 || digits.length > 15) return null;
      return '+$digits';
    }
    final digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) return null;

    final context = countryContext?.toUpperCase().trim() ?? '';
    if ((context == 'BE' || context == 'BELGIUM' || context.isEmpty) &&
        digits.startsWith('0') &&
        digits.length >= 9) {
      final national = digits.replaceFirst(RegExp(r'^0+'), '');
      if (national.isEmpty) return null;
      return '+32$national';
    }
    return null;
  }

  static String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  static double? _detailDouble(_TripHistoryItem item, String key) {
    final value = item.bookingDetails[key];
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }

  static double? _firstPathDouble(_TripHistoryItem item, String key) {
    final direct = _detailDouble(item, key);
    if (direct != null) return direct;
    final text = _firstPathText(item, <List<String>>[
      <String>[key],
      <String>['booking', key],
    ]);
    if (text == null) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  static bool _isPositiveAmount(double? value) =>
      value != null && value.isFinite && value > 0;

  static bool _isPlannedOperationalLegItem(_TripHistoryItem item) {
    if (item.kind.toLowerCase().trim() != 'planned') return false;
    final tripId = item.tripId.trim().toLowerCase();
    if (!tripId.startsWith('planned_')) return false;
    final legId = _firstPathText(item, const [
      ['leg_id'],
      ['legId'],
      ['booking_details', 'leg_id'],
      ['booking_details', 'legId'],
      ['booking', 'leg_id'],
      ['booking', 'legId'],
    ]);
    final legType = _firstPathText(item, const [
      ['leg_type'],
      ['legType'],
      ['booking_details', 'leg_type'],
      ['booking_details', 'legType'],
      ['booking', 'leg_type'],
      ['booking', 'legType'],
    ]);
    final rowKey = _firstPathText(item, const [
      ['row_key'],
      ['rowKey'],
      ['booking_details', 'row_key'],
      ['booking_details', 'rowKey'],
      ['booking', 'row_key'],
      ['booking', 'rowKey'],
    ]);
    return (legId?.trim().isNotEmpty ?? false) ||
        (legType?.trim().isNotEmpty ?? false) ||
        (rowKey?.trim().isNotEmpty ?? false);
  }

  static double? _effectiveOperationalLegAmount(_TripHistoryItem item) {
    if (!_isPlannedOperationalLegItem(item)) return null;
    final candidates = <double?>[
      item.totalEur,
      _detailDouble(item, 'segment_price_eur'),
      _firstPathDouble(item, 'segment_price_eur'),
      _detailDouble(item, 'leg_price_incl_vat'),
      _detailDouble(item, 'legPriceInclVat'),
      _firstPathDouble(item, 'leg_price_incl_vat'),
      _firstPathDouble(item, 'legPriceInclVat'),
    ];
    for (final candidate in candidates) {
      if (_isPositiveAmount(candidate)) return candidate;
    }
    return null;
  }

  static double? _receiptTotalAmount(_TripHistoryItem item) {
    if (item.kind.toLowerCase().trim() == 'planned') {
      final legAmount = _effectiveOperationalLegAmount(item);
      if (_isPositiveAmount(legAmount)) return legAmount;
      return _detailDouble(item, 'booking_total_eur') ?? item.totalEur;
    }
    return item.totalEur;
  }

  static String _moneyText(double? value) {
    if (value == null) return _receiptText('notAvailable');
    return '€ ${value.toStringAsFixed(2)}';
  }

  static String _totalText(_TripHistoryItem item) =>
      _moneyText(_receiptTotalAmount(item));

  static String _kmText(_TripHistoryItem item) {
    final km = item.kmTotal;
    if (km == null) return _receiptText('notAvailable');
    return '${km.toStringAsFixed(2)} km';
  }

  static String? _minutesText(double? value) {
    if (value == null) return null;
    return '${value.round()} min';
  }

  static ({
    bool isBusinessDocument,
    bool invoiceRequested,
    String companyName,
    String vatNumber,
    String invoiceEmail,
    String invoiceAddress,
  })
  _resolveBusinessFields(_TripHistoryItem item) {
    final invoiceRequested = _toBoolFlag(
      _firstPathText(item, const [
        ['invoice_requested'],
        ['invoiceRequested'],
        ['booking', 'invoice_requested'],
        ['booking', 'invoiceRequested'],
        ['booking_details', 'invoice_requested'],
        ['booking_details', 'invoiceRequested'],
        ['record', 'invoice_requested'],
        ['record', 'invoiceRequested'],
        ['record', 'booking', 'invoice_requested'],
        ['record', 'booking', 'invoiceRequested'],
        ['record', 'booking_details', 'invoice_requested'],
        ['record', 'booking_details', 'invoiceRequested'],
        ['payload', 'invoice_requested'],
        ['payload', 'invoiceRequested'],
        ['payload', 'booking', 'invoice_requested'],
        ['payload', 'booking', 'invoiceRequested'],
      ]),
    );
    final businessFlag = _toBoolFlag(
      _firstPathText(item, const [
        ['business_customer'],
        ['businessCustomer'],
        ['is_business'],
        ['isBusiness'],
        ['business_detected'],
        ['businessDetected'],
        ['booking', 'business_customer'],
        ['booking', 'businessCustomer'],
        ['booking', 'is_business'],
        ['booking', 'isBusiness'],
        ['booking', 'business_detected'],
        ['booking', 'businessDetected'],
        ['booking_details', 'business_customer'],
        ['booking_details', 'businessCustomer'],
        ['booking_details', 'is_business'],
        ['booking_details', 'isBusiness'],
        ['record', 'business_customer'],
        ['record', 'businessCustomer'],
        ['record', 'is_business'],
        ['record', 'isBusiness'],
        ['record', 'business_detected'],
        ['record', 'businessDetected'],
        ['record', 'booking', 'business_customer'],
        ['record', 'booking', 'businessCustomer'],
        ['record', 'booking', 'is_business'],
        ['record', 'booking', 'isBusiness'],
        ['record', 'booking', 'business_detected'],
        ['record', 'booking', 'businessDetected'],
      ]),
    );
    final customerCompany = _firstPathText(item, const [
      ['company_name'],
      ['companyName'],
      ['customer_company'],
      ['customerCompany'],
      ['booking', 'company_name'],
      ['booking', 'companyName'],
      ['booking_details', 'company_name'],
      ['booking_details', 'companyName'],
      ['record', 'company_name'],
      ['record', 'companyName'],
      ['record', 'booking', 'company_name'],
      ['record', 'booking', 'companyName'],
      ['record', 'booking_details', 'company_name'],
      ['record', 'booking_details', 'companyName'],
      ['payload', 'company_name'],
      ['payload', 'companyName'],
      ['payload', 'booking', 'company_name'],
      ['payload', 'booking', 'companyName'],
    ]);
    final customerVat = _firstPathText(item, const [
      ['vat_number'],
      ['vatNumber'],
      ['customer_vat'],
      ['customerVat'],
      ['booking', 'vat_number'],
      ['booking', 'vatNumber'],
      ['booking_details', 'vat_number'],
      ['booking_details', 'vatNumber'],
      ['record', 'vat_number'],
      ['record', 'vatNumber'],
      ['record', 'booking', 'vat_number'],
      ['record', 'booking', 'vatNumber'],
      ['record', 'booking_details', 'vat_number'],
      ['record', 'booking_details', 'vatNumber'],
      ['payload', 'vat_number'],
      ['payload', 'vatNumber'],
      ['payload', 'booking', 'vat_number'],
      ['payload', 'booking', 'vatNumber'],
    ]);
    final invoiceEmail =
        _firstPathText(item, const [
          ['invoice_email'],
          ['invoiceEmail'],
          ['booking', 'invoice_email'],
          ['booking', 'invoiceEmail'],
          ['booking_details', 'invoice_email'],
          ['booking_details', 'invoiceEmail'],
          ['record', 'invoice_email'],
          ['record', 'invoiceEmail'],
          ['record', 'booking', 'invoice_email'],
          ['record', 'booking', 'invoiceEmail'],
          ['record', 'booking_details', 'invoice_email'],
          ['record', 'booking_details', 'invoiceEmail'],
          ['payload', 'invoice_email'],
          ['payload', 'invoiceEmail'],
          ['payload', 'booking', 'invoice_email'],
          ['payload', 'booking', 'invoiceEmail'],
        ]) ??
        '';
    final invoiceAddress =
        _firstPathText(item, const [
          ['invoice_address'],
          ['invoiceAddress'],
          ['billing_address'],
          ['billingAddress'],
          ['company_address'],
          ['companyAddress'],
          ['booking', 'invoice_address'],
          ['booking', 'invoiceAddress'],
          ['booking', 'billing_address'],
          ['booking', 'billingAddress'],
          ['booking_details', 'invoice_address'],
          ['booking_details', 'invoiceAddress'],
          ['record', 'invoice_address'],
          ['record', 'invoiceAddress'],
          ['record', 'billing_address'],
          ['record', 'billingAddress'],
          ['record', 'booking', 'invoice_address'],
          ['record', 'booking', 'invoiceAddress'],
          ['record', 'booking_details', 'invoice_address'],
          ['record', 'booking_details', 'invoiceAddress'],
          ['payload', 'invoice_address'],
          ['payload', 'invoiceAddress'],
          ['payload', 'booking', 'invoice_address'],
          ['payload', 'booking', 'invoiceAddress'],
        ]) ??
        '';
    final hasBusiness =
        invoiceRequested ||
        businessFlag ||
        (customerCompany != null && customerCompany.trim().isNotEmpty) ||
        (customerVat != null && customerVat.trim().isNotEmpty);
    return (
      isBusinessDocument: hasBusiness,
      invoiceRequested: invoiceRequested,
      companyName: (customerCompany ?? '').trim(),
      vatNumber: (customerVat ?? '').trim(),
      invoiceEmail: invoiceEmail.trim(),
      invoiceAddress: invoiceAddress.trim(),
    );
  }

  static bool _isBusinessDocument(_TripHistoryItem item) {
    return _resolveBusinessFields(item).isBusinessDocument;
  }

  static bool _toBoolFlag(String? value) {
    final normalized = value?.toLowerCase().trim() ?? '';
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'ja';
  }

  static Map<String, dynamic>? _roundtripProjectionForPdf(
    _TripHistoryItem item,
  ) {
    final explicit = _detailMap(item, 'roundtrip_price_projection');
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return _deriveCompletedRoundtripProjectionForPdf(item);
  }

  static Map<String, dynamic>? _deriveCompletedRoundtripProjectionForPdf(
    _TripHistoryItem item,
  ) {
    String? pickText(List<List<String>> paths) => _firstPathText(item, paths);

    double? pickAmount(List<List<String>> paths) {
      for (final path in paths) {
        final raw = _detailAt(item, path);
        if (raw is num) return raw.toDouble();
        final text = _cleanContactText(raw);
        if (text == null) continue;
        final parsed = double.tryParse(text.replaceAll(',', '.'));
        if (parsed != null && parsed.isFinite) return parsed;
      }
      return null;
    }

    bool paidValue(String? raw) {
      final token = raw?.trim().toLowerCase() ?? '';
      return token == 'paid' ||
          token == 'settled' ||
          token == 'confirmed' ||
          token == 'completed' ||
          token == 'success' ||
          token == 'true';
    }

    final statusRaw = item.status.trim().isNotEmpty
        ? item.status
        : (pickText(const [
                ['status'],
                ['booking_status'],
                ['bookingStatus'],
                ['booking', 'status'],
                ['record', 'status'],
                ['record', 'booking', 'status'],
              ]) ??
              '');
    final statusToken = statusRaw.trim().toUpperCase();
    final completed =
        statusToken == 'COMPLETED' ||
        statusToken == 'STOPPED' ||
        statusToken == 'FINISHED';
    final paid = paidValue(
      pickText(const [
        ['payment_status'],
        ['paymentStatus'],
        ['payment_state'],
        ['paymentState'],
        ['paid'],
        ['is_paid'],
        ['isPaid'],
        ['booking', 'payment_status'],
        ['booking', 'paymentStatus'],
        ['record', 'payment_status'],
        ['record', 'paymentStatus'],
        ['record', 'booking', 'payment_status'],
        ['record', 'booking', 'paymentStatus'],
      ]),
    );
    if (!completed || !paid) return null;

    final outboundPrice = pickAmount(const [
      ['price_incl_vat_main'],
      ['priceInclVatMain'],
      ['outbound_price_eur'],
      ['booking', 'price_incl_vat_main'],
      ['booking', 'outbound_price_eur'],
      ['record', 'price_incl_vat_main'],
      ['record', 'outbound_price_eur'],
      ['record', 'booking', 'price_incl_vat_main'],
    ]);
    final returnPrice = pickAmount(const [
      ['price_incl_vat_return'],
      ['priceInclVatReturn'],
      ['return_price_eur'],
      ['booking', 'price_incl_vat_return'],
      ['booking', 'return_price_eur'],
      ['record', 'price_incl_vat_return'],
      ['record', 'return_price_eur'],
      ['record', 'booking', 'price_incl_vat_return'],
    ]);
    if (outboundPrice == null || returnPrice == null || returnPrice <= 0) {
      return null;
    }

    Map<String, dynamic>? routeSegment(int index) {
      final raw = _detailAt(item, const ['route_segments']);
      if (raw is List && raw.length > index && raw[index] is Map) {
        return Map<String, dynamic>.from(raw[index] as Map);
      }
      return null;
    }

    String cleanRoute(dynamic raw) => _cleanContactText(raw) ?? '';
    ({String from, String to}) parseRouteText(String? raw) {
      final text = raw?.trim() ?? '';
      if (text.isEmpty) return (from: '', to: '');
      final parts = text
          .split(RegExp(r'\s*(?:→|->|=>| - )\s*'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (parts.length >= 2) return (from: parts.first, to: parts.last);
      return (from: text, to: '');
    }

    final route = _resolveRoute(item);
    final outboundSegment = routeSegment(0);
    final returnSegment = routeSegment(1);
    final returnRouteText = parseRouteText(
      pickText(const [
        ['return_route'],
        ['returnRoute'],
        ['booking', 'return_route'],
        ['booking', 'returnRoute'],
        ['record', 'return_route'],
        ['record', 'returnRoute'],
        ['record', 'booking', 'return_route'],
        ['record', 'booking', 'returnRoute'],
      ]),
    );
    final outboundFrom = cleanRoute(outboundSegment?['from']).isNotEmpty
        ? cleanRoute(outboundSegment?['from'])
        : route.from;
    final outboundTo = cleanRoute(outboundSegment?['to']).isNotEmpty
        ? cleanRoute(outboundSegment?['to'])
        : route.to;
    final returnFrom = cleanRoute(returnSegment?['from']).isNotEmpty
        ? cleanRoute(returnSegment?['from'])
        : (returnRouteText.from.isNotEmpty ? returnRouteText.from : outboundTo);
    final returnTo = cleanRoute(returnSegment?['to']).isNotEmpty
        ? cleanRoute(returnSegment?['to'])
        : (returnRouteText.to.isNotEmpty ? returnRouteText.to : outboundFrom);
    if (outboundFrom.isEmpty ||
        outboundTo.isEmpty ||
        returnFrom.isEmpty ||
        returnTo.isEmpty) {
      return null;
    }

    double? segmentAmount(Map<String, dynamic>? segment, String key) {
      final raw = segment?[key];
      if (raw is num) return raw.toDouble();
      return double.tryParse((raw ?? '').toString().replaceAll(',', '.'));
    }

    final bookedWait = pickAmount(const [
      ['booked_wait_minutes'],
      ['bookedWaitMinutes'],
      ['wait_min'],
      ['waitMin'],
      ['booking', 'booked_wait_minutes'],
      ['booking', 'wait_min'],
      ['record', 'booking', 'booked_wait_minutes'],
      ['record', 'booking', 'wait_min'],
    ]);
    final total =
        pickAmount(const [
          ['booking_total_eur'],
          ['total_eur'],
          ['total'],
          ['price_incl_vat'],
          ['booking', 'booking_total_eur'],
          ['booking', 'price_incl_vat'],
          ['record', 'booking', 'price_incl_vat'],
        ]) ??
        _receiptTotalAmount(item) ??
        (outboundPrice + returnPrice);
    final outboundPickup =
        pickText(const [
          ['scheduled_pickup_at'],
          ['booking', 'scheduled_pickup_at'],
        ]) ??
        item.startedAt;

    return <String, dynamic>{
      'display_mode': 'completed_roundtrip',
      'original_total_eur': total,
      'active_total_eur': total,
      'payable_total_eur': total,
      'paid': true,
      'active_leg_type': 'outbound',
      'active_from': outboundFrom,
      'active_to': outboundTo,
      'active_pickup_iso': outboundPickup,
      'outbound_from': outboundFrom,
      'outbound_to': outboundTo,
      'outbound_pickup_iso': outboundPickup,
      'outbound_price_incl_vat': outboundPrice,
      'outbound_status': 'COMPLETED',
      'outbound_distance_km': segmentAmount(outboundSegment, 'distance_km'),
      'outbound_duration_min': segmentAmount(outboundSegment, 'duration_min'),
      'return_from': returnFrom,
      'return_to': returnTo,
      'return_pickup_iso': pickText(const [
        ['return_scheduled_pickup_at'],
        ['return_pickup_iso'],
        ['returnPickupIso'],
        ['booking', 'return_scheduled_pickup_at'],
        ['booking', 'return_pickup_iso'],
        ['record', 'booking', 'return_scheduled_pickup_at'],
      ]),
      'return_price_incl_vat': returnPrice,
      'return_status': 'COMPLETED',
      'return_distance_km': segmentAmount(returnSegment, 'distance_km'),
      'return_duration_min': segmentAmount(returnSegment, 'duration_min'),
      'booked_wait_minutes': bookedWait,
      'waiting_package': bookedWait != null && bookedWait > 0,
    };
  }

  static bool _isCompletedRoundtripProjection(
    Map<String, dynamic>? projection,
  ) {
    final mode = (projection?['display_mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return mode == 'completed_roundtrip';
  }

  static String _projectionText(Map<String, dynamic> projection, String key) {
    final text = (projection[key] ?? '').toString().trim();
    return text.isEmpty ? _receiptText('notAvailable') : text;
  }

  static double? _projectionAmount(
    Map<String, dynamic> projection,
    String key,
  ) {
    final raw = projection[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse((raw ?? '').toString().replaceAll(',', '.'));
  }

  static String _roundtripReceiptStatusText(String raw) {
    final token = raw.trim().toUpperCase();
    if (token == 'COMPLETED' || token == 'COMPLETE' || token == 'FINISHED') {
      return _tr(
        nl: 'Voltooid',
        en: 'Completed',
        fr: 'Termine',
        es: 'Completado',
      );
    }
    if (token == 'CANCELLED' || token == 'CANCELED' || token == 'DELETED') {
      return _tr(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annule',
        es: 'Cancelado',
      );
    }
    if (token == 'PENDING' || token == 'PLANNED') {
      return _tr(
        nl: 'Gepland',
        en: 'Planned',
        fr: 'Planifie',
        es: 'Planificado',
      );
    }
    return raw.trim().isEmpty
        ? _receiptText('notAvailable')
        : _titleCaseToken(raw);
  }

  static List<pw.Widget> _completedRoundtripPdfRows(
    _TripHistoryItem item,
    pw.Font boldFont,
  ) {
    final projection = _roundtripProjectionForPdf(item);
    if (!_isCompletedRoundtripProjection(projection)) {
      return const <pw.Widget>[];
    }
    final p = projection!;
    final bookedWait = _projectionAmount(p, 'booked_wait_minutes');
    final outboundDistance = _projectionAmount(p, 'outbound_distance_km');
    final outboundDuration = _projectionAmount(p, 'outbound_duration_min');
    final returnDistance = _projectionAmount(p, 'return_distance_km');
    final returnDuration = _projectionAmount(p, 'return_duration_min');

    List<pw.Widget> legRows({
      required String title,
      required String pickupKey,
      required String fromKey,
      required String toKey,
      required String priceKey,
      required String statusKey,
      required double? distanceKm,
      required double? durationMin,
    }) {
      return <pw.Widget>[
        pw.SizedBox(height: 10),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            font: boldFont,
          ),
        ),
        pw.SizedBox(height: 4),
        _pdfInfoRow(
          _receiptText('date'),
          _formatDate(_projectionText(p, pickupKey)),
        ),
        _pdfInfoRow(_receiptText('from'), _projectionText(p, fromKey)),
        _pdfInfoRow(_receiptText('to'), _projectionText(p, toKey)),
        if (distanceKm != null)
          _pdfInfoRow(
            _receiptText('distance'),
            '${distanceKm.toStringAsFixed(2)} km',
          ),
        if (durationMin != null)
          _pdfInfoRow(_receiptText('duration'), _minutesText(durationMin)!),
        _pdfInfoRow(
          _tr(
            nl: 'Prijs incl. btw',
            en: 'Price incl. VAT',
            fr: 'Prix TVAC',
            es: 'Precio con IVA',
          ),
          _moneyText(_projectionAmount(p, priceKey)),
        ),
        _pdfInfoRow(
          _receiptText('rideStatus'),
          _roundtripReceiptStatusText(_projectionText(p, statusKey)),
        ),
      ];
    }

    return <pw.Widget>[
      pw.SizedBox(height: 12),
      pw.Text(
        _tr(
          nl: 'Heen-en-terug rit',
          en: 'Roundtrip ride',
          fr: 'Trajet aller-retour',
          es: 'Viaje de ida y vuelta',
        ),
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          font: boldFont,
        ),
      ),
      ...legRows(
        title: _tr(nl: 'Heenrit', en: 'Outbound', fr: 'Aller', es: 'Ida'),
        pickupKey: 'outbound_pickup_iso',
        fromKey: 'outbound_from',
        toKey: 'outbound_to',
        priceKey: 'outbound_price_incl_vat',
        statusKey: 'outbound_status',
        distanceKm: outboundDistance,
        durationMin: outboundDuration,
      ),
      ...legRows(
        title: _tr(nl: 'Terugrit', en: 'Return', fr: 'Retour', es: 'Regreso'),
        pickupKey: 'return_pickup_iso',
        fromKey: 'return_from',
        toKey: 'return_to',
        priceKey: 'return_price_incl_vat',
        statusKey: 'return_status',
        distanceKm: returnDistance,
        durationMin: returnDuration,
      ),
      if (bookedWait != null && bookedWait > 0) ...[
        pw.SizedBox(height: 8),
        _pdfInfoRow(
          _receiptText('bookedWaitingTime'),
          _minutesText(bookedWait)!,
        ),
        _pdfInfoRow(
          _tr(nl: 'Pakket', en: 'Package', fr: 'Forfait', es: 'Paquete'),
          _tr(
            nl: 'Heen-terug met geboekte wachttijd',
            en: 'Roundtrip with booked waiting time',
            fr: 'Aller-retour avec attente reservee',
            es: 'Ida y vuelta con espera reservada',
          ),
        ),
      ],
    ];
  }

  static List<pw.Widget> _roundtripRouteNotePdfRows(_TripHistoryItem item) {
    final projection = _roundtripProjectionForPdf(item);
    if (projection == null || projection.isEmpty) return const <pw.Widget>[];
    final cancelledLeg = (projection['cancelled_leg_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (cancelledLeg != 'outbound' && cancelledLeg != 'return') {
      return const <pw.Widget>[];
    }
    final note = cancelledLeg == 'return'
        ? _tr(
            nl: 'Terugrit geannuleerd — niet aangerekend',
            en: 'Return trip cancelled — not charged',
            fr: 'Retour annule — non facture',
            es: 'Regreso cancelado — no cobrado',
          )
        : _tr(
            nl: 'Heenrit geannuleerd — niet aangerekend',
            en: 'Outbound trip cancelled — not charged',
            fr: 'Aller annule — non facture',
            es: 'Ida cancelada — no cobrado',
          );
    return <pw.Widget>[
      pw.SizedBox(height: 4),
      pw.Text(
        note,
        style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
      ),
    ];
  }

  static List<pw.Widget> _roundtripProjectionPdfRows(
    _TripHistoryItem item,
    pw.Font boldFont,
  ) {
    final projection = _roundtripProjectionForPdf(item);
    if (projection == null || projection.isEmpty) return const <pw.Widget>[];

    double? readAmount(String key) {
      final raw = projection[key];
      if (raw is num) return raw.toDouble();
      return double.tryParse((raw ?? '').toString().replaceAll(',', '.'));
    }

    bool readBool(String key) {
      final raw = (projection[key] ?? '').toString().trim().toLowerCase();
      return raw == 'true' || raw == '1';
    }

    final displayMode = (projection['display_mode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final outbound = readAmount('outbound_price_incl_vat');
    final returnPrice = readAmount('return_price_incl_vat');
    final original = readAmount('original_total_eur');
    final cancelled = readAmount('cancelled_total_eur');
    final payable = readAmount('payable_total_eur');
    final active = readAmount('active_total_eur');
    final credit = readAmount('credit_due_total_eur');
    final paid = readBool('paid');
    final outboundCancelled = readBool('outbound_cancelled');
    final returnCancelled = readBool('return_cancelled');
    final activeLegType = (projection['active_leg_type'] ?? 'outbound')
        .toString()
        .trim()
        .toLowerCase();
    final activeLegPrice = activeLegType == 'return' ? returnPrice : outbound;

    if (displayMode == 'completed_roundtrip') {
      return const <pw.Widget>[];
    }

    if (displayMode == 'unpaid_simple') {
      return <pw.Widget>[
        pw.SizedBox(height: 8),
        if (activeLegPrice != null)
          _pdfInfoRow(
            activeLegType == 'return'
                ? _tr(
                    nl: 'Terugrit prijs incl. btw',
                    en: 'Return price incl. VAT',
                    fr: 'Prix retour TVAC',
                    es: 'Precio regreso con IVA',
                  )
                : _tr(
                    nl: 'Heenrit prijs incl. btw',
                    en: 'Outbound price incl. VAT',
                    fr: "Prix aller TVAC",
                    es: 'Precio ida con IVA',
                  ),
            _moneyText(activeLegPrice),
          ),
        _pdfInfoRow(
          _tr(
            nl: 'Te betalen in de wagen',
            en: 'Amount due',
            fr: 'A payer dans le vehicule',
            es: 'A pagar en el vehiculo',
          ),
          _moneyText(payable ?? active),
        ),
      ];
    }

    String amountWithCancelled(double? amount, bool cancelledLeg) {
      final base = _moneyText(amount);
      if (!cancelledLeg) return base;
      return '$base (${_tr(nl: 'Geannuleerd', en: 'Cancelled', fr: 'Annule', es: 'Cancelado')})';
    }

    return <pw.Widget>[
      pw.SizedBox(height: 8),
      pw.Text(
        _tr(
          nl: 'Heen-en-terug prijsopbouw',
          en: 'Roundtrip price breakdown',
          fr: 'Detail prix aller-retour',
          es: 'Desglose ida y vuelta',
        ),
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
          font: boldFont,
        ),
      ),
      pw.SizedBox(height: 4),
      _pdfInfoRow(
        _tr(nl: 'Heenrit', en: 'Outbound', fr: 'Aller', es: 'Ida'),
        amountWithCancelled(outbound, outboundCancelled),
      ),
      _pdfInfoRow(
        _tr(nl: 'Terugrit', en: 'Return', fr: 'Retour', es: 'Regreso'),
        amountWithCancelled(returnPrice, returnCancelled),
      ),
      if (original != null)
        _pdfInfoRow(
          _tr(
            nl: 'Totaal oorspronkelijk',
            en: 'Original total',
            fr: 'Total original',
            es: 'Total original',
          ),
          _moneyText(original),
        ),
      if (cancelled != null && cancelled > 0)
        _pdfInfoRow(
          _tr(
            nl: 'Geannuleerd bedrag',
            en: 'Cancelled amount',
            fr: 'Montant annule',
            es: 'Importe cancelado',
          ),
          '- ${_moneyText(cancelled)}',
        ),
      if (paid && credit != null && credit > 0)
        _pdfInfoRow(
          _tr(
            nl: 'Te crediteren',
            en: 'Credit due',
            fr: 'A crediter',
            es: 'A acreditar',
          ),
          _moneyText(credit),
        )
      else if ((active ?? 0) > 0)
        _pdfInfoRow(
          _tr(
            nl: 'Resterende ritwaarde',
            en: 'Remaining ride value',
            fr: 'Valeur restante du trajet',
            es: 'Valor restante del viaje',
          ),
          _moneyText(active),
        ),
    ];
  }

  static Map<String, dynamic>? _detailMap(_TripHistoryItem item, String key) {
    final raw = item.bookingDetails[key];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static ({double subtotal, double vatAmount, double total, double vatRate})
  _resolvedReceiptAmounts(_TripHistoryItem item) {
    final settingsVatRate = businessSettingsNotifier.value.pricingVatRate;
    final vatRateCandidates = <double?>[
      _detailDouble(item, 'vat_rate'),
      _detailDouble(item, 'vatRate'),
      _detailDouble(item, 'booking_vat_rate'),
      _detailDouble(item, 'bookingVatRate'),
    ];
    double vatRate = settingsVatRate.clamp(0.0, 1.0);
    for (final candidate in vatRateCandidates) {
      if (candidate == null || !candidate.isFinite) continue;
      if (candidate > 1.0) {
        vatRate = candidate / 100.0;
        break;
      }
      if (candidate >= 0.0) {
        vatRate = candidate;
        break;
      }
    }
    final total =
        _receiptTotalAmount(item) ??
        _detailDouble(item, 'total') ??
        _detailDouble(item, 'booking_total_eur') ??
        0.0;
    final subtotalCandidate =
        _detailDouble(item, 'subtotal_ex_vat') ??
        _detailDouble(item, 'subtotalExVat') ??
        _detailDouble(item, 'price_ex_vat') ??
        _detailDouble(item, 'priceExVat');
    final vatAmountCandidate =
        _detailDouble(item, 'vat_amount') ??
        _detailDouble(item, 'vatAmount') ??
        _detailDouble(item, 'price_vat') ??
        _detailDouble(item, 'priceVat');

    final subtotal =
        subtotalCandidate ?? (vatRate > 0 ? (total / (1.0 + vatRate)) : total);
    final vatAmount = vatAmountCandidate ?? (total - subtotal);
    return (
      subtotal: subtotal.isFinite ? subtotal : 0.0,
      vatAmount: vatAmount.isFinite ? vatAmount : 0.0,
      total: total.isFinite ? total : 0.0,
      vatRate: vatRate.isFinite ? vatRate : 0.0,
    );
  }

  static String _customerReference(_TripHistoryItem item) {
    return _businessReferenceDisplayForItem(
      item,
      source: 'receipt_pdf_bundle_static',
    ).value;
  }

  static String _localizedPaymentMethodValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'cash':
        return _tr(nl: 'Contant', en: 'Cash', fr: 'Espèces', es: 'Efectivo');
      case 'bancontact':
        return _tr(
          nl: 'Bancontact',
          en: 'Bancontact',
          fr: 'Bancontact',
          es: 'Bancontact',
        );
      case 'card':
        return _tr(nl: 'Kaart', en: 'Card', fr: 'Carte', es: 'Tarjeta');
      case 'qr':
      case 'qr_code':
        return _tr(
          nl: 'QR-code',
          en: 'QR code',
          fr: 'Code QR',
          es: 'Código QR',
        );
      case 'mollie':
        return _tr(
          nl: 'Online betaling',
          en: 'Online payment',
          fr: 'Paiement en ligne',
          es: 'Pago en línea',
        );
      default:
        return _titleCaseToken(value);
    }
  }

  static String _localizedPaymentSourceValue(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return _receiptText('notAvailable');
    final normalized = value
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'in_car':
        return _tr(
          nl: 'In de wagen',
          en: 'In vehicle',
          fr: 'Dans le véhicule',
          es: 'En el vehículo',
        );
      case 'payment_link':
        return _tr(
          nl: 'Betaallink',
          en: 'Payment link',
          fr: 'Lien de paiement',
          es: 'Enlace de pago',
        );
      case 'mollie':
        return _tr(nl: 'Mollie', en: 'Mollie', fr: 'Mollie', es: 'Mollie');
      default:
        return _titleCaseToken(value);
    }
  }

  static String _displayServiceToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'passenger' ||
        normalized == 'personenvervoer' ||
        normalized == 'passenger_transport') {
      return _receiptText('passengerTransport');
    }
    if (normalized == 'airport' ||
        normalized == 'airport_transfer' ||
        normalized == 'luchthaven') {
      return _receiptText('airportTransfer');
    }
    return _titleCaseToken(raw);
  }

  static String _displayTierToken(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = raw.toLowerCase().replaceAll('-', '_').trim();
    if (normalized == 'comfort') return _receiptText('tierComfort');
    if (normalized == 'private') return _receiptText('tierPrivate');
    if (normalized == 'premium') return _receiptText('tierPremium');
    return _titleCaseToken(raw);
  }

  static String _paymentStatusText(_TripHistoryItem item) {
    // Authoritative paid detection mirrors `_isEffectiveReceiptPaid` in the
    // on-screen receipt: when ANY payment-status alias, paid-boolean alias,
    // or `paid_at` timestamp signals settlement, the PDF must show "Paid".
    // Prevents the PDF from contradicting the compliance / local-register
    // payment authority that the on-screen receipt now respects.
    const paidStatusAliases = <List<String>>[
      ['payment_status'],
      ['paymentStatus'],
      ['payment_state'],
      ['paymentState'],
      ['paid'],
      ['is_paid'],
      ['isPaid'],
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['booking', 'payment_state'],
      ['booking', 'paymentState'],
      ['booking', 'paid'],
      ['booking', 'is_paid'],
      ['booking', 'isPaid'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'payment_state'],
      ['record', 'paymentState'],
      ['record', 'paid'],
      ['record', 'is_paid'],
      ['record', 'isPaid'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['record', 'booking', 'payment_state'],
      ['record', 'booking', 'paymentState'],
      ['record', 'booking', 'paid'],
      ['record', 'booking', 'is_paid'],
      ['record', 'booking', 'isPaid'],
      ['payment', 'status'],
      ['payment', 'paid'],
      ['booking', 'payment', 'status'],
      ['booking', 'payment', 'paid'],
      ['record', 'payment', 'status'],
      ['record', 'payment', 'paid'],
      ['record', 'booking', 'payment', 'status'],
      ['record', 'booking', 'payment', 'paid'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ];
    for (final path in paidStatusAliases) {
      final v = _firstPathText(item, [path])?.toLowerCase().trim();
      if (v == null) continue;
      if (v == 'paid' ||
          v == 'settled' ||
          v == 'confirmed' ||
          v == 'completed' ||
          v == 'success' ||
          v == 'true') {
        return _receiptText('paid');
      }
    }
    const paidAtAliases = <List<String>>[
      ['paid_at'],
      ['paidAt'],
      ['booking', 'paid_at'],
      ['booking', 'paidAt'],
      ['record', 'paid_at'],
      ['record', 'paidAt'],
      ['record', 'booking', 'paid_at'],
      ['record', 'booking', 'paidAt'],
    ];
    for (final path in paidAtAliases) {
      final t = _firstPathText(item, [path])?.trim();
      if (t != null && t.isNotEmpty && t != '—') return _receiptText('paid');
    }
    final raw = _firstPathText(item, const [
      ['payment_status'],
      ['paymentStatus'],
      ['booking', 'payment_status'],
      ['booking', 'paymentStatus'],
      ['record', 'payment_status'],
      ['record', 'paymentStatus'],
      ['record', 'booking', 'payment_status'],
      ['record', 'booking', 'paymentStatus'],
      ['mollie', 'status'],
      ['record', 'mollie', 'status'],
    ])?.toLowerCase().trim();
    if (raw == 'open' || raw == 'pending' || raw == 'authorized') {
      return _receiptText('paymentSent');
    }
    return _receiptText('unpaid');
  }

  static String _receiptCustomerMessage(_TripHistoryItem item) {
    final route = _resolveRoute(item);
    final lines = <String>[
      '${_receiptText('receiptFrom')} $kCompanyName',
      '${_receiptText('type')}: ${item.kindLabel}',
      '${_receiptText('reference')}: ${_customerReference(item)}',
      '${_receiptText('from')}: ${route.from}',
      '${_receiptText('to')}: ${route.to}',
      if (_firstPathText(item, const [
            ['scheduled_pickup_at'],
            ['booking', 'scheduled_pickup_at'],
          ]) !=
          null)
        '${_receiptText('scheduledPickup')}: ${_formatDate(_firstPathText(item, const [
          ['scheduled_pickup_at'],
          ['booking', 'scheduled_pickup_at'],
        ]))}',
      if (item.startedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('startTime')}: ${_formatDate(item.startedAt)}',
      if (item.stoppedAt?.trim().isNotEmpty ?? false)
        '${_receiptText('endTime')}: ${_formatDate(item.stoppedAt)}',
      '${_receiptText('distance')}: ${_kmText(item)}',
      '${_receiptText('total')}: ${_totalText(item)}',
      '${_receiptText('paymentStatus')}: ${_paymentStatusText(item)}',
      '',
      _receiptText('thanksRide'),
    ];
    return lines.join('\n');
  }

  static String _sanitizeFilePart(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return cleaned.isEmpty ? 'receipt' : cleaned;
  }

  static String _titleCaseToken(String value) {
    final normalized = value.trim().replaceAll('_', ' ').replaceAll('-', ' ');
    if (normalized.isEmpty) return '—';
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  static Future<Uint8List?> _loadReceiptLogoBytes(String? preferredPath) async {
    final candidates = <String>[
      if (preferredPath != null && preferredPath.trim().isNotEmpty)
        preferredPath.trim(),
      kFluxidiLogoAsset,
    ];
    for (final candidate in candidates) {
      try {
        if (candidate.startsWith('assets/')) {
          final data = await rootBundle.load(candidate);
          return data.buffer.asUint8List();
        }
        final f = File(candidate);
        if (await f.exists()) {
          return await f.readAsBytes();
        }
      } catch (_) {
        // Ignore and try next candidate.
      }
    }
    return null;
  }

  static Future<Map<String, String>> _buildSellerProfile() async {
    final settings = businessSettingsNotifier.value;
    BackendBusinessProfile? backendProfile;
    try {
      backendProfile = await fetchBackendBusinessProfile();
    } catch (_) {
      backendProfile = null;
    }
    final profile =
        backendProfile ??
        localBackendBusinessProfileNotifier.value ??
        BackendBusinessProfile.defaults();
    final postcodeCity = [
      profile.postcode.trim(),
      profile.city.trim(),
    ].where((e) => e.isNotEmpty).join(' ');
    final address = [
      profile.address.trim().isNotEmpty
          ? profile.address.trim()
          : settings.address.trim(),
      if (postcodeCity.isNotEmpty) postcodeCity,
      if (profile.country.trim().isNotEmpty) profile.country.trim(),
    ].where((e) => e.isNotEmpty).join('\n');

    final companyName = profile.companyName.trim().isNotEmpty
        ? profile.companyName.trim()
        : settings.companyName.trim().isNotEmpty
        ? settings.companyName.trim()
        : kCompanyName;
    final legalName = profile.legalName.trim().isNotEmpty
        ? profile.legalName.trim()
        : companyName;
    final profileJson = profile.toJson();
    String localizedFooterFromProfile(AppLanguage lang) {
      final localized = switch (lang) {
        AppLanguage.en =>
          (profileJson['invoiceReceiptFooterTextEn'] ?? '').toString().trim(),
        AppLanguage.fr =>
          (profileJson['invoiceReceiptFooterTextFr'] ?? '').toString().trim(),
        AppLanguage.es =>
          (profileJson['invoiceReceiptFooterTextEs'] ?? '').toString().trim(),
        _ =>
          (profileJson['invoiceReceiptFooterTextNl'] ?? '').toString().trim(),
      };
      return localized;
    }

    final hasAnyLocalizedFooter =
        (profileJson['invoiceReceiptFooterTextNl'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEn'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextFr'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        (profileJson['invoiceReceiptFooterTextEs'] ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    final appLang = appConfig.currentLanguage;
    final localizedFooter = localizedFooterFromProfile(appLang);
    final legacyFooter = profile.invoiceReceiptFooterText.trim();
    final footerText = localizedFooter.isNotEmpty
        ? localizedFooter
        : (legacyFooter.isNotEmpty &&
              (appLang == AppLanguage.nl || !hasAnyLocalizedFooter))
        ? legacyFooter
        : _receiptText('pdfFooterDefault');

    return <String, String>{
      'companyName': companyName,
      'legalName': legalName,
      'address': address,
      'vatNumber': profile.vatNumber.trim().isNotEmpty
          ? profile.vatNumber.trim()
          : settings.vatCompanyNumber.trim(),
      'phone': profile.phone.trim().isNotEmpty
          ? profile.phone.trim()
          : settings.supportPhone.trim(),
      'email': profile.email.trim().isNotEmpty
          ? profile.email.trim()
          : settings.supportEmail.trim(),
      'website': profile.website.trim(),
      'footer': footerText,
      'logoPath': settings.logoAssetPath.trim(),
    };
  }
}

class _ResolvedPdfContact {
  final String? name;
  final String? phoneRaw;
  final String? email;
  final List<String> keys;
  final String source;

  const _ResolvedPdfContact({
    required this.name,
    required this.phoneRaw,
    required this.email,
    required this.keys,
    required this.source,
  });
}
