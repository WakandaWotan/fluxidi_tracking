import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/auth_failure_kind.dart';
import 'package:fluxidi_tracking/company/local_synthetic_company_session.dart';

typedef BookingHostCopy =
    String Function({
      required String nl,
      required String en,
      required String fr,
      required String es,
    });

AuthFailureKind classifyBookingHostFailure(Object error) {
  return classifyThrownAuthFailure(
    error,
    loopbackHost: isLoopbackBookingBaseUrl(kBookingBaseUrl),
  );
}

String bookingHostFailureUserText(Object error, BookingHostCopy t) {
  return bookingHostFailureUserTextForKind(
    classifyBookingHostFailure(error),
    t,
  );
}

String bookingHostFailureUserTextForKind(
  AuthFailureKind kind,
  BookingHostCopy t, {
  String? rawCode,
}) {
  final host = describePublicAuthHost(kBookingBaseUrl);
  final loopback = isLoopbackBookingBaseUrl(kBookingBaseUrl);
  final code = (rawCode ?? '').trim();
  if (code == 'http_401' || code == 'http_403') {
    return loopback
        ? t(
            nl: 'Deze bedrijfssessie hoort niet bij de lokale Worker op $host. Gebruik een lokaal bedrijf of een productie-build zonder lokale BOOKING_BASE_URL.',
            en: 'This company session does not belong to the local Worker at $host. Use a local company or a production build without a local BOOKING_BASE_URL.',
            fr: 'Cette session entreprise n’appartient pas au Worker local $host. Utilisez une entreprise locale ou un build production.',
            es: 'Esta sesión de empresa no pertenece al Worker local $host. Usa una empresa local o un build de producción.',
          )
        : t(
            nl: 'De bedrijfssessie werd geweigerd. Meld het bedrijf opnieuw aan en probeer opnieuw.',
            en: 'The company session was rejected. Pair the company again and retry.',
            fr: 'La session entreprise a été refusée. Recouplez l’entreprise et réessayez.',
            es: 'La sesión de empresa fue rechazada. Vuelve a emparejar la empresa e inténtalo de nuevo.',
          );
  }
  switch (kind) {
    case AuthFailureKind.localWorkerUnreachable:
      return t(
        nl: 'De lokale Worker is niet bereikbaar. Start eerst de Worker op $host.',
        en: 'The local Worker is unreachable. Start the Worker on $host first.',
        fr: 'Le Worker local est injoignable. Démarrez d’abord le Worker sur $host.',
        es: 'El Worker local no responde. Arranca primero el Worker en $host.',
      );
    case AuthFailureKind.networkError:
      return t(
        nl: 'Geen verbinding met de boekingsserver. Controleer het netwerk en probeer opnieuw.',
        en: 'No connection to the booking server. Check the network and try again.',
        fr: 'Pas de connexion au serveur de réservation. Vérifiez le réseau et réessayez.',
        es: 'Sin conexión con el servidor de reservas. Comprueba la red e inténtalo de nuevo.',
      );
    case AuthFailureKind.wrongEnvironment:
      return t(
        nl: 'Dit bedrijf staat niet op deze lokale debug-Worker ($host). Gebruik een lokaal bedrijf of een productie-build.',
        en: 'This company is not on this local debug Worker ($host). Use a local company or a production build.',
        fr: 'Cette entreprise n’est pas sur ce Worker local ($host). Utilisez une entreprise locale ou un build production.',
        es: 'Esta empresa no está en este Worker local ($host). Usa una empresa local o un build de producción.',
      );
    default:
      return t(
        nl: 'De boekingsserver kon dit verzoek niet verwerken. Probeer opnieuw.',
        en: 'The booking server could not process this request. Try again.',
        fr: 'Le serveur de réservation n’a pas pu traiter cette demande. Réessayez.',
        es: 'El servidor de reservas no pudo procesar esta solicitud. Inténtalo de nuevo.',
      );
  }
}
