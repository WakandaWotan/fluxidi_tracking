part of '../main.dart';

String _receiptText(String key) {
  switch (key) {
    case 'receiptTitle':
      return _tr(nl: 'Ritbon', en: 'Receipt', fr: 'Reçu', es: 'Recibo');
    case 'rideReceipt':
      return _tr(
        nl: 'Bewijs van rit',
        en: 'Ride receipt',
        fr: 'Justificatif de course',
        es: 'Comprobante del viaje',
      );
    case 'receiptUnavailable':
      return _tr(
        nl: 'Ritbon is beschikbaar na afronden van de rit.',
        en: 'Receipt is available after completing the ride.',
        fr: 'Le reçu est disponible après la fin de la course.',
        es: 'El recibo esta disponible despues de finalizar el viaje.',
      );
    case 'tripHistoryTitle':
      return _tr(
        nl: 'Ritten historiek',
        en: 'Ride history',
        fr: 'Historique des courses',
        es: 'Historial de viajes',
      );
    case 'refresh':
      return _tr(
        nl: 'Vernieuw',
        en: 'Refresh',
        fr: 'Actualiser',
        es: 'Actualizar',
      );
    case 'historyLoadFailed':
      return _tr(
        nl: 'Kon ritten historiek niet laden.',
        en: 'Could not load ride history.',
        fr: "Impossible de charger l'historique.",
        es: 'No se pudo cargar el historial.',
      );
    case 'historyEmpty':
      return _tr(
        nl: 'Nog geen ritten gevonden.',
        en: 'No rides found yet.',
        fr: 'Aucune course trouvée.',
        es: 'Aun no hay viajes.',
      );
    case 'archiveTripLabel':
      return _tr(nl: 'Verberg', en: 'Hide', fr: 'Masquer', es: 'Ocultar');
    case 'archiveTripTitle':
      return _tr(
        nl: 'Deze rit verbergen uit de historiek?',
        en: 'Hide this ride from history?',
        fr: 'Masquer cette course de l’historique ?',
        es: '¿Ocultar este viaje del historial?',
      );
    case 'archiveTripBody':
      return _tr(
        nl: 'De ritbon blijft bewaard voor administratie.',
        en: 'The receipt will remain stored for administration.',
        fr: 'Le reçu reste conservé pour l’administration.',
        es: 'El recibo seguirá guardado para la administración.',
      );
    case 'archiveTripCancel':
      return _tr(nl: 'Annuleren', en: 'Cancel', fr: 'Annuler', es: 'Cancelar');
    case 'archiveTripConfirm':
      return _tr(nl: 'Verbergen', en: 'Hide', fr: 'Masquer', es: 'Ocultar');
    case 'archiveTripSuccess':
      return _tr(
        nl: 'Rit verborgen uit historiek.',
        en: 'Ride hidden from history.',
        fr: 'Course masquée de l’historique.',
        es: 'Viaje ocultado del historial.',
      );
    case 'archiveTripFailed':
      return _tr(
        nl: 'Kon rit niet verbergen.',
        en: 'Could not hide ride.',
        fr: 'Impossible de masquer la course.',
        es: 'No se pudo ocultar el viaje.',
      );
    case 'waitingCompact':
      return _tr(nl: 'wachten', en: 'waiting', fr: 'attente', es: 'espera');
    case 'type':
      return _tr(nl: 'Type', en: 'Type', fr: 'Type', es: 'Tipo');
    case 'streetRide':
      return _tr(
        nl: 'Straatrit',
        en: 'Street ride',
        fr: 'Course directe',
        es: 'Viaje directo',
      );
    case 'plannedRide':
      return _tr(
        nl: 'Geplande rit',
        en: 'Planned ride',
        fr: 'Course planifiée',
        es: 'Viaje planificado',
      );
    case 'outboundRide':
      return _tr(
        nl: 'Heenrit',
        en: 'Outbound ride',
        fr: 'Trajet aller',
        es: 'Viaje de ida',
      );
    case 'returnRide':
      return _tr(
        nl: 'Retourrit',
        en: 'Return ride',
        fr: 'Trajet retour',
        es: 'Viaje de vuelta',
      );
    case 'subtype':
      return _tr(nl: 'Subtype', en: 'Subtype', fr: 'Sous-type', es: 'Subtipo');
    case 'receiptNumber':
      return _tr(
        nl: 'Bonnummer',
        en: 'Receipt no.',
        fr: 'Numéro de reçu',
        es: 'Número de recibo',
      );
    case 'planningNumber':
      return _tr(
        nl: 'Planningnummer',
        en: 'Planning no.',
        fr: 'N° de planning',
        es: 'N.º de planificación',
      );
    case 'bookingNumber':
      return _tr(
        nl: 'Boekingsnummer',
        en: 'Booking no.',
        fr: 'N° de réservation',
        es: 'N.º de reserva',
      );
    case 'internalBooking':
      return _tr(
        nl: 'Interne boeking',
        en: 'Internal booking',
        fr: 'Réservation interne',
        es: 'Reserva interna',
      );
    case 'internalTrip':
      return _tr(
        nl: 'Interne rit',
        en: 'Internal trip',
        fr: 'Course interne',
        es: 'Viaje interno',
      );
    case 'tripId':
      return _tr(nl: 'Trip ID', en: 'Trip ID', fr: 'ID course', es: 'ID viaje');
    case 'bookingId':
      return _tr(
        nl: 'Booking ID',
        en: 'Booking ID',
        fr: 'ID réservation',
        es: 'ID reserva',
      );
    case 'date':
      return _tr(nl: 'Datum', en: 'Date', fr: 'Date', es: 'Fecha');
    case 'startTime':
      return _tr(
        nl: 'Starttijd',
        en: 'Start time',
        fr: 'Heure de début',
        es: 'Hora de inicio',
      );
    case 'endTime':
      return _tr(
        nl: 'Stoptijd',
        en: 'End time',
        fr: 'Heure de fin',
        es: 'Hora de fin',
      );
    case 'duration':
      return _tr(nl: 'Duur', en: 'Duration', fr: 'Durée', es: 'Duración');
    case 'pickup':
      return _tr(
        nl: 'Ophaaladres',
        en: 'Pickup',
        fr: 'Prise en charge',
        es: 'Recogida',
      );
    case 'destination':
      return _tr(
        nl: 'Bestemming',
        en: 'Destination',
        fr: 'Destination',
        es: 'Destino',
      );
    case 'from':
      return _tr(nl: 'Van', en: 'From', fr: 'De', es: 'Desde');
    case 'to':
      return _tr(nl: 'Naar', en: 'To', fr: 'À', es: 'A');
    case 'distance':
      return _tr(
        nl: 'Afstand',
        en: 'Distance',
        fr: 'Distance',
        es: 'Distancia',
      );
    case 'actualDistance':
      return _tr(
        nl: 'Werkelijke afstand',
        en: 'Actual distance',
        fr: 'Distance réelle',
        es: 'Distancia real',
      );
    case 'waitingTime':
      return _tr(
        nl: 'Wachttijd',
        en: 'Waiting time',
        fr: "Temps d'attente",
        es: 'Tiempo de espera',
      );
    case 'bookedWaitingTime':
      return _tr(
        nl: 'Geboekte wachttijd',
        en: 'Booked waiting time',
        fr: "Attente réservée",
        es: 'Espera reservada',
      );
    case 'actualWaitingTime':
      return _tr(
        nl: 'Werkelijke wachttijd',
        en: 'Actual waiting time',
        fr: "Attente réelle",
        es: 'Espera real',
      );
    case 'plannedBookingDetails':
      return _tr(
        nl: 'Geplande boeking',
        en: 'Planned booking details',
        fr: 'Détails de réservation',
        es: 'Detalles de reserva',
      );
    case 'bookingDetails':
      return _tr(
        nl: 'Boekingsdetails',
        en: 'Booking details',
        fr: 'Détails de réservation',
        es: 'Detalles de reserva',
      );
    case 'customer':
      return _tr(nl: 'Klant', en: 'Customer', fr: 'Client', es: 'Cliente');
    case 'customerDetails':
      return _tr(
        nl: 'Klantgegevens',
        en: 'Customer details',
        fr: 'Coordonnées client',
        es: 'Datos del cliente',
      );
    case 'customerName':
      return _tr(
        nl: 'Klantnaam',
        en: 'Customer name',
        fr: 'Nom du client',
        es: 'Nombre del cliente',
      );
    case 'customerPhone':
      return _tr(
        nl: 'Telefoon',
        en: 'Customer phone',
        fr: 'Téléphone client',
        es: 'Teléfono del cliente',
      );
    case 'customerEmail':
      return _tr(
        nl: 'E-mail',
        en: 'Customer email',
        fr: 'E-mail client',
        es: 'Email del cliente',
      );
    case 'scheduledPickup':
      return _tr(
        nl: 'Geplande ophaal',
        en: 'Scheduled pickup',
        fr: 'Prise en charge prévue',
        es: 'Recogida programada',
      );
    case 'service':
      return _tr(nl: 'Service', en: 'Service', fr: 'Service', es: 'Servicio');
    case 'passengerTransport':
      return _tr(
        nl: 'Personenvervoer',
        en: 'Passenger transport',
        fr: 'Transport de passagers',
        es: 'Transporte de pasajeros',
      );
    case 'businessRide':
      return _tr(
        nl: 'Zakelijke rit',
        en: 'Business ride',
        fr: "Course d'affaires",
        es: 'Viaje de negocios',
      );
    case 'airportTransfer':
      return _tr(
        nl: 'Luchthavenvervoer',
        en: 'Airport transfer',
        fr: 'Transfert aeroport',
        es: 'Traslado al aeropuerto',
      );
    case 'tier':
      return _tr(nl: 'Tier', en: 'Tier', fr: 'Catégorie', es: 'Categoría');
    case 'tierComfort':
      return _tr(nl: 'Comfort', en: 'Comfort', fr: 'Confort', es: 'Confort');
    case 'tierPrivate':
      return _tr(nl: 'Private', en: 'Private', fr: 'Prive', es: 'Privado');
    case 'tierPremium':
      return _tr(nl: 'Premium', en: 'Premium', fr: 'Premium', es: 'Premium');
    case 'passengers':
      return _tr(
        nl: 'Passagiers / Pax',
        en: 'Passengers / Pax',
        fr: 'Passagers / Pax',
        es: 'Pasajeros / Pax',
      );
    case 'bags':
      return _tr(nl: 'Bagage', en: 'Bags', fr: 'Bagages', es: 'Equipaje');
    case 'extraStops':
      return _tr(
        nl: 'Extra stops',
        en: 'Extra stops',
        fr: 'Arrêts supplémentaires',
        es: 'Paradas extra',
      );
    case 'extras':
      return _tr(nl: 'Extras', en: 'Extras', fr: 'Extras', es: 'Extras');
    case 'notes':
      return _tr(nl: 'Notities', en: 'Notes', fr: 'Notes', es: 'Notas');
    case 'routeAndPrices':
      return _tr(
        nl: 'Route en prijzen',
        en: 'Route and prices',
        fr: 'Itinéraire et prix',
        es: 'Ruta y precios',
      );
    case 'route':
      return _tr(nl: 'Route', en: 'Route', fr: 'Itinéraire', es: 'Ruta');
    case 'routeDetails':
      return _tr(
        nl: 'Route details',
        en: 'Route details',
        fr: "Détails de l'itinéraire",
        es: 'Detalles de ruta',
      );
    case 'outboundRoute':
      return _tr(
        nl: 'Heenroute',
        en: 'Outbound route',
        fr: 'Itinéraire aller',
        es: 'Ruta de ida',
      );
    case 'returnRoute':
      return _tr(
        nl: 'Retour route',
        en: 'Return route',
        fr: 'Itinéraire retour',
        es: 'Ruta de vuelta',
      );
    case 'returnTrip':
      return _tr(
        nl: 'Retourrit',
        en: 'Return trip',
        fr: 'Trajet retour',
        es: 'Viaje de vuelta',
      );
    case 'returnPlanned':
      return _tr(
        nl: 'Retour gepland',
        en: 'Return planned',
        fr: 'Retour prevu',
        es: 'Vuelta programada',
      );
    case 'fixedPrice':
      return _tr(
        nl: 'Vaste prijs',
        en: 'Fixed price',
        fr: 'Prix fixe',
        es: 'Precio fijo',
      );
    case 'fixedQuotePrice':
      return _tr(
        nl: 'Vaste offerteprijs',
        en: 'Fixed quote price',
        fr: 'Prix devis fixe',
        es: 'Precio fijo cotizado',
      );
    case 'packagePrice':
      return _tr(
        nl: 'Pakketprijs incl. btw',
        en: 'Package price incl. VAT',
        fr: 'Prix forfaitaire TVA incl.',
        es: 'Precio paquete IVA incl.',
      );
    case 'ridePrice':
      return _tr(
        nl: 'Ritprijs incl. btw',
        en: 'Ride price incl. VAT',
        fr: 'Prix course TVA incl.',
        es: 'Precio viaje IVA incl.',
      );
    case 'outboundPrice':
      return _tr(
        nl: 'Prijs heen incl. btw',
        en: 'Outbound price incl. VAT',
        fr: 'Prix aller TVA incl.',
        es: 'Precio ida IVA incl.',
      );
    case 'returnPrice':
      return _tr(
        nl: 'Prijs retour incl. btw',
        en: 'Return price incl. VAT',
        fr: 'Prix retour TVA incl.',
        es: 'Precio vuelta IVA incl.',
      );
    case 'total':
      return _tr(nl: 'Totaal', en: 'Total', fr: 'Total', es: 'Total');
    case 'amount':
      return _tr(nl: 'Bedrag', en: 'Amount', fr: 'Montant', es: 'Importe');
    case 'payment':
      return _tr(nl: 'Betalen', en: 'Payment', fr: 'Paiement', es: 'Pago');
    case 'receiptActions':
      return _tr(nl: 'Bon', en: 'Receipt', fr: 'Reçu', es: 'Recibo');
    case 'statusPaymentSection':
      return _tr(
        nl: 'Status en betaling',
        en: 'Status and payment',
        fr: 'Statut et paiement',
        es: 'Estado y pago',
      );
    case 'paymentActions':
      return _tr(nl: 'Betaalzone', en: 'Payment', fr: 'Paiement', es: 'Pago');
    case 'moreOptions':
      return _tr(
        nl: 'Meer opties',
        en: 'More options',
        fr: 'Plus d’options',
        es: 'Más opciones',
      );
    case 'payByQr':
      return _tr(
        nl: 'Betaal via QR',
        en: 'Pay by QR',
        fr: 'Payer par QR',
        es: 'Pagar con QR',
      );
    case 'cashReceived':
      return _tr(
        nl: 'Contant ontvangen',
        en: 'Cash received',
        fr: 'Espèces reçues',
        es: 'Efectivo recibido',
      );
    case 'paidByCardTerminal':
      return _tr(
        nl: 'Betaald via Bancontact',
        en: 'Paid by card terminal',
        fr: 'Payé par terminal bancaire',
        es: 'Pagado con terminal de tarjeta',
      );
    case 'businessInvoice':
      return _tr(
        nl: 'Zakelijke factuur',
        en: 'Business invoice',
        fr: 'Facture professionnelle',
        es: 'Factura comercial',
      );
    case 'invoicePending':
      return _tr(
        nl: 'Betaling via factuur in afwachting',
        en: 'Invoice pending',
        fr: 'Paiement par facture en attente',
        es: 'Pago por factura pendiente',
      );
    case 'invoiced':
      return _tr(
        nl: 'Gefactureerd',
        en: 'Invoiced',
        fr: 'Facturé',
        es: 'Facturado',
      );
    case 'confirmQrPaid':
      return _tr(
        nl: 'QR betaling bevestigd',
        en: 'QR payment confirmed',
        fr: 'Paiement QR confirme',
        es: 'Pago QR confirmado',
      );
    case 'paymentStatus':
      return _tr(
        nl: 'Betaalstatus',
        en: 'Payment status',
        fr: 'Statut du paiement',
        es: 'Estado del pago',
      );
    case 'rideStatus':
      return _tr(
        nl: 'Ritstatus',
        en: 'Ride status',
        fr: 'Statut de la course',
        es: 'Estado del viaje',
      );
    case 'paid':
      return _tr(nl: 'Betaald', en: 'Paid', fr: 'Payé', es: 'Pagado');
    case 'unpaid':
      return _tr(
        nl: 'Onbetaald',
        en: 'Unpaid',
        fr: 'Non payé',
        es: 'No pagado',
      );
    case 'paymentSent':
      return _tr(
        nl: 'Betaalverzoek verstuurd',
        en: 'Payment request sent',
        fr: 'Demande de paiement envoyée',
        es: 'Solicitud de pago enviada',
      );
    case 'paymentMarkedPaid':
      return _tr(
        nl: 'Betaling als betaald opgeslagen.',
        en: 'Payment saved as paid.',
        fr: 'Paiement enregistre comme paye.',
        es: 'Pago guardado como pagado.',
      );
    case 'paymentMarkFailed':
      return _tr(
        nl: 'Kon betaling niet opslaan. Probeer opnieuw.',
        en: 'Could not save payment. Please retry.',
        fr: 'Impossible denregistrer le paiement. Reessayez.',
        es: 'No se pudo guardar el pago. Intentalo de nuevo.',
      );
    case 'bookingIdMissing':
      return _tr(
        nl: 'Boekings-ID ontbreekt.',
        en: 'Booking ID is missing.',
        fr: 'ID de reservation manquant.',
        es: 'Falta el ID de reserva.',
      );
    case 'paymentAuthRequired':
      return _tr(
        nl: 'Log opnieuw in om de betaling te bevestigen.',
        en: 'Sign in again to confirm this payment.',
        fr: 'Reconnectez-vous pour confirmer ce paiement.',
        es: 'Vuelva a iniciar sesion para confirmar este pago.',
      );
    case 'qrReadyToScan':
      return _tr(
        nl: 'QR gereed om te scannen. Bevestig hieronder na betaling.',
        en: 'QR ready to scan. Confirm below once paid.',
        fr: 'QR pret a scanner. Confirmez ci-dessous une fois paye.',
        es: 'QR listo para escanear. Confirme abajo una vez pagado.',
      );
    case 'demoPayment':
      return _tr(
        nl: 'Markeer betaald (demo)',
        en: 'Mark paid (demo)',
        fr: 'Marquer comme payé (demo)',
        es: 'Marcar pagado (demo)',
      );
    case 'qrPayment':
      return _tr(
        nl: 'QR betaling',
        en: 'QR payment',
        fr: 'Paiement QR',
        es: 'Pago QR',
      );
    case 'showPaymentLink':
      return _tr(
        nl: 'Toon betaallink',
        en: 'Show payment link',
        fr: 'Voir le lien de paiement',
        es: 'Mostrar enlace de pago',
      );
    case 'showQrPayment':
      return _tr(
        nl: 'Toon QR betaling',
        en: 'Show QR payment',
        fr: 'Voir le QR de paiement',
        es: 'Mostrar pago QR',
      );
    case 'copyPaymentLink':
      return _tr(
        nl: 'Kopieer betaallink',
        en: 'Copy payment link',
        fr: 'Copier le lien de paiement',
        es: 'Copiar enlace de pago',
      );
    case 'sharePaymentRequest':
      return _tr(
        nl: 'Deel betaalverzoek',
        en: 'Share payment request',
        fr: 'Partager la demande de paiement',
        es: 'Compartir solicitud de pago',
      );
    case 'paymentPlaceholder':
      return _tr(
        nl: 'MVP: deze link is een interne demolink en verwerkt nog geen echte betalingen.',
        en: 'MVP: this is an internal demo link and does not process real payments yet.',
        fr: 'MVP : ce lien est un lien interne de démonstration et ne traite pas encore de paiements réels.',
        es: 'MVP: este enlace es un enlace interno de demostración y aún no procesa pagos reales.',
      );
    case 'driver':
      return _tr(
        nl: 'Chauffeur',
        en: 'Driver',
        fr: 'Chauffeur',
        es: 'Conductor',
      );
    case 'vehicle':
      return _tr(nl: 'Voertuig', en: 'Vehicle', fr: 'Véhicule', es: 'Vehículo');
    case 'licensePlate':
      return _tr(
        nl: 'Nummerplaat',
        en: 'License plate',
        fr: "Plaque d'immatriculation",
        es: 'Matricula',
      );
    case 'status':
      return _tr(nl: 'Status', en: 'Status', fr: 'Statut', es: 'Estado');
    case 'notAvailable':
      return _tr(
        nl: 'Niet beschikbaar',
        en: 'Not available',
        fr: 'Non disponible',
        es: 'No disponible',
      );
    case 'unknown':
      return _tr(
        nl: 'Onbekend',
        en: 'Unknown',
        fr: 'Inconnu',
        es: 'Desconocido',
      );
    case 'close':
      return _tr(nl: 'Sluiten', en: 'Close', fr: 'Fermer', es: 'Cerrar');
    case 'copy':
      return _tr(nl: 'Kopieer', en: 'Copy', fr: 'Copier', es: 'Copiar');
    case 'copyLink':
      return _tr(
        nl: 'Kopieer link',
        en: 'Copy link',
        fr: 'Copier le lien',
        es: 'Copiar enlace',
      );
    case 'share':
      return _tr(nl: 'Delen', en: 'Share', fr: 'Partager', es: 'Compartir');
    case 'shareReceipt':
      return _tr(
        nl: 'Deel bon',
        en: 'Share receipt',
        fr: 'Partager le reçu',
        es: 'Compartir recibo',
      );
    case 'send':
      return _tr(nl: 'Verstuur', en: 'Send', fr: 'Envoyer', es: 'Enviar');
    case 'emailReceipt':
      return _tr(
        nl: 'Mail bon',
        en: 'Email receipt',
        fr: 'Envoyer le reçu',
        es: 'Enviar recibo',
      );
    case 'printReceipt':
      return _tr(
        nl: 'Print bon',
        en: 'Print receipt',
        fr: 'Imprimer le reçu',
        es: 'Imprimir recibo',
      );
    case 'viewPdf':
      return _tr(
        nl: 'Bekijk PDF',
        en: 'View PDF',
        fr: 'Voir PDF',
        es: 'Ver PDF',
      );
    case 'viewInvoicePdf':
      return _tr(
        nl: 'Factuur-PDF bekijken',
        en: 'View invoice PDF',
        fr: 'Voir le PDF de la facture',
        es: 'Ver PDF de factura',
      );
    case 'sharePdf':
      return _tr(
        nl: 'Deel PDF',
        en: 'Share PDF',
        fr: 'Partager PDF',
        es: 'Compartir PDF',
      );
    case 'shareInvoicePdf':
      return _tr(
        nl: 'Factuur delen',
        en: 'Share invoice',
        fr: 'Partager la facture',
        es: 'Compartir factura',
      );
    case 'emailPdf':
      return _tr(
        nl: 'Stuur PDF via e-mail',
        en: 'Send PDF by email',
        fr: 'Envoyer PDF par e-mail',
        es: 'Enviar PDF por correo',
      );
    case 'whatsappPdf':
      return _tr(
        nl: 'Stuur PDF via WhatsApp',
        en: 'Send PDF via WhatsApp',
        fr: 'Envoyer PDF via WhatsApp',
        es: 'Enviar PDF por WhatsApp',
      );
    case 'pdfReady':
      return _tr(
        nl: 'PDF klaar om te delen.',
        en: 'PDF is ready to share.',
        fr: 'PDF prêt à partager.',
        es: 'PDF listo para compartir.',
      );
    case 'pdfGenerationFailed':
      return _tr(
        nl: 'PDF maken mislukt, we gebruiken de tekstversie.',
        en: 'PDF generation failed, using text fallback.',
        fr: 'Échec de génération PDF, utilisation de la version texte.',
        es: 'Falló la generación del PDF, usando versión de texto.',
      );
    case 'paymentReceiptLabel':
      return _tr(
        nl: 'Betaalbewijs / Ritbon',
        en: 'Payment receipt / Ride receipt',
        fr: 'Justificatif de paiement / Reçu de course',
        es: 'Comprobante de pago / Recibo de viaje',
      );
    case 'invoiceLabel':
      return _tr(nl: 'Factuur', en: 'Invoice', fr: 'Facture', es: 'Factura');
    case 'subtotalExVat':
      return _tr(
        nl: 'Subtotaal excl. btw',
        en: 'Subtotal excl. VAT',
        fr: 'Sous-total HT',
        es: 'Subtotal sin IVA',
      );
    case 'vatAmount':
      return _tr(
        nl: 'BTW-bedrag',
        en: 'VAT amount',
        fr: 'Montant TVA',
        es: 'Importe IVA',
      );
    case 'vatRate':
      return _tr(
        nl: 'BTW-tarief',
        en: 'VAT rate',
        fr: 'Taux TVA',
        es: 'Tasa IVA',
      );
    case 'paymentMethod':
      return _tr(
        nl: 'Betaalmethode',
        en: 'Payment method',
        fr: 'Méthode de paiement',
        es: 'Método de pago',
      );
    case 'paymentSource':
      return _tr(
        nl: 'Betalingsbron',
        en: 'Payment source',
        fr: 'Source du paiement',
        es: 'Origen del pago',
      );
    case 'company':
      return _tr(nl: 'Bedrijf', en: 'Company', fr: 'Entreprise', es: 'Empresa');
    case 'legalName':
      return _tr(
        nl: 'Juridische naam',
        en: 'Legal name',
        fr: 'Raison sociale',
        es: 'Razón social',
      );
    case 'companyAddress':
      return _tr(nl: 'Adres', en: 'Address', fr: 'Adresse', es: 'Dirección');
    case 'companyVat':
      return _tr(
        nl: 'BTW-nummer',
        en: 'VAT number',
        fr: 'Numéro TVA',
        es: 'NIF/IVA',
      );
    case 'companyPhone':
      return _tr(
        nl: 'Telefoon',
        en: 'Company phone',
        fr: 'Téléphone entreprise',
        es: 'Teléfono de empresa',
      );
    case 'companyEmail':
      return _tr(
        nl: 'E-mail',
        en: 'Company email',
        fr: 'E-mail entreprise',
        es: 'Email de empresa',
      );
    case 'companyWebsite':
      return _tr(nl: 'Website', en: 'Website', fr: 'Site web', es: 'Sitio web');
    case 'printLater':
      return _tr(
        nl: 'Printfunctie wordt later gekoppeld aan printer.',
        en: 'Printing will be connected to a printer later.',
        fr: 'L’impression sera connectée à une imprimante ultérieurement.',
        es: 'La impresión se conectará a una impresora más adelante.',
      );
    case 'whatsappReceipt':
      return _tr(
        nl: 'Stuur bon via WhatsApp',
        en: 'Send receipt via WhatsApp',
        fr: 'Envoyer le reçu via WhatsApp',
        es: 'Enviar recibo por WhatsApp',
      );
    case 'emailReceiptToCustomer':
      return _tr(
        nl: 'Mail bon naar klant',
        en: 'Email receipt to customer',
        fr: 'Envoyer le reçu au client',
        es: 'Enviar recibo al cliente',
      );
    case 'whatsappPaymentRequest':
      return _tr(
        nl: 'Stuur betaallink via WhatsApp',
        en: 'Send payment link via WhatsApp',
        fr: 'Envoyer le lien de paiement via WhatsApp',
        es: 'Enviar enlace de pago por WhatsApp',
      );
    case 'emailPaymentRequest':
      return _tr(
        nl: 'Mail betaallink naar klant',
        en: 'Email payment link to customer',
        fr: 'Envoyer le lien de paiement au client',
        es: 'Enviar enlace de pago al cliente',
      );
    case 'noCustomerContact':
      return _tr(
        nl: 'Geen klantcontactgegevens beschikbaar voor gerichte verzending.',
        en: 'No customer contact details available for targeted sending.',
        fr: 'Aucune coordonnée client disponible pour un envoi ciblé.',
        es: 'No hay datos de contacto del cliente disponibles para el envío directo.',
      );
    case 'phoneNeedsCountryCode':
      return _tr(
        nl: 'Gebruik een telefoonnummer met landcode, bijvoorbeeld +32.',
        en: 'Use a phone number with country code, for example +32.',
        fr: 'Utilisez un numéro avec indicatif pays, par exemple +32.',
        es: 'Usa un número con prefijo internacional, por ejemplo +32.',
      );
    case 'noValidWhatsappPhone':
      return _tr(
        nl: 'Geen klanttelefoonnummer gevonden.',
        en: 'No customer phone number found.',
        fr: 'Aucun numéro de téléphone client trouvé.',
        es: 'No se encontró ningún teléfono del cliente.',
      );
    case 'whatsappOpenFailed':
      return _tr(
        nl: 'WhatsApp kon niet worden geopend.',
        en: 'Could not open WhatsApp.',
        fr: 'Impossible d’ouvrir WhatsApp.',
        es: 'No se pudo abrir WhatsApp.',
      );
    case 'emailOpenFailed':
      return _tr(
        nl: 'E-mailapp kon niet worden geopend.',
        en: 'Could not open email app.',
        fr: 'Impossible d’ouvrir l’application e-mail.',
        es: 'No se pudo abrir la app de correo.',
      );
    case 'receiptEmailSubject':
      return _tr(
        nl: 'Uw ritbon',
        en: 'Your ride receipt',
        fr: 'Votre reçu de course',
        es: 'Su recibo de viaje',
      );
    case 'paymentEmailSubject':
      return _tr(
        nl: 'Betaalverzoek / demolink',
        en: 'Payment request / demo link',
        fr: 'Demande de paiement / lien de démonstration',
        es: 'Solicitud de pago / enlace de demostración',
      );
    case 'paymentRequestDemoTitle':
      return _tr(
        nl: 'Betaalverzoek / demolink',
        en: 'Payment request / demo link',
        fr: 'Demande de paiement / lien de démonstration',
        es: 'Solicitud de pago / enlace de demostración',
      );
    case 'reference':
      return _tr(
        nl: 'Referentie',
        en: 'Reference',
        fr: 'Référence',
        es: 'Referencia',
      );
    case 'ride':
      return _tr(nl: 'Rit', en: 'Ride', fr: 'Course', es: 'Viaje');
    case 'thanksRide':
      return _tr(
        nl: 'Bedankt voor uw rit.',
        en: 'Thank you for your ride.',
        fr: 'Merci pour votre course.',
        es: 'Gracias por su viaje.',
      );
    case 'pdfFooterDefault':
      return _tr(
        nl: 'Bedankt voor uw vertrouwen in Fluxidi.',
        en: 'Thank you for choosing Fluxidi.',
        fr: 'Merci pour votre confiance en Fluxidi.',
        es: 'Gracias por confiar en Fluxidi.',
      );
    case 'currentLocation':
      return _tr(
        nl: 'Huidige locatie',
        en: 'Current location',
        fr: 'Position actuelle',
        es: 'Ubicación actual',
      );
    case 'receiptFrom':
      return _tr(
        nl: 'Bon van',
        en: 'Receipt from',
        fr: 'Reçu de',
        es: 'Recibo de',
      );
    case 'paymentRequestFrom':
      return _tr(
        nl: 'Betaalverzoek van',
        en: 'Payment request from',
        fr: 'Demande de paiement de',
        es: 'Solicitud de pago de',
      );
    case 'downloadSave':
      return _tr(
        nl: 'Download / opslaan',
        en: 'Download / save',
        fr: 'Télécharger / enregistrer',
        es: 'Descargar / guardar',
      );
    case 'comingSoon':
      return _tr(
        nl: 'komt later.',
        en: 'coming later.',
        fr: 'arrive plus tard.',
        es: 'llegara mas tarde.',
      );
    case 'paymentLink':
      return _tr(
        nl: 'Betaallink',
        en: 'Payment link',
        fr: 'Lien de paiement',
        es: 'Enlace de pago',
      );
    case 'paymentLinkCopied':
      return _tr(
        nl: 'Betaallink gekopieerd.',
        en: 'Payment link copied.',
        fr: 'Lien de paiement copié.',
        es: 'Enlace de pago copiado.',
      );
    case 'paymentRequestCopied':
      return _tr(
        nl: 'Betaalverzoek gekopieerd om te delen.',
        en: 'Payment request copied for sharing.',
        fr: 'Demande de paiement copiée pour partage.',
        es: 'Solicitud de pago copiada para compartir.',
      );
    case 'receiptCopied':
      return _tr(
        nl: 'Bontekst gekopieerd om te delen.',
        en: 'Receipt text copied for sharing.',
        fr: 'Texte du reçu copié pour partage.',
        es: 'Texto del recibo copiado para compartir.',
      );
  }
  return key;
}

String _localizedRideKind(String kind) {
  return kind.toLowerCase().trim() == 'planned'
      ? _receiptText('plannedRide')
      : _receiptText('streetRide');
}

String _localizedRideSubtype(String? raw) {
  final value = (raw ?? '').toLowerCase().trim();
  if (value == 'retourrit' || value == 'return ride' || value == 'return') {
    return _receiptText('returnRide');
  }
  if (value == 'heenrit' || value == 'outbound ride' || value == 'outbound') {
    return _receiptText('outboundRide');
  }
  return _receiptText('unknown');
}

String _localizedRideStatus(String? raw) {
  final value = (raw ?? '').toLowerCase().trim();
  switch (value) {
    case 'stopped':
    case 'completed':
    case 'complete':
    case 'done':
      return _tr(
        nl: 'Afgerond',
        en: 'Completed',
        fr: 'Terminée',
        es: 'Finalizada',
      );
    case 'active':
    case 'running':
      return _tr(nl: 'Actief', en: 'Active', fr: 'Active', es: 'Activa');
    case 'waiting':
    case 'wait':
      return _tr(
        nl: 'Wachten',
        en: 'Waiting',
        fr: 'En attente',
        es: 'En espera',
      );
    case 'cancelled':
    case 'canceled':
      return _tr(
        nl: 'Geannuleerd',
        en: 'Cancelled',
        fr: 'Annulée',
        es: 'Cancelada',
      );
  }
  return _receiptText('unknown');
}

bool _looksLikeCoordinatePair(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return false;
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
  final match = RegExp(
    r'^([+-]?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d{1,3}(?:\.\d+)?)$',
  ).firstMatch(normalized);
  if (match == null) return false;
  final lat = double.tryParse(match.group(1)!);
  final lon = double.tryParse(match.group(2)!);
  if (lat == null || lon == null) return false;
  return lat.abs() <= 90.0 && lon.abs() <= 180.0;
}

String _receiptStartPointFallback() {
  return _tr(
    nl: 'Straatrit startpunt',
    en: 'Street ride start point',
    fr: 'Point de départ',
    es: 'Punto de inicio',
  );
}

String _receiptStartLocationFallback() {
  return _tr(
    nl: 'Startlocatie',
    en: 'Start location',
    fr: 'Point de départ',
    es: 'Punto de inicio',
  );
}

String _sanitizeCustomerFacingRouteLabel(
  String? raw, {
  required bool isFromField,
}) {
  final fallback = isFromField
      ? _receiptStartPointFallback()
      : _receiptStartLocationFallback();
  final text = raw?.trim() ?? '';
  if (text.isEmpty || text == '-' || text == '—') return fallback;
  if (text.toLowerCase() == _receiptText('currentLocation').toLowerCase()) {
    return fallback;
  }
  if (_looksLikeCoordinatePair(text)) return fallback;
  return text;
}
