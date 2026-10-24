import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'company_public_booking_link.dart';

const companyBookingQrCardKey = Key('company_booking_qr_card');
const companyBookingCopyKey = Key('company_booking_copy');
const companyBookingOpenKey = Key('company_booking_open');
const companyBookingShareKey = Key('company_booking_share');
const companyBookingShareQrKey = Key('company_booking_share_qr');

class CompanyPublicBookingLinkView extends StatefulWidget {
  const CompanyPublicBookingLinkView({
    super.key,
    required this.loader,
    this.language = AppLanguage.nl,
    this.scopeIsCurrent,
    this.urlKey,
    this.copyLink,
    this.openLink,
    this.shareLink,
    this.shareQr,
    this.onAvailabilityChanged,
  });

  final Future<CompanyPublicBookingLink> Function() loader;
  final AppLanguage language;
  final bool Function()? scopeIsCurrent;
  final Key? urlKey;
  final Future<void> Function(String url)? copyLink;
  final Future<bool> Function(Uri url)? openLink;
  final Future<void> Function(String url)? shareLink;
  final Future<void> Function(Uint8List png, String url, String name)? shareQr;
  final ValueChanged<bool>? onAvailabilityChanged;

  @override
  State<CompanyPublicBookingLinkView> createState() =>
      _CompanyPublicBookingLinkViewState();
}

class _CompanyPublicBookingLinkViewState
    extends State<CompanyPublicBookingLinkView> {
  final _boundaryKey = GlobalKey();
  late Future<CompanyPublicBookingLink> _link;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _notifyAvailability(false);
    _link = Future.sync(widget.loader).then((link) {
      _notifyAvailability(widget.scopeIsCurrent?.call() != false);
      return link;
    });
  }

  void _notifyAvailability(bool ready) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAvailabilityChanged?.call(ready);
    });
  }

  String _text(String nl, String en, String fr, String es, String de) =>
      switch (widget.language) {
        AppLanguage.nl => nl,
        AppLanguage.en => en,
        AppLanguage.fr => fr,
        AppLanguage.es => es,
        AppLanguage.de => de,
      };

  String get _unavailable => _text(
    'De publieke boekingslink is nog niet beschikbaar voor dit bedrijf. Controleer je bedrijfsprofiel of probeer later opnieuw.',
    'The public booking link is not available for this company. Check your company profile or try again later.',
    'Le lien de réservation public n’est pas disponible pour cette entreprise. Vérifiez votre profil ou réessayez plus tard.',
    'El enlace público de reserva no está disponible para esta empresa. Revisa tu perfil o inténtalo más tarde.',
    'Der öffentliche Buchungslink ist für dieses Unternehmen nicht verfügbar. Prüfen Sie Ihr Firmenprofil oder versuchen Sie es später erneut.',
  );

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    if (widget.scopeIsCurrent?.call() == false) {
      setState(_load);
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                'Dit is niet gelukt. Probeer opnieuw.',
                'This did not work. Please try again.',
                'Cette action a échoué. Réessayez.',
                'No se pudo completar. Inténtalo de nuevo.',
                'Das hat nicht funktioniert. Versuchen Sie es erneut.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareQr(CompanyPublicBookingLink link) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || widget.scopeIsCurrent?.call() == false) {
      throw const CompanyBookingLinkUnavailable();
    }
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) throw StateError('qr_unavailable');
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || widget.scopeIsCurrent?.call() == false) {
        throw const CompanyBookingLinkUnavailable();
      }
      final png = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (widget.shareQr != null) {
        await widget.shareQr!(png, link.url, link.companyName);
      } else {
        await Share.shareXFiles(
          [
            XFile.fromData(
              png,
              mimeType: 'image/png',
              name: 'booking-qr-${link.slug}.png',
            ),
          ],
          text: link.url,
          subject: link.companyName,
        );
      }
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CompanyPublicBookingLink>(
      future: _link,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final link = snapshot.data;
        if (snapshot.hasError ||
            link == null ||
            widget.scopeIsCurrent?.call() == false) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_unavailable),
              TextButton(
                onPressed: () => setState(_load),
                child: Text(
                  _text(
                    'Opnieuw proberen',
                    'Try again',
                    'Réessayer',
                    'Reintentar',
                    'Erneut versuchen',
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(link.url, key: widget.urlKey),
            const SizedBox(height: 12),
            Center(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Container(
                  key: companyBookingQrCardKey,
                  width: 300,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        link.companyName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _text(
                          'Scan om een rit te boeken',
                          'Scan to book a ride',
                          'Scannez pour réserver une course',
                          'Escanea para reservar un viaje',
                          'Scannen Sie, um eine Fahrt zu buchen',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                        ),
                      ),
                      QrImageView(
                        data: link.url,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                      Text(
                        link.url,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: companyBookingCopyKey,
                  onPressed: _busy
                      ? null
                      : () => _act(() async {
                          if (widget.copyLink != null) {
                            await widget.copyLink!(link.url);
                          } else {
                            await Clipboard.setData(
                              ClipboardData(text: link.url),
                            );
                          }
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _text(
                                  'Boekingslink gekopieerd',
                                  'Booking link copied',
                                  'Lien de réservation copié',
                                  'Enlace de reserva copiado',
                                  'Buchungslink kopiert',
                                ),
                              ),
                            ),
                          );
                        }),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: Text(
                    _text(
                      'Kopieer link',
                      'Copy link',
                      'Copier le lien',
                      'Copiar enlace',
                      'Link kopieren',
                    ),
                  ),
                ),
                FilledButton.icon(
                  key: companyBookingShareQrKey,
                  onPressed: _busy ? null : () => _act(() => _shareQr(link)),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                  label: Text(
                    _text(
                      'Deel QR',
                      'Share QR',
                      'Partager QR',
                      'Compartir QR',
                      'QR teilen',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: companyBookingShareKey,
                  onPressed: _busy
                      ? null
                      : () => _act(() async {
                          if (widget.shareLink != null) {
                            await widget.shareLink!(link.url);
                          } else {
                            await Share.share(
                              link.url,
                              subject: link.companyName,
                            );
                          }
                        }),
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: Text(
                    _text('Delen', 'Share', 'Partager', 'Compartir', 'Teilen'),
                  ),
                ),
                FilledButton.icon(
                  key: companyBookingOpenKey,
                  onPressed: _busy
                      ? null
                      : () => _act(() async {
                          final uri = Uri.parse(link.url);
                          final opened =
                              await (widget.openLink?.call(uri) ??
                                  launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  ));
                          if (!opened) throw StateError('link_unavailable');
                        }),
                  icon: const Icon(Icons.open_in_new_outlined, size: 16),
                  label: Text(
                    _text(
                      'Open link',
                      'Open link',
                      'Ouvrir le lien',
                      'Abrir enlace',
                      'Link öffnen',
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
