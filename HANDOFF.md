# AirPad — état du chantier v1 App Store

Dernière mise à jour : 2026-08-27 (session 3)
Branche de travail : `release/v1-appstore` (poussée sur `origin`)

---

## Pièges à connaître avant de toucher au projet

1. **`Config/Secrets.xcconfig` est ignoré par git et indispensable.**
   S'il manque, `xcodegen generate` **échoue en affichant une erreur de validation
   puis rend la main sans rien régénérer** — et `xcodebuild` continue de compiler
   l'ancien `.pbxproj`, donc les modifications de `project.yml` semblent sans effet.
   Ce piège a déjà coûté plusieurs builds. Contenu attendu :

   ```
   REVENUECAT_API_KEY = appl_oaSoXDthjPsueYemDRZXvOetCxL
   POSTHOG_API_KEY =
   POSTHOG_HOST = https:/$()/eu.i.posthog.com
   ```

   Le `$()` au milieu de l'URL est volontaire : `//` démarre un commentaire en xcconfig.

2. **Le dépôt GitHub a été renommé `MacTrack` → `AirPad`.** Le remote local dit
   encore `MacTrack.git` (GitHub redirige). Les URL réelles sont sous
   `abdouldotdev/AirPad`.

3. **Toujours `xcodegen generate` après avoir modifié `project.yml`**, et vérifier
   la sortie plutôt que de la rediriger vers `/dev/null`.

4. **Le serveur macOS ne peut pas être signé en Debug avec la signature auto.**
   Passer `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application"`.

5. **Espace disque tendu (~3,7 Go).** Nettoyer `build/`, `~/Library/Developer/Xcode/DerivedData/AirPad-*`
   et `/tmp/airpad-dmg` en fin de tâche. Ne pas créer de simulateur superflu.

---

## 0. Ce qui a changé en session 3 — À LIRE

### Le modèle économique a changé : hard paywall INTÉGRAL

Le handoff précédent disait « trackpad gratuit, clavier payant ». **C'est faux
maintenant.** Décision de l'utilisateur, verbatim : « pour accéder au feature il
faut un abonnement. même free trial ça suffit. »

- `PremiumFeature.keyboard` couvre clavier **et** trackpad (une seule ligne dans
  la table du paywall : les séparer faisait passer le trackpad pour un accessoire
  alors que c'est la fonction principale).
- Sans abonnement, `AirPadView` n'affiche **pas** la surface de contrôle : elle
  est remplacée par `TryFreeView`. Ne pas remettre de flou ni de panneau flottant
  par-dessus le trackpad — cela a été explicitement rejeté deux fois.
- `Store/listing-en-US.md` et `Store/review-notes.md` ont été réécrits en
  conséquence. **Ne pas revenir à la version « trackpad gratuit ».**

### Direction artistique

- **Bleu `Brand.accent`** = l'app (onboarding, connexion, réglages).
- **Or et argent `Premium.*`** = tout ce qui touche à l'abonnement.
- Les couleurs sémantiques (vert connecté, rouge erreur) ne servent **qu'aux
  états**, jamais à décorer. L'onboarding avait quatre teintes différentes ;
  il n'en a plus qu'une.
- Un métal a besoin d'un reflet : `goldSheen` / `silverSheen` sont des dégradés
  dans **une seule matière**, ce n'est pas un retour au bicolore.
- `ProWordmark` compose « AirPad **Pro** » + couronne. L'utiliser partout plutôt
  que de recomposer le lockup à la main.

### Fichiers ajoutés
| Fichier | Rôle |
|---|---|
| `Client/Theme.swift` | `Brand`, `Premium`, `ProWordmark` |
| `Client/Paywall/TryFreeView.swift` | Page affichée sans abonnement : grande illustration animée en angle, « We want you to use AirPad for free. », CTA « Try it now » |

### Débloquer Pro sans achat
Réglages → section **Debug** → *Débloquer AirPad Pro* (`SubscriptionManager.debugUnlock`,
persisté dans `UserDefaults`). Compilé uniquement en Debug. Sert à filmer la démo.

### Pièges rencontrés en session 3
1. **`xcodebuild` sort en code 0 alors que le build a échoué** (mauvais
   identifiant d'appareil). Toujours vérifier la présence de `BUILD SUCCEEDED`
   dans la sortie, jamais le code retour seul.
2. **`devicectl` et `xcodebuild` n'utilisent pas le même identifiant.**
   `xcrun devicectl list devices` donne un UUID CoreDevice ; `xcodebuild` veut
   l'UDID matériel, donné par `xcrun xctrace list devices`.
   iPhone 15 Pro d'Abdoul : **`00008130-000E35182861401C`** (iOS 26.5).
3. **Espace disque critique** (~2 Go). Un build device pèse ~2 Go. Purger
   `~/Library/Developer/Xcode/DerivedData`, `~/Library/Caches/org.swift.swiftpm`
   et `/tmp/airpad-dd` avant de compiler.
4. **Nouveau fichier Swift ⇒ `xcodegen generate` obligatoire**, sinon
   « cannot find X in scope » : le `.pbxproj` liste les fichiers explicitement.
5. **L'extension Chrome de Claude ne se connecte pas** malgré une installation
   dans Chrome *et* dans Arc. `list_connected_browsers` renvoie `[]`.
   Ne pas y passer du temps : la fiche App Store se crée à la main de toute façon,
   **l'API d'Apple n'a pas de `create_app`**.
6. **TCC et Accessibilité** : remplacer le binaire d'une app déjà autorisée
   invalide l'octroi, et la case reste cochée dans les Réglages Système en ne
   s'appliquant à rien. Remède : `tccutil reset Accessibility com.abdouldotdev.AirPadServer`,
   puis re-autoriser. L'app Mac vit dans `/Applications/AirPadServer.app`.

## 1. Bugs — terminé

Tous corrigés, vérifiés par build et par la suite de tests du protocole.

### Serveur (`Server/Sources/Server/`)
| Bug | Avant | Après |
|---|---|---|
| Autorisation Accessibilité | Jamais demandée ; `CGEvent.post` échouait en silence | `AccessibilityManager` sonde l'état, bannière dans la fenêtre + entrée de menu, lien direct vers les Réglages |
| `start(port:)` | `8080` codé en dur, paramètre ignoré | Le port reçu est utilisé |
| Découpage TCP | `split("\n")` sans reliquat : commande coupée entre deux paquets perdue | Tampon d'accumulation `drainBuffer()` + garde-fou 1 Mo |
| Cycle de vie des connexions | Aucun `stateUpdateHandler` : « Connecté » restait affiché, `stop()` ne coupait rien, plusieurs clients simultanés | Connexion active unique, arbitrage, déconnexion propagée, `stop()` coupe réellement |
| Modificateurs | Aucun support des flags | `K:<code>:<état>:<flags>` applique `CGEventFlags` |
| Curseur hors écran | Pouvait sortir de l'écran | Borné à l'écran courant |
| `DENIED` jamais reçu | `cancel()` juste après `send()` coupait avant l'envoi | Fermeture déplacée dans le complétion d'envoi (**trouvé par les tests**) |

### Client (`Client/`)
| Bug | Avant | Après |
|---|---|---|
| `isConnected` bloqué à vrai | Ni heartbeat ni gestion de `.waiting` | PING/PONG toutes les 2 s, seuil à 6 s, `.waiting` traité, reconnexion à palier progressif |
| Modificateurs ⇧⌘⌥⌃ | `down` puis `up` sur le même appui → ⌘C et ⌘V impossibles | Modificateurs à bascule : appui = armé pour la touche suivante, double appui = verrouillé |
| `rowSpace` | Code mort, jamais rendu | Supprimé, remplacé par `modifierRow` réellement affichée |
| Barre d'espace | Libellé vide | Libellée `space` |
| Rangées QWERTY | Une touche de moins que l'AZERTY | `;` et `,` ajoutés, rangées symétriques |
| Keycodes AZERTY | Suspectés faux | **Vérifiés corrects** (codes positionnels : M=41, `,`=46, `;`=43) — aucun changement nécessaire |
| Aperçu caméra | `UIScreen.main.bounds` dans une vue de 180 pt → déformé | `CameraPreviewView` dont la couche *est* l'aperçu |
| Session caméra | Jamais arrêtée | Arrêtée dans `dismantleUIView` et après lecture |
| Refus caméra | Rectangle noir muet | Message explicite + bouton vers les Réglages |
| Sécurité | N'importe qui sur le Wi-Fi pilotait le Mac | Code d'appairage 8 caractères dans le QR, `AUTH` obligatoire, délai de 5 s |
| iPad | `TARGETED_DEVICE_FAMILY` implicite | `1,2` + orientations iPad ; clavier borné à 620 pt et centré |
| README | Annonçait UDP | Corrigé en TCP + tableau du protocole |

### Vérification
`python3 Tests/protocol_test.py` avec l'app Mac lancée → **9/9**
(refus sans AUTH, mauvais code, bon code, PONG, commande coupée en deux paquets,
deux commandes groupées, arbitrage du second client, INIT, libération de la place).

---

## 2. Captures — partiel

Dossier : `~/Desktop/AirPad-Captures/`

Faites, en 1320×2868 (format iPhone 6.9" exact) :
`01-onboarding-1`, `02-pairing`, `03-remote-free`, `04-keyboard-qwerty`,
`05-keyboard-azerty`, `06-trackpad`, `07-paywall`, `08-settings`,
plus `10-mac-window.png` (fenêtre Mac avec QR, code et bannière Accessibilité).

Ajoutées en session 2 :
`01b-onboarding-2`, `01c-onboarding-3` (iPhone), `11-mac-menubar.png` (menu de la
barre de menus macOS, ouvert), et la série iPad 13" complète en **2064×2752** :
`ipad-01-onboarding`, `ipad-02-pairing`, `ipad-03-trackpad`, `ipad-04-keyboard-qwerty`,
`ipad-05-keyboard-azerty`, `ipad-06-remote-free`, `ipad-07-settings`.

**Reste à faire** : refaire `07-paywall` une fois les produits App Store créés
(il affiche aujourd'hui « offres indisponibles »).

⚠️ **Piège des captures simulateur** : l'écran `pairing` déclenche la demande
d'accès caméra, et cette alerte système **reste affichée par-dessus toutes les
captures suivantes**. `simctl privacy … grant camera` ne la referme pas une fois
présentée. Il faut désinstaller l'app, relancer SpringBoard
(`xcrun simctl spawn <dev> launchctl kickstart -k system/com.apple.SpringBoard`),
réinstaller, puis accorder la caméra **avant** la première capture.

⚠️ **`rtk` casse les pipelines** : `rtk find` / `rtk grep` sont des équivalents
sémantiques, pas des remplacements shell — `rtk find … | head` renvoie du texte
inutilisable et `rtk ls | rtk grep x` cherche dans le dépôt au lieu de stdin.
Pour ces cas, utiliser `/usr/bin/find`, `/usr/bin/grep` en chemin absolu.

### Mode capture
L'app accepte un argument de lancement, actif en Debug uniquement
(`Client/Services/CaptureMode.swift`). Depuis la session 2, `onboarding-1`,
`onboarding-2` et `onboarding-3` ouvrent l'onboarding directement sur la page
voulue — sans ça les écrans 2 et 3 ne sont atteignables qu'en balayant à la main.

```sh
xcrun simctl launch <device> com.abdouldotdev.AirPadClient -capture keyboard
```

Écrans : `onboarding`, `pairing`, `free`, `keyboard`, `keyboard-azerty`,
`trackpad`, `paywall`, `settings`, `settings-pro`.
Il force un Mac appairé factice, un abonnement simulé et l'état « Connecté ».

Simulateur iPhone déjà créé : **AirPad-iPhone69** (iPhone 17 Pro Max, iOS 26.2).
Pour l'iPad, réutiliser **« Montaj iPad Captures »** (iPad Pro 13" M5, même
résolution) puis désinstaller l'app — ne pas créer un simulateur de plus,
l'espace disque ne le permet pas.

---

## 3. Abonnements — code fait, produits store à créer

Arbitrages validés par l'utilisateur :
- **Paywall dur** : trackpad (déplacement, clics, défilement) gratuit ; **tout le
  clavier** est payant, avec F1-F12, vitesse du curseur, multi-Mac et gestes 3-4 doigts.
- **Essai gratuit : 3 jours, sur l'annuel uniquement.**
- Tarifs : Weekly 4,99 USD, Yearly 14,99 USD, un seul groupe d'abonnement.

⚠️ **Conséquence à ne pas oublier** : la description App Store doit annoncer
explicitement que le clavier est une fonction d'abonnement. La promesse
« trackpad + clavier » sans mention de l'abonnement est un rejet 2.3.1 assuré.

Implémenté : `PaywallView` (SwiftUI natif, sélection de plan, essai mis en avant,
restauration, mention du renouvellement automatique, liens CGU/confidentialité),
`SubscriptionManager`, verrouillage par `PremiumFeature`, retour au palier gratuit
quand l'abonnement expire.

---

## 4. RevenueCat — configuré, tests sandbox à faire

| Élément | Valeur |
|---|---|
| Projet | `proj1739160d` (AirPad) |
| App iOS | `app13381f86a3` (bundle `com.abdouldotdev.AirPadClient`) |
| Clé publique SDK | `appl_oaSoXDthjPsueYemDRZXvOetCxL` |
| Entitlement | `airpad_pro` → `entl7c59d008bf` (**pas `premium`**) |
| Produit weekly | `airpad_pro_weekly` → `prod1834b02439` |
| Produit yearly | `airpad_pro_yearly` → `prod57d29e5d4d` |
| Offering | `default` → `ofrng1ecb46faff` (courant) |
| Package annuel | `$rc_annual` → `pkgebdb6f5a86e` |
| Package hebdo | `$rc_weekly` → `pkgec618be6224` |

SDK lié via SPM (`purchases-ios` 5.x), clé injectée par xcconfig, build vérifié.

**Reste à faire** : créer les produits côté App Store Connect avec **exactement**
ces identifiants, renseigner la clé API App Store Connect et le secret partagé
dans RevenueCat (`app_store_connect_api_key_configured: false` aujourd'hui), puis
tester réellement en bac à sable : achat weekly, achat yearly, restauration,
statut d'entitlement. **Ne rien conclure sans avoir vu le résultat.**

---

## 5. PostHog — code fait, clé manquante

`Client/Services/Analytics.swift` : instrumentation complète écrite (cycle de vie,
appairage QR vs manuel avec délai jusqu'à la première connexion, usage réel,
erreurs réseau, entonnoir du paywall) et propriétés de profil persistantes
(modèle matériel, iOS, langue, pays, disposition, version, première session,
nombre de sessions, statut d'abonnement, Mac appairé anonymisé).
Noms d'événements centralisés dans `enum Event`. Interrupteur dans les réglages.

Règles respectées : ni IP locale, ni nom de réseau, ni contenu frappé — les frappes
ne sont comptées qu'en volume, et l'identifiant matériel remplace le nom d'appareil
choisi par l'utilisateur (qui contient souvent un prénom).

**Bloqué** : l'authentification OAuth du MCP PostHog n'a pas été menée à son terme,
le serveur s'est déconnecté. Relancer `mcp__posthog__authenticate`, créer le projet,
récupérer la clé `phc_…` et la mettre dans `Config/Secrets.xcconfig`.
Sans clé, `Analytics.configure` ne fait rien et l'app fonctionne normalement.

---

## 6. Pages légales — terminé

Branche orpheline `gh-pages`, GitHub Pages actif. Bilingue EN/FR avec bascule
mémorisée, responsive, thème clair et sombre. Contenu aligné sur ce que collectent
réellement PostHog et RevenueCat.

- https://abdouldotdev.github.io/AirPad/ → **200**
- https://abdouldotdev.github.io/AirPad/privacy.html → **200**
- https://abdouldotdev.github.io/AirPad/terms.html → **200**

Ces URL sont déjà câblées dans l'app (`LegalLinks`).

---

## 7. Fiche App Store — à faire

Fait : bundle IDs enregistrés.
- `com.abdouldotdev.AirPadClient` → `G67MZP3AM2`
- `com.abdouldotdev.AirPadServer` → `2Q7UN32M69`

**Bloqué** : la session App Store Connect est expirée dans Chrome et l'API ne
permet pas de créer une fiche (`create_app` n'existe pas). L'utilisateur doit se
connecter sur appstoreconnect.apple.com ; **ne jamais saisir son mot de passe à sa
place**. Une fois la fiche créée, tout le reste passe par le MCP `appstore-connect`
(c'est la demande explicite de l'utilisateur) : localisations, catégories, âge,
captures, groupe d'abonnement, produits, prix, notes de review, soumission.

Langue : **fiche en anglais** (locale primaire `en-US`).

**Tous les textes sont déjà rédigés et versionnés** dans `Store/` :
- `Store/listing-en-US.md` — nom, sous-titre, texte promotionnel, mots-clés
  (exactement 100 caractères), description, nouveautés, URL, catégories, âge.
  La description annonce explicitement que le clavier relève de l'abonnement.
- `Store/review-notes.md` — notes de review complètes (installation du compagnon
  Mac, autorisation Accessibilité, appairage, ce qui est gratuit vs payant).
- `Store/demo-video.md` — découpage de la vidéo à joindre.

Il n'y a donc plus rien à rédiger : une fois la fiche créée, tout se pousse
par le MCP à partir de ces fichiers.

⚠️ **Risque de rejet n°1** : le reviewer n'aura pas de Mac appairé. Prévoir dans
les notes de review une explication du fonctionnement en réseau local **et une
vidéo de démonstration**, sans quoi le rejet est quasi certain.

---

## 8. macOS — terminé

- Signé **Developer ID Application: Abdoul Rachid Tapsoba (HZ3366WY57)**
- Hardened runtime + horodatage, App Sandbox volontairement désactivé
  (il bloquerait l'injection d'événements globaux — l'app ne peut donc pas aller
  sur le Mac App Store, ce qui confirme le choix de distribution hors store)
- **Notarisée** (`Accepted`) et **staplée** ; `spctl` → `accepted, source=Notarized Developer ID`
- DMG 2,2 Mo avec fond dessiné, icône positionnée et lien `/Applications`
- Release : https://github.com/abdouldotdev/AirPad/releases/tag/v1.0.0 (DMG en 200)
- Lien de téléchargement câblé dans l'app iOS et sur la page d'accueil

Profil de notarisation déjà dans le trousseau sous le nom **`AirPad`**
(clé `AuthKey_KNDK6PLN5H`, issuer récupéré dans le `.env` du MCP appstore-connect).
Commande : `xcrun notarytool submit <dmg> --keychain-profile "AirPad" --wait`

⚠️ Toujours passer par `xcodebuild archive` + `-exportArchive` avec
`ExportOptions.plist` en `developer-id`. Un simple `build` ajoute l'entitlement
`get-task-allow` et **la notarisation est refusée** (déjà rencontré).

---

## Ce qui attend une action de l'utilisateur

1. Se connecter à App Store Connect dans Chrome (fiche à créer à la main).
2. Terminer l'OAuth PostHog pour obtenir la clé `phc_…`.
3. Créer un compte de test bac à sable pour les achats.
4. Renseigner la clé API App Store Connect dans RevenueCat.
5. Fournir une vidéo de démonstration pour les notes de review (ou valider que
   l'agent en produise une depuis le simulateur).
