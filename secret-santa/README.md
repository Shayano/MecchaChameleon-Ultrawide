# 🎅 Secret Santa

Petite app pour organiser un Secret Santa en famille ou entre amis, hébergée gratuitement sur un Cloudflare Worker.

## Fonctionnalités

* Création d'un groupe : nom, budget, date, message, participants.
* Exclusions : une ligne par couple ou foyer (`Alice, Bob`), ces personnes ne se tirent pas entre elles.
* Tirage au sort automatique, aléatoire et équitable.
* Un **lien organisateur** secret et un **lien perso** par participant, à envoyer par WhatsApp, SMS ou copier/coller.
* Chaque participant découvre à qui il offre un cadeau et écrit sa liste d'idées (visible seulement par la personne qui lui offre).
* L'organisateur voit qui a ouvert son lien, sans voir les tirages.
* Modifier les participants (les liens existants restent valables), refaire le tirage, supprimer le groupe.
* Aucun compte ni email nécessaire. Les données expirent automatiquement après environ 13 mois.

## Déployer (5 minutes)

Prérequis : Node.js 18+ et un compte Cloudflare gratuit.

```bash
cd secret-santa
npm install
npx wrangler login
npx wrangler deploy
```

Au premier déploiement, wrangler crée automatiquement l'espace de stockage KV `SANTA` et affiche l'URL de l'app (`https://secret-santa.<ton-sous-domaine>.workers.dev`).

Tester en local : `npm run dev` puis ouvrir http://localhost:8787.

## Utilisation

1. Ouvre l'app, remplis le formulaire, clique sur « Créer le groupe et faire le tirage ».
2. **Ajoute le lien organisateur à tes favoris**, c'est le seul moyen de revenir gérer le groupe.
3. Envoie à chacun son message (bouton WhatsApp, SMS ou « Copier le message »).
4. Chacun ouvre son lien, clique sur « Découvrir » et remplit sa liste d'idées.

Si tu participes aussi, évite d'ouvrir les liens des autres depuis l'espace organisateur.

## Technique

* Un seul fichier `src/index.js`, aucune dépendance, pages rendues côté serveur.
* Stockage Cloudflare KV, liens protégés par des jetons aléatoires de 128 bits.
* Contenu utilisateur échappé, CSP stricte, pages non indexées.
* Plan gratuit Cloudflare largement suffisant (KV : 1 000 écritures et 100 000 lectures par jour).
