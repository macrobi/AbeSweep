# AbeSweep

Az AbeSweep natív macOS-segédprogram Adobe-alkalmazások, támogatási fájlok,
háttérszolgáltatások, gyorsítótárak, naplók, beállítások és ellenőrzött
hosts-bejegyzések felderítésére, áttekintésére és kijelölt eltávolítására.

Az AbeSweep 1.4 hivatalos, notarizált DMG-je a
[macadmin.hu](https://macadmin.hu) oldalon és a
[GitHub Releases](https://github.com/macrobi/AbeSweep/releases/tag/v1.4) lapján
érhető el. Mindkét helyen ugyanaz a fájl található. A GitHub a forrásnak,
hibajegyeknek és közreműködésnek ad otthont. A saját build és a módosított
változat nem hivatalos AbeSweep-kiadás.

Az AbeSweep hozzáférhető forrású, ingyenesen használható segédprogram, céges
környezetben és fizetett rendszergazdai munkában is. A [licenc](LICENSE.hu.md)
tiltja a program értékesítését és fizetős szoftvercsomagba foglalását.
Módosított kiadásnál átnevezés, módosításjelölés és forrásmelléklet kötelező.
[Licencösszefoglaló](../LICENSE-STATUS.md).

## Fő képességek

- Szűken meghatározott Adobe-összetevőket keres a gyakori rendszer- és
  felhasználói helyeken.
- Módosítás előtt megmutatja a találat okát, méretét és kockázatát.
- Ideiglenesfájl-, Creative Cloud-infrastruktúra-, teljes eltávolítási és egyéni
  kijelölési módot kínál.
- A dokumentumkezelő alkalmazások szabályos bezárását kéri, és megáll, ha azok
  nyitva maradnak, hogy a felhasználó elmenthesse a munkáját.
- Az eredeti útvonal megőrzésével helyi karanténba mozgatja a kijelölt elemeket,
  visszaállítási jegyzéket és olvasható naplót készít.
- Az `/etc/hosts` fájlból csak ellenőrzött Adobe-bejegyzéseket távolít el, az
  eredetit pedig ellenőrzött másolatként karanténban tartja.
- Ütközésellenőrzést, visszaállítást és hiba vagy megszakítás esetén lehetőség
  szerinti visszagörgetést biztosít.

Az alkalmazás megnyitása és a helyi vizsgálat önmagában nem távolít el fájlt.
A takarítás csak a kijelölés áttekintése, a kockázat megerősítése és a szükséges
macOS-jóváhagyás után indul.

## Biztonsági korlátok

A karantén és a visszaállítás csökkenti a kockázatot, de nem biztonsági mentés,
és nem garantálja minden hiba vagy ütközés helyreállítását. A megszakítási kérés
biztonságos műveleti lépések között lép életbe, ezért nem mindig azonnali. Hagyd
nyitva az AbeSweepet a visszagörgetés végéig, majd ellenőrizd az eredményt és a
naplót.

A visszaállítás nem ír felül újból létrejött célfájlt. Hiányzó vagy megváltozott
karanténelemet nem tud újra létrehozni. A **Karantén végleges törlése** nem
vonható vissza, utána helyreállítás nem lehetséges. Takarítás előtt mentsd a
munkádat, ellenőrizd a Creative Cloud szinkronizálását, és legyen független,
naprakész biztonsági mentésed.

Az AbeSweep még folyamat- vagy szolgáltatásmódosítás előtt ellenőrzi a teljes
kijelölést. Elutasítja azt az indítási szolgáltatást, amelynek plistje,
végrehajtható állománya vagy Adobe-kódaláírása nem igazolható. A kijelölt
fájloknak a karanténnal azonos fájlrendszerköteten kell lenniük; különben egy
kijelölt elemet sem mozgat el.

Visszaállításkor minden meglévő karanténelemnek ugyanazon a fájlrendszerköteten
kell lennie, mint a célútvonal legközelebbi meglévő szülőjének. Az AbeSweep ezt
minden elemnél, mozgatás előtt ellenőrzi, és elutasítja a visszaállítást, ha a
biztonságos visszagörgetés nem garantálható.

## Adatvédelem és hálózat

A vizsgálati eredmény, fájlútvonal, hosts-tartalom, napló, karantén és
Adobe-fiókadat a Macen marad.

Az AbeSweep két egymástól különálló hálózati funkciót használ:

- A Sparkle a hivatalos `macadmin.hu` frissítési feedet ellenőrzi. A Sparkle
  rendszerprofil-küldése ki van kapcsolva.
- Az opcionális Adobe-domainfelülvizsgálat elkülönített HTTPS-munkamenetben
  letölti az Adobe nyilvános hálózati végpontoldalát, majd helyben összeveti a
  beépített katalógussal. Új telepítésnél alapból ki van kapcsolva; kézi
  ellenőrzés vagy külön engedélyezett heti ellenőrzés kapcsolatot létesíthet az
  Adobe kiszolgálójával. Az új cím csak felülvizsgálati jelölt, automatikusan nem
  kerül eltávolításra.

A célkiszolgáló a szokásos hálózati kapcsolat részeként láthatja az IP-címet és
a technikai kérés metaadatait. Részletek: [USAGE.md](USAGE.md).

A forrásból készült build az alapbeállítás szerint megtartja a hivatalos
frissítési feedet és a nyilvános frissítés-ellenőrző kulcsot. A licenc szerint
a továbbadott módosított buildet át kell nevezni és
egyértelműen jelölni. Technikailag a Sparkle-t is ki kell kapcsolni, vagy saját
HTTPS-feedet és a bizalmasan őrzött aláírókulcshoz tartozó saját nyilvános
ellenőrző kulcsot kell használni, hogy a felhasználó ne kerüljön észrevétlenül
hivatalos és nem hivatalos kiadások között.

## Követelmények és fejlesztés

- macOS 14 vagy újabb
- Swift 6-ot támogató Xcode
- Swift Package Managerrel rögzített Sparkle 2.9.6

Egyes védett helyekhez Full Disk Access szükséges, a rendszerfájlok mozgatásához
vagy szolgáltatások vezérléséhez pedig ettől külön rendszergazdai jóváhagyást is
kérhet a macOS. Takarítás előtt olvasd el a [használati útmutatót](USAGE.md).

A felülvizsgált forrás jelenlegi verziója AbeSweep 1.4, buildszáma 10400.

A buildelés leírása: [BUILDING.md](BUILDING.md). A használati és helyreállítási
útmutató: [USAGE.md](USAGE.md). A közreműködés feltételei:
[CONTRIBUTING.md](../CONTRIBUTING.md).

A projektet önkéntes alapon tartják karban. A hibajegyek feldolgozása a
rendelkezésre álló kapacitás szerint történik; válasz vagy javítás nem
garantálható.

Az AbeSweep független, nem hivatalos projekt. Nem az Adobe Inc. terméke, és az
Adobe Inc. nem támogatja, nem ellenőrizte és nem hagyta jóvá. Az Adobe, a
Creative Cloud és a kapcsolódó terméknevek az Adobe Inc. védjegyei lehetnek;
itt kizárólag az együttműködés és a segédprogram céljának leírására szolgálnak.
