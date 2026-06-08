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
    final bundle = await _buildReceiptPdfBundle(
      context: context,
      item: item,
      skipBackendInvoice: true,
    );
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
      final rideDateText =
          _firstPathText(item, const [
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
            _pdfInfoRow(_receiptText('from'), route.from),
            _pdfInfoRow(_receiptText('to'), route.to),
            _pdfInfoRow(_receiptText('distance'), _kmText(item)),
            _pdfInfoRow(_receiptText('duration'), durationText),
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
    bool isPlaceholder(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return true;
      if (text == '-' || text == '—') return true;
      return text.toLowerCase() ==
          _receiptText('currentLocation').toLowerCase();
    }

    String? pickLabel(List<List<String>> paths) {
      for (final path in paths) {
        final text = _cleanContactText(_detailAt(item, path));
        if (!isPlaceholder(text)) return text;
      }
      return null;
    }

    final normalizedFrom = isPlaceholder(item.origin)
        ? null
        : item.origin.trim();
    final normalizedTo = isPlaceholder(item.destination)
        ? null
        : item.destination.trim();
    final rawFrom = pickLabel(const [
      ['from'],
      ['pickup'],
      ['pickup_address'],
      ['pickupAddress'],
      ['pickupLocation'],
      ['pickup_location'],
      ['origin'],
      ['start_address'],
      ['startAddress'],
      ['booking', 'from'],
      ['booking', 'pickup'],
      ['booking', 'pickup_address'],
      ['booking', 'pickupAddress'],
      ['record', 'from'],
      ['record', 'booking', 'from'],
      ['record', 'booking', 'pickup'],
      ['payload', 'from'],
      ['payload', 'booking', 'from'],
      ['quote', 'inputs', 'from'],
    ]);
    final rawTo = pickLabel(const [
      ['to'],
      ['destination'],
      ['destination_address'],
      ['destinationAddress'],
      ['dropoff'],
      ['dropoff_address'],
      ['dropoffAddress'],
      ['end_address'],
      ['endAddress'],
      ['booking', 'to'],
      ['booking', 'destination'],
      ['booking', 'destination_address'],
      ['booking', 'destinationAddress'],
      ['record', 'to'],
      ['record', 'booking', 'to'],
      ['record', 'booking', 'destination'],
      ['payload', 'to'],
      ['payload', 'booking', 'to'],
      ['quote', 'inputs', 'to'],
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
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
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
    if (raw == 'paid' || raw == 'settled' || raw == 'confirmed') {
      return _receiptText('paid');
    }
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
