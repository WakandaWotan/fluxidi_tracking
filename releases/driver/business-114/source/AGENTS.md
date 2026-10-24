# Fluxidi - worktree-instructies

- Controleer git-root, branch/HEAD en lokale wijzigingen vóór substantieel werk; behoud bestaand werk van andere agents/worktrees.
- Houd local, staging en production en fixture-tested, staging-tested, handset-tested en production-tested afzonderlijk bij.
- Werk na substantieel werk de lokale docs/FLUXIDI_HANDOFF.md bij.

<!-- BEGIN FLUXIDI_ANDROID_QA_SOURCE_V1 -->
## Android-staging: gedeelde Definition of Done

- Lees vóór substantieel werk de centrale bron `../fluxidi_tracking/docs/FLUXIDI_RELEASE_CHECKLIST.md`, vooral "Android-staging: Definition of Done". Dit pad is relatief aan de worktree-root (de map van dit AGENTS.md), niet aan een app-submap. Lees ook de lokale `docs/FLUXIDI_HANDOFF.md` als die bestaat.
- Die checklist is de enige inhoudelijke bron voor Android-QA/releaseregels in `fluxidi_tracking`, `fluxidi_customer_dev` en `fluxidi_customer_whitelabel`. Lees haar opnieuw vóór Android-build/upload; maak geen lokale beleidskopie. Bij ontbrekende/onleesbare bron of tegenstrijdige instructies: stop de build/upload en rapporteer.
- De vaste gebruikersopdracht omvat automatisch release-AAB bouwen en uploaden uitsluitend naar Google Play Internal Testing voor werkelijk geraakte stagingapps, zodra klaar voor toestelvalidatie en na groene relevante tests en alle package/endpoints/signing-controles uit de checklist. Vraag daarvoor geen nieuwe toestemming. Alle stopvoorwaarden en rapportagevelden daar blijven verplicht.
- Nooit automatisch Production, Open Testing of Closed Testing. Backend-only en documentatie-only werk vereist geen AAB. Deze afspraak geeft geen toestemming voor backenddeploy, commit, push, reset of stash. Een expliciete beperking in de actuele gebruikersopdracht blijft gelden.
- Wijzig de volledige procedure alleen in de centrale checklist. Houd uitsluitend dit verwijzingsblok identiek in de drie root-AGENTS.md-bestanden; kopieer geen overige worktree-instructies of handoffhistoriek. Bij verhuizing alle drie verwijzingen samen aanpassen en controleren.
<!-- END FLUXIDI_ANDROID_QA_SOURCE_V1 -->
