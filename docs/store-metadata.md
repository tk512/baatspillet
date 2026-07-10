# App Store-metadata (utkast — lim inn i App Store Connect)

## Identitet
- Navn: **Båtspillet**
- Undertittel (30 tegn): `Seil, frakt og finn skatter!`
- Bundle-id: `skep.batspillet` · IAP: `skep.batspillet.kapteinpakken` (non-consumable, kr 19)
- Primærspråk: Norsk (bokmål) · Kategori: Games → Family (IKKE Kids-kategorien i v1)
- Aldersgrense: 4+ (spørreskjemaet: ingen vold/frykt/gambling — mild tegneserie-sjørøver)

## Beskrivelse (utkast)
Seil mellom norske byer i ditt eget båtspill! Frakt passasjerer og fisk,
tjen gullmynter, kjøp proviant i havnebutikken – og hold utkikk etter den
late sjørøveren. Finn skattekart hos havnesjefene, kappseil mot sjørøverskuta
til sandbankene, og samle alle skattene i albumet ditt.

Laget av en pappa til sønnen sin (5) – all tale er ekte barnestemme, og
spillet kan spilles helt uten å kunne lese.

- Rolig og snilt: båten synker aldri, havnene er alltid trygge
- Norsk tale og norske byer
- Oppdrag, skattejakt, delfiner, ubåt og fyrverkeri
- Ingen reklame, ingen sporing – én valgfri Kaptein-pakke (alle finbåtene)

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
