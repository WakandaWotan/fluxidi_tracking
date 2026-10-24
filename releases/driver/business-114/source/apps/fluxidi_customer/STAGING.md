# Actuele volledige Fluxidi klantenapp: normale en stagingbuild

Bron: deze appmap en de gedeelde root in dezelfde worktree. Beide gebruiken ongewijzigd `lib/main.dart`, dezelfde schermen, services, assets, vertalingen en phone/tablet-layouts. Geen aparte staging-UX, E2E-login of banner. Trackingarchitectuur is niet aangepast.

| | Normaal | Staging |
|---|---|---|
| Android applicationId | com.fluxidi.customer | com.fluxidi.customer.staging |
| Launcherlabel | Fluxidi Klanten | Fluxidi Klanten Staging |
| Payment return | fluxidicustomer://pay/return | fluxidicustomerstaging://pay/return |
| Runtime | production (standaard) | staging |

De interne Android namespace/MainActivity blijft `com.fluxidi.customer.dev`; dit is uitsluitend de bestaande codeklassenaam, NIET het geïnstalleerde package. Android-isolatie en alle provider-authorities volgen applicationId. Backup staat uit. Appdocumenten en secure storage zijn per Android-app gescheiden; bestaande runtime-opslagmappen krijgen bovendien `_staging`.

## Lokaal bouwen vanuit deze map

```powershell
flutter build apk --debug --target-platform android-arm64
flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=config/staging.json
```

Voor werkende kaart/adressuggesties moet de bestaande geldige `MAPBOX_TOKEN` ook als dart-define worden meegegeven; het native resource-token komt uit de bestaande Gradle-property/environment/local.properties-route. Tokens niet in de bronconfig opslaan. De lokaal gecontroleerde debug-APK's zijn compile/identiteitsbewijs; de build zonder token configureert geen werkende Mapbox-runtime. Dit verwijdert geen kaartfunctie uit de app.

Stagingselectie is `FLUXIDI_RUNTIME_ENV=staging`. `config/staging.json` geeft expliciet alle vijf bestaande API-URL-defines mee, waaronder beide public-bookingaliases. Gradle controleert dit vóór compilatie; de Dart-startupguard controleert de effectieve endpoints vóór sessie-/netwerkinitialisatie. Ontbrekende, productie- of E2E-hosts worden geweigerd. Normale builds weigeren staginghosts. Tegenstrijdige package/naam/scheme-defines worden geweigerd. De oude `FLUXIDI_CUSTOMER_STAGING=true` / `.dev` / E2E-route wordt door deze app niet meer geaccepteerd.

`FLUXIDI_CUSTOMER_PLAY=true` blijft uitsluitend een normale release-signingguard en wordt in staging geweigerd. Stagingrelease vereist het bestaande uploadkeystore en MAPBOX_TOKEN; debugbuilds gebruiken debug-signing. Geen versiecodeverhoging of Play-upload in deze opdracht. De bestaande staging-AAB-scriptnaam is behouden, maar gebruikt nu dezelfde actuele config; voer die alleen uit wanneer de centrale releasevoorwaarden daadwerkelijk vervuld zijn.

## Backend nog niet operationeel bewezen

De volgende hostnamen bestonden reeds als gereserveerde stagingconfig in de gedeelde runtimebron. Zij zijn niet als werkende backend verzonnen of gedeployed:

- fluxidi-booking-api-staging.fluxidi.workers.dev
- fluxidi-tracking-api-staging.fluxidi.workers.dev
- fluxidi-navigation-api-staging.fluxidi.workers.dev

Read-only GET /health op 2026-09-26: alle drie HTTP 404, HTML 'Page not found'. Dit bewijst geen uitgerolde API. Voor echte stagingflows ontbreken de bevestigde werkende services en hun stagingbindings/configuratie: customer-auth/session, booking, tracking-Room, route/ETA, en test-betaalprovider/redirectconfig voor het staging payment-scheme. Geen productiebackend als fallback. MAPBOX_TOKEN blijft de bestaande externe providerconfiguratie. Backenddeployment, stagingdata, installatie en Play zijn buiten deze opdracht gebleven.

## Lokaal bewijs

- 164 customer-tests normaal en 164 dezelfde tests onder staging groen, inclusief nieuwe configuratietests.
- 86 bestaande gedeelde tracking/detail/renewal/network/reassignment/leg/generation/presentation/runtime/E2E-guard-tests groen met normale defines. Onder staging worden de 72 tracking/detail-tests apart uitgevoerd. Een extra brede run met stagingdefines gaf 83 pass/3 fail: de drie tests verwachten expliciet productie-defaults; hun normale run is groen en hun verwachtingen zijn niet gewijzigd.
- Beide arm64 debug-APK's gebouwd; package/launcherlabel/scheme/authorities in APK-manifests gecontroleerd.
- Zes echte negatieve Gradleconfiguraties gecontroleerd: verkeerde package, ontbrekende host, productiehost in staging, E2E-vlag, staginghost in normaal, productie-Playvlag met staging.
- Alleen local/fixture/build-tested. Niet staging-, handset- of production-tested. Geen featureverwijderingen of tweede entrypoint.

De bestaande betaalfinalisatieretry en eerdere trackingbeperkingen zijn niet gewijzigd. Deze appconfiguratie is geen bewijs van werkende stagingbetalingen of Android-toestelgedrag.

## Gewijzigde bronnen binnen deze opdracht

- android/app/build.gradle.kts; android/app/src/main/AndroidManifest.xml
- lib/app/customer_app_config.dart; lib/app/customer_runtime_guard.dart (nieuw)
- lib/bridge/customer_runtime.dart; config/staging.json (nieuw)
- test/customer_runtime_configuration_test.dart (nieuw); bestaande customer_deep_link_test.dart, customer_navigation_test.dart, customer_session_lock_test.dart volgen de actuele buildidentiteit
- Gedeelde root lib/app_config.dart: uitsluitend twee directe endpointvelden aangesloten op bestaande overrides; eerdere lokale wijzigingen behouden
- Root scripts/build_fluxidi_customer_staging_aab.ps1; docs/FLUXIDI_HANDOFF.md
- Deze STAGING.md; README.md met verwijzing naar actuele instructies
- Centrale fluxidi_tracking/docs/FLUXIDI_RELEASE_CHECKLIST.md: nieuwe staging-packageverwijzing volgens opdracht

Lokaal bewaarde APK's: root .qa-local/customer-staging-ready/fluxidi-klanten-normal-debug.apk en fluxidi-klanten-staging-debug.apk; beide versie 0.1.0+1, debug-signing, arm64. Niet geïnstalleerd of geüpload.
