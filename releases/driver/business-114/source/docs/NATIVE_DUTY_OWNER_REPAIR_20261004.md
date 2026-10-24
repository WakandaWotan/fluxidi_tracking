# Native beschikbaarheidsdienst: eigenaar en startbevestiging

Datum: 2026-10-04. Authoritative bron: `D:/Projecten/_flutter_work/fluxidi_business_internal47`, HEAD `fef8a2f3b25c4ea2e8f6d818d8829ea6207f3aa8` (bestaande dirty werkboom behouden). Deze deelopdracht wijzigt geen Customerbron, backend, manifest, permissions, GPS-freshnessbeleid, signingmateriaal of releasenummer.

## Vastgesteld op Business 58

De aangesloten tablet had Business 58 en een actief appproces, maar geen `DriverDutyService`, geen dienstmelding 754 en geen actuele Fluxidi locatieproviderregistratie. FINE/COARSE waren toegestaan; masterlocatie was aan. Dit bewijst geen algemene Androidpermission- of Dozeblokkade. Gesaneerde runtime-rolmarkers bevestigden `business_preview`; de bestaande previewguard sloeg native duty terecht over om teamchauffeurs niet automatisch de locatie van één administratortablet te geven. Root en release_readiness beheren de afzonderlijke reparatie voor een expliciet geauthenticeerde duurzame toesteleigenaar.

## Native herstel

- MainActivity bevestigde vroeger alleen het in de Androidqueue plaatsen van een start. Nu wacht het maximaal acht seconden op de servicecallback. `true` betekent foregrounddienst gestart en minstens één locatiesubscriptie succesvol toegepast. Dit is **geen** bewijs dat een verse GPS-fix of heartbeat door de server is geaccepteerd.
- `DriverDutyLifecycle` bewaakt ook nog niet uitgevoerde starts. STOP vóór `onStartCommand`, late startbevestiging, late fout en oude generatie na een eigenaarwissel kunnen een nieuwere activatie niet activeren of verwijderen.
- Elke activatie heeft immutable bearer/endpoints en een generatie. GPS-listeners en de opgeslagen fix horen bij die exacte activatie. Een nieuwe activatie wist oude fix/cadence/foutteller, verwijdert oude subscriptions, annuleert oude connections en invalideert oude queued callbacks. Een request gebruikt uitsluitend de credentials van zijn oorspronkelijke activatie.
- Immutable ownerconfig bevat tevens tenant/company/driver/vehicle en notificationtekst. Cold restore mag uitsluitend een bestaande activatie adopteren wanneer de volledige expected config overeenkomt. Een andere bearer, actor, voertuig of endpoint geeft geen runningactivatie of device-ID terug.
- Native ready wordt pas na permission/providerregistratie gepubliceerd. Ontbrekende toestemming, uitgeschakelde locatie, falende registratie, startfout en timeout leveren `false` en een vaste gesaneerde reden op. Geen bearer, requestbody of GPS wordt toegevoegd aan logging.
- Na echte native ready wordt de eerste heartbeat meteen ingepland; de bestaande periodieke 90 seconden en GPS-cadence 120/25 seconden blijven behouden.
- HTTP 401/403 op heartbeat, GPS en dispatchreceipt beëindigt alleen de betrokken activatie. STOP/teardown van een oude activatie mag een nieuwere niet beëindigen.

## Compatibel channelcontract

`fluxidi/driver_duty`:

| Methode | Contract |
| --- | --- |
| `start` | Bestaande config plus optionele `activation_id`; zonder ID krijgt een legacycaller een native gegenereerde ID. Boolresult maximaal acht seconden begrensd. |
| `running` | Optionele `activation_id`; met ID uitsluitend de matching activatie. Zonder argument blijft de legacy globale query werken. |
| `status` | Optionele ID of `expected_config`; `{running, activation_id, native_device_id, state, reason}` met state `starting`, `ready`, `failed` of `stopped`. Expected config vereist token/tenant_id/company_id/driver_id/vehicle_id/booking/tracking exact; title/text worden vergeleken indien opgegeven. Onvolledige/malformed/mismatched expected config geeft `owner_not_current`, geen activatie of device-ID. Native device-ID uitsluitend bij matched ready expected config. Geen gevoelige credentials. |
| `stop` | Optionele ID; met ID alleen die eigenaar, zonder argument legacy globale STOP voor expliciete logout/offline. |
| `consent` | Bestaande expliciete toestemmingskeuze behouden. |

## Tests en compilebewijs

De eerdere volledige native Gradlegate gaf 11/11 PASS. Na withdrawal/actorstatusuitbreiding is de finale Android-nativecompile opnieuw geslaagd, zonder Fluttercompile/assetcopy en zonder AAB/upload/install:

```text
:app:compileReleaseKotlin
-x :app:compileFlutterBuildRelease -x :app:copyFlutterAssetsRelease
```

Private buildomgeving alleen geladen, geen secretwaarden gelezen/geprint of config gewijzigd. De volledige Gradle unit-task na deze uitbreiding werd geblokkeerd door een inconsistente gegenereerde `GeneratedPluginRegistrant` die integration_test registreert terwijl de actuele release Gradle-pluginconfig deze dev-plugin mist. De JavaCompile-exclusie is door AGP geweigerd. Geen gegenereerde file of dependencyconfig is hiervoor gewijzigd; root moet dit via de reguliere Flutter releasevoorbereiding consistent maken.

Daarom zijn de finale pure Kotlinhelpers en hun tests rechtstreeks met de bestaande cached Kotlin2.1.0/JUnit4.13.2 en Java17 gecompileerd/uitgevoerd: **23/23 PASS**, nul failures. Dertien lifecyclecases, zeven withdrawalcases en drie cadencetests. Cases omvatten enqueue/ready/configmatching, stop vóór queued start, late A ready/failure/STOP behoudt B, immutable credentials, generations, revoke, cold redelivery/status mismatch, same-bearer voertuigswitch, optionele notificationmatch, failclosed ontbrekende/verkeerd getypte actorconfig, oorspronkelijke withdrawalcredentials, geen state/token van nieuwe B bij retry, max4 attempts/max180s, 429backoff, verlopen retry, terminal auth/owner mismatch en max32 queued leases.

Finale bewijslogs: `C:/Users/cvanr/AppData/Local/Temp/fluxidi-business-native-duty-final-compile-20261004.log` en `fluxidi-business-native-duty-final-kotlin-junit-20261004.log`. Standalone testclasses: `C:/Users/cvanr/AppData/Local/Temp/fluxidi-native-duty-final-kotlin-gate-17c96b42-3d7c-4250-94a5-0c10c3aaabfe`. Alleen bestaande Notification.Builder/PiP-deprecation en overige dependencywaarschuwingen bij nativecompile; geen Kotlin compilefouten. Bestaande 11-test XML bewijst de eerdere gate, niet de finale 23-teststandalonegate.

## Read-only backendcontract en resterende grens

De authoritative Booking/Trackingbron heeft geen `/driver/native-session`/devicecredentialrefreshroute. Bestaande gewone driverlogin/pairing levert een scoped 30-daagse bearer. Operator-mint levert standaard één uur, bedoeld voor de UIpreview, met lokale owned-sessionclear bij routeexit; dat is geen duurzame native toesteleigenaar.

Tracking GPS verifieert KV driverrecord, role `driver`, tenant/company/driver en expiry; clientscopeconflicten worden geweigerd. Actuele driverindex, diensturen/pauze/accountactiviteit en toegewezen voertuig bepalen de toegestane presence. Geen fysieke deviceproof of purpose/origincheck is aan dat bestaande bearercontract toegevoegd. Revocation via verwijderen van het scoped KV sessionrecord blijft behouden. Dispatchreceipt gebruikt de SHA256 van de bearer als `device_key`, los van GPSfreshness.

Beschikbaarheidsupdate blijft driverbreed zonder expectedrevision/currentdevice/sessionownercheck. Daarom **geen automatische globale pause/clear** met een oude bearer tijdens lokale eigenaarwissel: daarmee kan de actuele eigenaar op een ander toestel worden gepauzeerd. Dispatchcapabilities houden hun bestaande sessionhash/TTL en echte straatrit-/capacityclaims worden niet verwijderd.

## Nieuwe exact-owned withdrawal

De native service publiceert `/track/driver/location` met `activation_id` en `native_device_id`. Activation is een opaque `[A-Za-z0-9_-]{1,128}` generatielabel; de installUUID wordt als niet-geheime waarde in app-private SharedPreferences `driver_duty/duty_device_id` bewaard. Dit is geen hardware-attestatie of nieuwe credentialopslag. De bestaande scoped bearer blijft authenticatie.

Orderly STOP, eigenaarwissel, startfailure, revoke en echte service-teardown trekken de oude locatiepublishinglease asynchroon in via `POST /track/driver/location/withdraw`, oude immutable bearer en body `{activation_id,native_device_id}`. Een afzonderlijke process-local queue blijft na Service.worker-stop werken, met maximaal vier pogingen, een 180s deadline en maximaal 32 pending snapshots. Alleen network/5xx/429 worden binnen die grens herprobeerd. Geen credential wordt opgeslagen; een oude failed withdrawal wijzigt geen nieuwe native duty, binding of beschikbaarheid.

private_profile implementeert het bijbehorende servercontract: authscope/tokenhash worden server-side bepaald; Room serialiseert GPS/withdraw, wist uitsluitend de exacte actuele bearer+activatie+device-publicatie en bewaart een retired-activation fence tegen late oude GPS. Een nieuwe activatie met dezelfde bearer blijft toegestaan; legacy en andere eigenaren blijven ongemoeid. Zonder daadwerkelijk sessiegebonden native_device_id is installUUID alleen een aanvullende equalitylabel. Native doet geen backenddeploy: root moet de passende backendversie vóór Business59 uitrollen en vergelijken.

Bij proceskill/force-stop of onbereikbaar netwerk blijft de bestaande GPSfreshness/TTL de fallback. Connected orderly STOP is het concrete onmiddellijke withdrawalcontract; er wordt geen garantie op uitschrijving na OS-forcekill gemaakt. Native generic GPS bevat geen booking/session/phase; private_profile behoudt bij exact dezelfde eigenaar uitsluitend reeds gevalideerde pickup/trip-context. Dat backendpad plus foreground `/track/ping` met dezelfde proof moet de volledige NAV/on_trip-regressie afdekken.

## Nog te bewijzen

De lifecycle-JVMtests en nativecompile bewijzen geen echt Android servicecallback-/GPS-/scherm-uit-/procesherstartgedrag. Root beheert Dartintegratie, Business59 AAB/Internal en toestelacceptatie. Controleer daarop expliciete eigen chauffeuractivatie, daadwerkelijke foregrounddienst/notification/provider en verse serverGPS, scherm uit/app weg, pause/logout en identiteitwissel zonder teampreview-GPS. Geen release-/handset-/end-to-end voltooiingsclaim uit deze deelopdracht.

## Root Business59 build/upload proof — 2026-10-04

Ordinary com.fluxidi.tracking 1.0.7(59), min24/target36, was signed with the existing B8479589...A33FE upload certificate. AAB399999123bytes, SHA2564fe51c30e9dd7117b842f47f8cd6bff0beacfbaff8f5870cabd12c8411d2c0ec; immutable copy C:/Users/cvanr/AppData/Local/Temp/fluxidi-business59-verified-release.aab. Source1780files, HEAD/staged stable, only verified expected release GeneratedPluginRegistrant drift; asset420 PASS. Final Dart251 PASS. Full Android release Gradle gate59 PASS: duty23, GoogleMaps27, Mapbox9, XML build/app/test-results/testReleaseUnitTest; earlier integration_test registration blocker resolved by ordinary release generation. Internal completed edit00842404565985044429, independently read back; production4 unchanged. Tablet last verified58; native screen-off/live-map acceptance pending. Full root/server/hotel rollout evidence: D:/Projecten/_flutter_work/fluxidi_booking_live_9af4c215_rc/docs/CONTINUATION_RELEASE_PROOF_20261004.md.

## Business60 Internal completion — 2026-10-04

Ordinary com.fluxidi.tracking 1.0.7(60), min24/target36, includes59native duty repairs plus the narrow wrapped billing notices. 71 relevant Play/layout/catalog/quote/add-on tests PASS; explicit notice/billing/test analyzer no issues. AAB399996879bytes, SHA25674e40e527b5db95124f9057ab0fd4ebb224e649eb68108e8552d5e25ba61b25a, immutable TEMP/fluxidi-business60-verified-release.aab. Existing B8479589...A33FE upload certificate verified, assets420 PASS, source1780files/HEAD/staged fixed/no drift. Play Internal completed edit06306435737237688108; independent fresh readback60completed, public production4 unchanged. Tablet Play download is in progress; installation and real native-GPS/notice acceptance have not yet been inferred from that download. No subscription price/entitlement/contract/charge change included.
