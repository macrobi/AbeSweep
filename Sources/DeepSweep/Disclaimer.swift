import Foundation

enum DisclaimerCopy {
    static var title: String {
        L10n.text(
            "Fontos használati és felelősségi tájékoztató",
            "Important usage and liability notice"
        )
    }

    static var introduction: String {
        L10n.text(
            "Az AbeSweep független, nem hivatalos segédprogram. Nem az Adobe Inc. terméke, és az Adobe Inc. nem támogatja, nem ellenőrizte, illetve nem hagyta jóvá.",
            "AbeSweep is an independent, unofficial utility. It is not an Adobe Inc. product and has not been supported, reviewed, or approved by Adobe Inc."
        )
    }

    static var operation: String {
        L10n.text(
            "Az AbeSweep a fejlesztés idején nyilvánosan hozzáférhető műszaki információk, valamint a számítógépen észlelhető fájlnevek, csomagazonosítók és rendszerútvonalak alapján azonosítja az Adobe-hoz kapcsolódó összetevőket. Az Adobe-termékek, a macOS és a külső bővítmények változhatnak, ezért nem garantálható, hogy a program minden rendszer-összeállításban valamennyi elemet hiánytalanul vagy tévedésmentesen felismer.",
            "AbeSweep identifies Adobe-related components using technical information that was publicly available during development, together with file names, bundle identifiers, and system paths detected on the computer. Adobe products, macOS, and third-party plug-ins may change, so complete or error-free detection cannot be guaranteed for every system configuration."
        )
    }

    static var risk: String {
        L10n.text(
            "Az eltávolítás alkalmazásokat, beállításokat és rendszerszintű háttérszolgáltatásokat érinthet. Használat előtt mentsd el a munkádat, ellenőrizd a Creative Cloud szinkronizálását, és készíts naprakész biztonsági mentést. Csak akkor indíts műveletet, ha átnézted a kijelölt elemeket és érted a lehetséges következményeket. A karantén és a visszaállítás csökkenti, de nem szünteti meg teljesen az adatvesztés vagy működési zavar kockázatát.",
            "Removal may affect applications, settings, and system-level background services. Before use, save your work, verify Creative Cloud synchronization, and create an up-to-date backup. Start an operation only after reviewing the selected items and understanding the possible consequences. Quarantine and restore reduce, but do not entirely eliminate, the risk of data loss or malfunction."
        )
    }

    static var fullDiskAccess: String {
        L10n.text(
            "A teljes Adobe-eltávolításhoz a macOS Teljes lemezhozzáférés engedélyére lehet szükség, mert bizonyos alkalmazáskonténereket a rendszer külön véd. Az AbeSweep adatolvasás nélküli próbával ellenőrzi a hozzáférést; ha az már rendben van, nem nyitja meg feleslegesen a Rendszerbeállításokat. Ellenkező esetben nyisd meg az Adatvédelem és biztonság > Teljes lemezhozzáférés panelt, add hozzá az AbeSweep.app fájlt, kapcsold be mellette az engedélyt, majd lépj ki az AbeSweepből és indítsd újra. Az AbeSweep nem tudja saját magának megadni ezt a jogosultságot. A hitelesítést a macOS végzi, és támogatott, beállított gépen Touch ID-t is felajánlhat; ezt az AbeSweep nem kényszerítheti ki. A takarítás után az engedély kikapcsolható.",
            "Complete Adobe removal may require macOS Full Disk Access because the system separately protects certain application containers. AbeSweep checks access with a probe that does not read file contents; when access is already working, it does not open System Settings unnecessarily. Otherwise, open Privacy & Security > Full Disk Access, add AbeSweep.app, turn on permission beside it, then quit and reopen AbeSweep. AbeSweep cannot grant this permission to itself. Authentication is handled by macOS, which may offer Touch ID on a supported and configured Mac; AbeSweep cannot force it. You may turn off the permission after cleanup."
        )
    }

    static var privacy: String {
        L10n.text(
            "Az alkalmazásfrissítések ellenőrzése a macadmin.hu frissítési kiszolgálójához kapcsolódik; a Sparkle rendszerprofil-küldése ki van kapcsolva. Az Adobe-domainellenőrzés ettől külön működik, és új telepítésnél alapból kikapcsolt. Kézi indításkor vagy külön engedélyezett heti ellenőrzéskor kizárólag az Adobe nyilvános hivatalos végpontoldalát tölti le elkülönített, cookie- és tartós cache nélküli HTTPS-kapcsolaton, majd helyben összeveti a beépített domainlistával. Új cím esetén csak felülvizsgálati jelzést ad; automatikus törlés nincs. A hosts fájl, a vizsgálati eredmények, fájlútvonalak, naplók, karantén és Adobe-fiókadatok nem kerülnek feltöltésre. A célkiszolgáló a szokásos internetkapcsolat részeként láthatja az IP-címet és az AbeSweep nevét tartalmazó technikai kérésazonosítót.",
            "Application update checks connect to the macadmin.hu update server; Sparkle system profiling is disabled. Adobe domain review is a separate feature and is off by default on a new installation. When run manually or enabled for weekly review, it downloads only Adobe's official public endpoint page through an isolated HTTPS session without cookies or persistent caching, then compares it locally with the built-in domain list. New addresses are only flagged for review; nothing is removed automatically. The hosts file, scan results, file paths, logs, quarantine, and Adobe account data are not uploaded. As part of an ordinary internet connection, the destination server can see the IP address and a technical request identifier containing the AbeSweep name."
        )
    }

    static var liability: String {
        L10n.text(
            "A szoftver a lehető legnagyobb gondossággal készült, de hibamentes működésére, adott célra való alkalmasságára vagy teljes körű eredményére nincs feltétlen garancia. A felhasználó a műveletet saját, tájékozott döntése alapján indítja. A jogszabály által megengedett legteljesebb mértékben a szerző nem vállal felelősséget a rendeltetésellenes használatból, figyelmen kívül hagyott figyelmeztetésből, nem támogatott vagy egyedi rendszerkonfigurációból eredő közvetett károkért, adatvesztésért vagy szolgáltatáskiesésért.\n\nEz a tájékoztató nem zárja ki és nem korlátozza a jogszabály alapján ki nem zárható felelősséget, illetve a felhasználót megillető kötelező fogyasztói jogokat.",
            "The software has been developed with the greatest reasonable care, but error-free operation, fitness for a particular purpose, or complete results are not unconditionally guaranteed. The user starts each operation based on their own informed decision. To the fullest extent permitted by law, the author is not liable for indirect damage, data loss, or service interruption resulting from misuse, ignored warnings, or unsupported or unusual system configurations.\n\nThis notice does not exclude or limit liability that cannot be excluded by law or any mandatory consumer rights available to the user."
        )
    }

    static var trademarks: String {
        L10n.text(
            "Az Adobe, a Creative Cloud és az Adobe-termékek nevei az Adobe Inc. védjegyei vagy bejegyzett védjegyei lehetnek. Az elnevezések kizárólag az együttműködés és a program rendeltetésének leírására szolgálnak.",
            "Adobe, Creative Cloud, and Adobe product names may be trademarks or registered trademarks of Adobe Inc. These names are used solely to describe interoperability and the purpose of the utility."
        )
    }
}
