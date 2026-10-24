# Gezamenlijke Driver B114 — Internal Testing

BUILD / ARTIFACTVALIDATIE / PLAY INTERNAL READBACK: PASS. Package `com.fluxidi.tracking`, versie `1.0.7 (114)`. De bestaande vier interne testers en andere Play-tracks zijn behouden. Geen toestel bediend, geen boeking of betaling uitgevoerd. Fysieke acceptatie en definitieve release-tag blijven OPEN.

AAB: `D:\Projecten\outputs\driver_joint_b114_20261024\business-114.aab`  
SHA-256: `3bbe45d1881d550c367cffd8c4577e426fb1988719ad2070e0d7ff0cd1092ecf`  
Bytes: 414585844

## Git — vóór de build vastgelegd en gepusht

- Finale gebouwde broncommit: `f444520531431c61b5f629defb844911cc5fc34e` — https://github.com/WakandaWotan/fluxidi_tracking/commit/f444520531431c61b5f629defb844911cc5fc34e
- Geïntegreerde B113-baselinecommit: `c9731692eff8a2c02f24528207f82e3db30e5135`.
- Opgenomen backendcommit van Agent 2: `9e7b3e469d606ac9480030ad87ef6154760fae87`.
- Branch: `codex/driver-integrated-b114-20261024`.
- Volledige Driver-bron: `releases/driver/business-114/source/` (2790 verzegelde bestanden). Volledige backendbron: `releases/backend/booking-preview-20261024-e0270b2c198e/`.
- Bronclosure: `b12f1f87fd081abcbd1841100381562b4a0b3acb5e717a0d81f15e11aeb1a731`. Alle bronbytes waren vóór de build gelijk aan de commit; na de build is er nul bronafwijking. Niet de dirty gedeelde werkboom gebouwd. Gedeelde index, staged exports en Agent 2-bronnen zijn niet overschreven.
- Geen signingkeys, servicetokens, productie-defines of lokale SDK-configuratie gecommit. De bestaande externe productie-defines en signing zijn gebruikt. SOURCE-HASHES.json in Git bevat de complete bronclosure; SOURCE_CHANGES.json hieronder bevat alleen de delta tegenover B113.

Git-parentketen: backend `9e7b3e4` → integratie `c9731692` → verpakkingscorrectie `f4445205`. Remote-readback is vastgelegd in GIT_PUSH_READBACK.json. Er is bewust nog geen definitieve release-tag: die vereist de door de eigenaar gevraagde fysieke PASS.

## Geïntegreerde correcties

1. Persoonlijke QR-/boekingslink: ontbrekende optionele directory-company_code gebruikt uitsluitend de al geverifieerde chauffeursessiecode, na de bestaande sessie-/voertuig-/tenantcontroles. Bestaand bedrijfsleider-QR-scherm, delen en kopiëren hergebruikt. Een echte directory-401 blijft een weigering; geen authenticatie omzeild.
2. Gsm-zijbalk icon-only; tablet/grotere layout en tooltips/toegankelijkheidslabels behouden. Bestaande vijf thema's en taalkeuzes behouden.
3. Eén herhalend native ritalarm en vibratie per scope/aanbod/versie, veilige voorgrond/achtergrondoverdracht onder actuele duty-lease, geen dubbele alarms door polling. Stop pas bij bevestigde beslissing of geldige afloop; late oude ACK annuleert geen nieuw aanbod. OS-volume, notificatiemachtiging, Niet storen en expliciete kanaalkeuzes blijven gelden.
4. Direct heldere, vloeiende rode puls van 600 ms per richting (1,2 s totaal), geen 100-ms-aan/uit-flikkering. Verminderde beweging geeft een statische rode waarschuwing.
5. Mijn ritten: B113 ontving decision200 maar startte daar geen gerichte ritlijstverversing. De geïntegreerde callback start nu de bestaande persoonlijke /driver/bookings-read buiten de cache, met begrensde herhaling. Expliciet `offer.owner_id` blijft behouden; er wordt geen booking-ID uit offer_id ontleed. Pas een actuele niet-degraded pagina met dezelfde canonieke boeking, operationele leg, toegewezen chauffeur/voertuig, niet-gesloten status en niet-available_unassigned opent/ververst automatisch Mijn ritten. ACK alleen, een lege/onvolledige/falende read of oude UI-cache maakt niets toegewezen. De bestaande serverlijst blijft beslissend; geen rolwissel of handmatige navigatie nodig bij bevestigde toewijzing.

## Concrete artifactfout gevonden en gericht hersteld

De eerste lokale B114-AAB is vóór elke upload afgekeurd: er zat géén alarm-WAV in. Ook de bestaande B113-AAB bevat geen WAV. Het werkelijke R8-rapport markeerde `raw/fluxidi_ride_chime` als `reachable=false`. Dit is een bewezen verpakkingsfout; het is geen uitsluitend op toestelinstellingen gebaseerde verklaring voor de historische stilte.

De enige aanvullende productcorrectie is `res/raw/com_fluxidi_tracking_ride_audio_keep.xml`, met precies `tools:keep="@raw/fluxidi_ride_chime"`. De bestaande naam-URI, runtimecode, kanaalinstellingen en permissies zijn daarbij niet veranderd. [Android documenteert tools:keep voor indirect gebruikte resources](https://developer.android.com/topic/performance/app-optimization/customize-which-resources-to-keep).

De herstelbuild bevat de werkelijke WAV-bytes, SHA-gelijk aan de bron; R8 toont nu reachable=true. De eerste AAB blijft bewaard als `business-114.rejected-missing-chime.aab`, SHA-256 `7697bd88c5cb4560dcdbed71537b9fccb77f6fbfd84c90dba030243d7db05d45`. Deze is nooit geüpload. Er waren dus twee traceerbare lokale builds, uitsluitend de tweede is naar Play gegaan. Geen stille rebuild of overschrijving van B113.

## Validatie

| Controle | Resultaat |
|---|---|
| Geïntegreerde Flutter-/QR-/contractregressies | 366/366 PASS |
| Nieuwe canonieke assignmentgevallen, opgenomen in die 366 | 13/13 PASS; ontbrekende B113-wiring eerst rood |
| Zijbalk: vijf thema's/talen, smalle gsm en tablet | 189/189 PASS |
| Native alarm/kanaal/lifecycle-unit-tests | 26/26 PASS |
| Bestaande B113 lijst-/annuleringsregressies | 16/16 PASS |
| Alarmbaseline | zes Flutter-fouten en acht oorspronkelijke native-fouten aangetoond |
| Package/versie/signatuur/bundle/manifest | PASS |
| Uploadcertificaat gelijk B113 | `b8479589dce57c16b2a2e2528d52196d2701deb7ad046af2e735d58afe0a33fe` |
| Permissies | exact gelijk B113 |
| Flutter-assets | 426; inventaris én alle bytes gelijk B113 |
| Native alarm-WAV in AAB | PASS, bytegelijk aan verzegelde bron |
| Productie-endpoints / bekende QA-configuratie afwezig | PASS |
| MapLibre-registratie en 16-KiB native alignment | PASS |
| Bron na build gelijk gepushte commit | PASS, nul drift |
| Play Internal | 114, completed, exacte AAB-hash teruggelezen |
| Testers / andere tracks | bestaande vier behouden / ongewijzigd |

Analyzer: geen nieuwe fout; vier bestaande waarschuwingen/info in de grote Driver-home blijven buiten scope. Bestaande NDK-/Java-deprecationwaarschuwingen hebben de build niet geblokkeerd; de native artifactcontroles zijn afzonderlijk PASS. Native tests gebruiken Android-API-mocks en de UI-tests een mapsurface-fixture. Dit bewijst geen hoorbaarheid, voelbare trilling of echte route op de Samsung.

Tussenliggende harnessproblemen zijn behouden in de logs: ontbrekende import bij de eerste integratiecompile hersteld; relocatie van een testfixture-import gecorrigeerd; verlopen synthetische backendautoriteit wordt nu per test gereset; zijbalkmatrix gebruikt dezelfde bestaande UI-buildflag; oude lijsttestharness kent de nieuwe callback. Geen productie-autorisatie of testverwachting is versoepeld. Alle definitieve controles hierboven zijn groen. De aanvullende keep-XML verandert geen geteste Dart-/Kotlin-werking; de nieuwe resourcegate is op het werkelijk geoptimaliseerde artifact rood→groen bewezen.

## Actieve backend — Agent 2

Gecertificeerde productie-readback van Agent 2: Booking `d58426a5-6b25-4b0b-90ea-db6a4fcadddd` en Tracking `2aecbd6f-f2a5-4236-b175-08ebc2b4ddac`, beide 100%. Booking-entryhash `e0270b2c198e17fedbe094bd1073655594f2b3f6632d6ea62632be9529103087`; companion `9dc892767a74b358605c4367a3e20e95ea344e61ef4a7b1c9d47eb178c5c038e`. 148 Booking-bindings en 16 Tracking-bindings gecontroleerd. ASAP-herstel, prijzen, reserveringen, financiële en tenantbeveiliging zijn volgens die readback behouden. Navigation-code/settings zijn niet gewijzigd. Deze sessie heeft geen nieuwe backenddeployment uitgevoerd.

Vier coherente Core-referenties uit die readback:

```json
{
  "OWNED_QUOTE_ACTIVATION": {
    "schema": "fluxidi-national-activation-v1",
    "state": "active",
    "runtimeSha256": "e0270b2c198e17fedbe094bd1073655594f2b3f6632d6ea62632be9529103087",
    "publicationSha256": "b161ba4cb8d41a9abe25f5be8f84d69f8d82c8a2f4f8afb81b40bf49f94808bb",
    "manifestSha256": "54440cd1e535964cd6a68b60a98b42fd0e3a95a50def3ae8fd10b91f08f0b3b9",
    "graphVersion": "offline-national-car-v2-8096d82857a47e7507353f30",
    "evidenceRevision": "frontage-v1-79740c155aa0f1b862481d44"
  },
  "OWNED_QUOTE_PUBLICATION_REF": {
    "schema": "fluxidi-national-publication-ref-v1",
    "key": "routing/national/publications/b161ba4cb8d41a9abe25f5be8f84d69f8d82c8a2f4f8afb81b40bf49f94808bb.json",
    "sha256": "b161ba4cb8d41a9abe25f5be8f84d69f8d82c8a2f4f8afb81b40bf49f94808bb",
    "bytes": 1266138
  },
  "RELIABLE_NATIONAL_ACTIVATION": {
    "schema": "fluxidi-national-activation-v1",
    "state": "active",
    "runtimeSha256": "e0270b2c198e17fedbe094bd1073655594f2b3f6632d6ea62632be9529103087",
    "publicationSha256": "b161ba4cb8d41a9abe25f5be8f84d69f8d82c8a2f4f8afb81b40bf49f94808bb",
    "manifestSha256": "54440cd1e535964cd6a68b60a98b42fd0e3a95a50def3ae8fd10b91f08f0b3b9",
    "graphVersion": "offline-national-car-v2-8096d82857a47e7507353f30",
    "evidenceRevision": "frontage-v1-79740c155aa0f1b862481d44"
  },
  "RELIABLE_NATIONAL_PUBLICATION_REF": {
    "schema": "fluxidi-national-publication-ref-v1",
    "key": "routing/national/publications/b161ba4cb8d41a9abe25f5be8f84d69f8d82c8a2f4f8afb81b40bf49f94808bb.json",
    "sha256": "b161ba4cb8d41a9abe25f5be8f84d69f8d82c8a2f4f8afb81b40bf49f94808bb",
    "bytes": 1266138
  }
}
```

## Open fysieke punten en harde grens

De eigenaar werkt de Samsung via de normale Play-update bij naar 1.0.7 (114), zonder uninstall of gegevensreset. Nog te bevestigen: nieuw aanbod hoorbaar/voelbaar/zichtbaar in voor- en achtergrond; accepteren → automatisch Mijn ritten; behoud na verversen/schermwissel; echte routepreview met afstand/ETA; navigatie met werkelijke route; persoonlijke QR-/boekingslink; icon-only-zijbalk. Zie ACCEPTANCE.md.

`assignment_driver_no_vehicle` blijft expliciet OPEN. Dit pakket verbergt een latere serverintrekking niet en houdt geen onterecht toegewezen rit vast. De eerdere fysieke navigatiefout en 9,8-secondenboekingsverwerking zijn eveneens niet als opgelost aangemerkt. Een kaart zonder route is geen navigatie-PASS. Alleen na eigenaarbevestiging van fysieke PASS wordt de definitieve Git-release-tag gemaakt; bij FAIL blijven commits/artifacts behouden en wordt alleen het bewezen defect opgevolgd.

## Gewijzigde bestanden en SHA-256 tegenover B113

| Bestand | SHA-256 finale bron |
|---|---|
| `android/app/src/main/kotlin/com/fluxidi/tracking/DriverDutyService.kt` | `696fc7f315863791e7eca6d96d5469d621719b86e10476a8cf22e3a9df9d2969` |
| `android/app/src/main/kotlin/com/fluxidi/tracking/DriverRideNotifications.kt` | `16a9a5530c2f280e9161df84c0f03f50124aa71e6bd2906e207e9ba00045733e` |
| `android/app/src/main/kotlin/com/fluxidi/tracking/MainActivity.kt` | `bc56119cee244841f7eda5005f6b1e424e535f7b7ec10501da032a896e202bb4` |
| `android/app/src/main/kotlin/com/fluxidi/tracking/VehicleRideAlert.kt` | `873f7500a49a1873bee005594a305494564d6a9e3545ed624564450b0fa256e0` |
| `android/app/src/main/res/raw/fluxidi_ride_chime.wav` | `102eaf093ee0b36e8adb1ffde160d8e691d35c66d040cc86407961bce546d385` |
| `android/app/src/test/kotlin/com/fluxidi/tracking/DriverRideChannelPolicyTest.kt` | `54d8a641d952b3632772bf7ec6da1194d398bc4b1215b3ed554c77f5d8bb56a1` |
| `docs/FLUXIDI_HANDOFF.md` | `a1ee52a8c4b3487329a657c164f213a85e637586aeb26982cacb966147cff44f` |
| `lib/company/active_company_booking_link_view.dart` | `a709edb95fad8f9c8c7a2d56e5ae0d16da0b2f3efa9d6ded43e471440a976a1e` |
| `lib/company/booking_list_mutation_reload.dart` | `51962bf2fe65bacad181eae4ec5b8012c64dada5d574515979e35743a67c1b3d` |
| `lib/company/driver_booking_link_trace.dart` | `9d73b7e59809a71caf7c1b7a90ff9b5f78184df421cd6426097bc3ebabdea059` |
| `lib/company/driver_public_booking_link.dart` | `3086cebe89734e813dcdab212a7d63f7277095a461682c5c5bc64643e9066cfb` |
| `lib/driver/driver_ride_alert.dart` | `e734b661adec98e423288598e8567f321d9c74a96ec20e29e6a1eace0bacbce6` |
| `lib/driver/driver_ride_alert_controller.dart` | `169c3d85e104ecc29045626e705d4a97e939d9569203c36bb60bd2e545c4ad3b` |
| `lib/driver/driver_ride_frame_border.dart` | `12e1438cc2bebede1a645d8d49a54d6fb229a083f20fc07949e86d3d3c781047` |
| `lib/driver/driver_ride_offer.dart` | `0721d57e26836c7b0244e4db9a3583f8713693743ea2145f1d64e39606e11c32` |
| `lib/driver/driver_ride_offer_host.dart` | `f9c365cbb6bd0169a3f41e0448c30bb28f4e68c1ec0bb95cdf406559b5602040` |
| `lib/main.dart` | `839cf3ed0d3958dbf2a96d7dfcfee0f6c0a50c0b265966826901ca98fbb050f7` |
| `lib/main_parts/driver_home_page_state.dart` | `aa1ad3b0a2243094b5ab134c2607e3b444aea5c77a2e557d84c5a665f58b4ab2` |
| `pubspec.yaml` | `bd84b4ab55360acae406d4d6a1d0e050411e571a84977238e08037487624b02d` |
| `test/company/driver_booking_link_trace_test.dart` | `fa03117141399a3c3d8255db20351d527f33e6990d4ac526108063aa8d1e32d5` |
| `test/driver/driver_assignment_refresh_test.dart` | `4c2a8b6e7e9030e85559b1c04a086f7e4a50ee11032c0b6a8a41ffa73f4fcbb5` |
| `test/driver/fixtures/alarm_before/driver_ride_alert.dart` | `d2b226b961d58be43209448ae8d2c987885d6e502c633c0a1b933ebdb67ae386` |
| `test/driver/fixtures/alarm_before/driver_ride_alert_controller.dart` | `6ac14ac0c6b8edc68c516174eba3cfc8cb24216e790db1cc9846a388667848cc` |
| `test/driver/fixtures/alarm_before/driver_ride_frame_border.dart` | `c1b09e8054fedcda5626c35050864de4860e199370379bed2f62bbf1693d62ca` |
| `test/driver/fixtures/alarm_before/driver_ride_offer_host.dart` | `78e4618c5a350eaf69c4b25dc022d80b9079a82fe419a829a638892e578382b8` |
| `test/driver/fixtures/assignment_refresh_home.dart` | `05d703fa4dad74eda2ad27c95c35c81219a67a6117b8624f20e962154d3bac9b` |
| `test/driver/fixtures/driver_ride_frame_border_before.dart` | `20b2d97b6de8575ef9670be152be5e58229f517f91e7f47c3633a56a0fc27f2b` |
| `test/driver/fixtures/driver_ride_offer_host_before.dart` | `220941b1d375ee396e935feb999221960e7a4540a635e5dc272dacd67f6270b7` |
| `test/driver/ride_alarm_repair_test.dart` | `71bd27315a49482e9792cfe3ea2a3b894d9dfadf62f044974120c34c09da280b` |
| `test/driver/ride_alarm_source_preservation_test.dart` | `c30a8cb8ff6d84cf39e4020e47c02bfd2cb2d61250bf77b1ceec77ed8002ccf0` |
| `android/app/src/main/res/raw/com_fluxidi_tracking_ride_audio_keep.xml` | `293e93e7b97374488628e9e829b1e5458310a57360b170b9cbb8008282e806c9` |

Uitvoerbewijs: business-AAB_PROOF.json, ARTIFACT_INTEGRATION_PROOF.json, PLAY_READBACK.json, TESTER_PRESERVATION.json, BACKEND_RELEASE_READBACK.json en SOURCE_CHANGES.json. B113-AAB en zijn bronseals zijn behouden. Bestaande B108/B109/B110/B111/B112/C94 en de publieke webrelease zijn niet gewijzigd.
