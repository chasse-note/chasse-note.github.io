# Chasse Note — carnet de chasse partagé

Carnet de chasse en ligne : sessions, espèces (vues, tuées, blessées, perdues), passages, statistiques par saison, export Excel/JSON — et maintenant **comptes, synchronisation entre appareils et classement du groupe**.

- **Fonctionne hors ligne** : à la chasse sans réseau, tout s’enregistre sur le téléphone et part en ligne au retour du réseau.
- **S’installe comme une appli** : dans Chrome Android, menu ⋮ → *Ajouter à l’écran d’accueil*.
- **Vie privée** : chaque carnet complet est privé. Le groupe ne voit que les totaux par saison et les espèces — jamais les lieux, compagnons, armes ou notes.
- **Administration** : le premier compte créé devient administrateur. Les inscrits suivants sont « en attente » jusqu’à ce que l’administrateur les valide (onglet **Groupe**).

---

## Mise en ligne (≈ 20 minutes, une seule fois)

### 1. Supabase — la base de données des comptes (gratuit)

1. Créez un compte sur **supabase.com** → *New project*. Nom : `chasse-note`, région : **Europe (Paris ou Francfort)**. Notez le mot de passe de base de données quelque part (il ne servira pas dans le site).
2. Dans le projet : **SQL Editor** → *New query* → collez tout le contenu de `schema.sql` → **Run**. Vous devez voir « Success ».
3. **Project Settings → API** (ou bouton *Connect*) : copiez
   - la **Project URL** (`https://xxxx.supabase.co`)
   - la clé **publishable** (ou *anon public*). ⚠️ Jamais la clé *secret* / *service_role*.
4. Ouvrez `config.js` et collez ces deux valeurs entre les guillemets.

### 2. GitHub Pages — l’hébergement du site (gratuit)

1. Sur github.com : **New repository** → nom `chasse-note` → **Public** → *Create repository*.
2. Cliquez **uploading an existing file**, puis glissez **tout le contenu** du dossier (`index.html`, `config.js`, `sw.js`, `manifest.webmanifest`, les icônes, `schema.sql`, `recuperer-donnees.html`, ce `README.md`) → *Commit changes*.
3. **Settings → Pages** → *Source : Deploy from a branch* → branche **main**, dossier **/ (root)** → *Save*.
4. Après 1 à 2 minutes, le site est en ligne à l’adresse :
   `https://VOTRE-PSEUDO-GITHUB.github.io/chasse-note/`

### 3. Relier les deux

Dans Supabase : **Authentication → URL Configuration**
- *Site URL* : `https://VOTRE-PSEUDO-GITHUB.github.io/chasse-note/`
- *Redirect URLs* : ajoutez la même adresse.

Sans cette étape, les liens de confirmation d’e-mail renverraient vers une mauvaise adresse.

### 4. Créez VOTRE compte en premier

Ouvrez le site → **Réglages → Compte & partage** → e-mail, mot de passe, pseudo → **Créer un compte** → cliquez le lien reçu par e-mail → connectez-vous.
Le premier compte devient **administrateur** automatiquement. Faites-le avant de partager le lien.

> Si quelqu’un s’est inscrit avant vous par erreur : dans Supabase → SQL Editor, lancez
> `update public.profils set role='admin', statut='actif' where id = (select id from auth.users where email = 'votre@email.fr');`

---

## Récupérer les données de l’ancien carnet (téléphone)

Les données de l’ancien fichier `indexchasse.html` sont rangées dans Chrome, liées à ce fichier. Le nouveau site a une autre adresse, il ne peut donc pas les lire tout seul. Il faut les exporter puis les importer :

1. **Avant tout, ne videz pas les données de Chrome** et ne supprimez pas l’ancien fichier.
2. Sur le téléphone, ouvrez l’ancien `indexchasse.html` dans Chrome (comme d’habitude).
3. **Réglages → Exporter JSON** : un fichier `chasse-note-AAAA-MM-JJ.json` arrive dans *Téléchargements*. (Faites aussi *Exporter Excel* : double sécurité.)
4. Ouvrez le nouveau site, **connectez-vous**, puis **Réglages → Importer un fichier** → choisissez le `.json`.
5. Le carnet est importé **et envoyé sur votre compte** : il apparaît aussi sur tous vos autres appareils.

**Plan B** si l’ancien fichier ne s’ouvre plus : copiez `recuperer-donnees.html` dans le même dossier que l’ancien `indexchasse.html` sur le téléphone et ouvrez-le avec Chrome de la même façon. Il lit les données restées dans le navigateur et propose de télécharger la sauvegarde.

---

## Inviter les autres chasseurs

1. Envoyez-leur le lien du site.
2. Ils créent leur compte (Réglages → Compte & partage) et importent leur propre carnet si besoin.
3. Vous les voyez dans **Groupe → Administration** : **Valider**, **Refuser/Bloquer**, ou **Nommer admin**.
4. Chaque membre peut choisir de ne pas apparaître dans le classement (case dans son profil).

## Mettre à jour le site plus tard

Remplacez le fichier modifié sur GitHub (*Add file → Upload files*). Si vous changez `index.html`, changez aussi la ligne `VERSION` de `sw.js` (ex. `chasse-note-v3`) pour que les téléphones prennent la nouvelle version.

## Ce qui est stocké où

| Donnée | Où | Qui la voit |
|---|---|---|
| Carnet complet (sessions, lieux, notes, compagnons, armes, réglages) | Téléphone + table `carnets` | Vous seul |
| Totaux par saison et espèces | Table `stats_saison` | Membres validés (si « apparaître au classement » est coché) |
| Pseudo, secteur | Table `profils` | Membres validés |
| E-mail | Comptes Supabase | Vous seul + administrateurs |
