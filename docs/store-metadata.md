# App Store-metadata (utkast — lim inn i App Store Connect)

## Identitet
- Navn: **Båtspillet**
- Undertittel (30 tegn): `Seil, frakt og finn skatter!`
- Bundle-id: `skep.batspillet` · IAP: `skep.batspillet.kapteinpakken` (non-consumable, kr 19)
- Primærspråk: Norsk (bokmål) · Kategori: Games → Family (IKKE Kids-kategorien i v1)
- Aldersgrense: 4+ (spørreskjemaet: ingen vold/frykt/gambling — mild tegneserie-sjørøver)

## Promotional text (170 tegn, kan endres uten review)
«Seil, frakt og finn skatter i norske farvann – et rolig og eventyrlig
båtspill for barn, med ekte barnestemme og null reklame.»

## Beskrivelse
Ute på sjøen ligger småbyene og venter. Og midt mellom dem vugger en båt
som du styrer.

Havnesjefene trenger hjelp: passasjerer skal hjem til sitt, og fisken skal
fram før kvelden. For hver tur får du blanke gullmynter, og av og til et
gammelt skattekart. Da gjelder det å seile av sted, for der ute venter en
sjørøverskute – ikke så farlig, bare litt lat og lur – som gjerne vil ha
skatten først.

Ingen må kunne lese for å være kaptein her. En ekte guttestemme forteller deg
alt underveis, og båten kan aldri synke, samme hvor det bærer.

Og har du lyst på mer, finnes Kaptein-pakken: alle finbåtene og hele Amerika,
med snøøyer, ørkenkyst og byer så store som New York.

Spillet passer best for barn mellom 4 og 12, men alle som liker båter får
være med. Ingen reklame og ingen mas. En pappa laget det til gutten sin – og
nå er det ditt.

## Nøkkelord (100 tegn)
`båt,barnespill,seile,skattejakt,norsk,barn,ferje,hav,sjørøver,fisk,spill for barn`

## Skjermbilder (må lages)
- iPhone 6,9": 3–5 stk (verden + skattejakt + butikk + båtvelger)
- iPad 13": 3–5 stk samme motiver
- Ta dem i simulatorene med `Cmd+S` (ekte enhets-oppløsning kreves)

## Lenker
- Personvern-URL: host `docs/personvern.md` (GitHub Pages) → påkrevd felt
- Support-URL: repoets GitHub-side eller samme side

## App-personvern (spørreskjema)
- «Data Not Collected» — alle kategorier NEI (sant: ingen innsamling)

## Sjekkliste før innsending
- [ ] Enrollment godkjent → registrer bundle-id + opprett appen i ASC
- [ ] IAP-produkt opprettet + prispunkt kr 19 + Small Business Program
- [ ] `TEAM_ID=… ./ios.sh archive` → last opp → TestFlight en uke på familien
- [ ] Skjermbilder + tekstene over
- [ ] Reviewer-notat: «All tale er norsk (barnestemme). Kjøpet testes med
      sandbox-konto. Spillet krever ingen konto.»
