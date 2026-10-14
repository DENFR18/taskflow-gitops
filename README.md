# taskflow-gitops — dépôt GitOps du cours CI/CD M2

Ce dépôt décrit **l'état voulu** de l'application TaskFlow dans Kubernetes.
Argo CD le surveille et aligne le cluster dessus : pour changer la production,
on ne tape pas de commande, on fait une **Pull Request**.

## Installation (à faire chez vous, avant le cours)

Prérequis : Docker Desktop démarré, 8 Go de RAM, 10 Go de disque libre.
Sous Windows : WSL2 (Ubuntu) + intégration WSL de Docker Desktop, et toutes les commandes dans WSL.

```bash
git clone https://github.com/9m7fjfpv9k-cyber/taskflow-gitops.git
cd taskflow-gitops
./scripts/install.sh
```

Le script crée un cluster local `kind`, installe Argo CD et Argo Rollouts,
puis télécharge les images des labs. Comptez 5 à 15 minutes.
Il peut être relancé sans risque.

> **Note sur notre environnement.** Sur le poste de Denilsson, le trafic HTTPS sortant de WSL2 est bloqué par la politique de sécurité du poste (DNS et ICMP fonctionnent, TCP 443 expire, y compris en mode réseau mirrored). L'installation a donc été faite directement sous Windows avec un équivalent PowerShell de `install.sh`, en passant par Docker Desktop : même cluster `kind-cicd`, Argo CD v3.5.3 et Argo Rollouts v1.10.0.

## Structure

| Chemin | Rôle |
| --- | --- |
| `apps/taskflow/` | Les manifests surveillés par Argo CD |
| `argocd/application.yaml` | Déclare l'application dans Argo CD |
| `exemples/bluegreen/` | Manifests pour le déploiement Blue-Green |
| `exemples/canary/` | Manifests pour le déploiement Canary |
| `exemples/robustesse/` | Canary avec test de charge k6 automatique, modèle de postmortem |
| `exemples/ci/` | Pipelines de la mini-PSSI (GitHub Actions et GitLab CI) |
| `policies/` | Mini-PSSI et règles Rego vérifiées par conftest |
| `scripts/install.sh` | Installation de l'environnement |
| `scripts/argocd-ui.sh` | Ouvre l'interface d'Argo CD |
| `scripts/observe.sh` | Montre quelle version répond, et avec quel code HTTP |
| `scripts/charge.sh` | Lance à la main le test de charge k6 contre un service |

## Images disponibles

`ghcr.io/9m7fjfpv9k-cyber/taskflow` en versions `1.0.0`, `1.1.0`, `2.0.0`, `2.1.0` et `2.2.0`.

## Équipe

<!-- Noms du binôme -->
- Denilsson ([@DENFR18](https://github.com/DENFR18)) : propriétaire du fork
- Illies ([@IB432](https://github.com/IB432)) : collaborateur (write)

---

## Lab du matin : déployer par PR, provoquer une dérive, revenir en arrière

### Configuration

L'application Argo CD (`argocd/application.yaml`) pointe sur notre fork :

| Paramètre | Valeur | Effet |
|---|---|---|
| `repoURL` | `https://github.com/DENFR18/taskflow-gitops.git` | Argo CD suit notre fork |
| `targetRevision` | `main` | Seule la branche protégée est déployée |
| `path` | `apps/taskflow` | Dossier des manifests (Deployment de 4 replicas + Service) |
| `automated` | activé | Synchronisation automatique, sans clic |
| `selfHeal` | `true` | Toute modification manuelle du cluster est annulée |
| `prune` | `true` | Une ressource supprimée de Git est supprimée du cluster |
| `timeout.reconciliation` | `60s` | Argo CD relit Git toutes les 60 s (réglé par `install.sh`) |

La branche `main` est protégée par un ruleset : PR obligatoire, 1 approbation, force push et suppression interdits. Chaque changement de cet exercice est passé par une PR approuvée par le binôme.

### Étapes

1. **Mise en service.** Après la modification du `repoURL` (PR #2, commit `abcc67a`), `kubectl apply -f argocd/application.yaml` : l'application passe en **Synced / Healthy** avec 4 pods en 1.0.0.

   ![Application Synced et Healthy dans Argo CD](docs/images/argocd-synced-healthy.png)

2. **Déploiement de la 2.0.0 par PR (#3).** L'image est définie dans `apps/taskflow/deployment.yaml`. Son tag passe de `1.0.0` à `2.0.0`.

   ![Ligne image dans deployment.yaml](docs/images/manifests-image.png)

   Après le merge, Argo CD détecte le nouveau commit et Kubernetes effectue un rolling update : les pods 2.0.0 démarrent avant l'arrêt des pods 1.0.0, sans coupure de service.

   ![Rolling update vers la 2.0.0](docs/images/rolling-update-2.0.0.png)

3. **Dérive 1 : `kubectl scale --replicas=1`.** Argo CD détecte l'écart dans la seconde et réapplique les 4 replicas définis dans Git. Les pods `Succeeded` sont ceux arrêtés par le `scale`, les pods `Pending` ceux recréés par Argo CD.

   ![Retour automatique à 4 replicas](docs/images/derive-scale.png)

4. **Dérive 2 : `kubectl set image ...:1.1.0`.** L'application passe en **OutOfSync**, puis Argo CD réapplique l'image 2.0.0.

   ![Dérive d'image détectée](docs/images/derive-set-image.png)

   Chaque dérive suit le même cycle dans les événements de l'application : `Synced -> OutOfSync`, `Initiated automated sync`, `Partial sync operation succeeded` (seul le Deployment modifié est réappliqué), puis `Progressing -> Healthy`.

   ![Cycles de self-heal](docs/images/selfheal-describe.png)

5. **Retour en 1.0.0 avec le bouton Revert de GitHub (PR #4).** Le revert passe par le même circuit qu'un déploiement : la PR est bloquée tant que le binôme ne l'a pas approuvée.

   ![PR de revert en attente de review](docs/images/pr-revert.png)

   Après le merge (commit `19ce3cb`), les pods reviennent en 1.0.0 avec le même ReplicaSet qu'au départ (`taskflow-76547969d7`) : le modèle de pod est identique à l'original.

   ![Retour en 1.0.0 après le revert](docs/images/revert-1.0.0.png)

Les événements de l'application Argo CD retracent toute la séquence (heures en UTC, soit Paris − 2 h) :

![Événements Argo CD](docs/images/events-argocd.png)

### Journal des déploiements

Heures de Paris. Les heures de merge proviennent des commits de merge (`git log`), celles de synchronisation des événements Argo CD.

| Heure | Action | Commit / PR | Version attendue (Git) | État Argo CD | Délai observé |
|---|---|---|---|---|---|
| 12:22:00 | `kubectl apply` de l'Application | PR #2 (`abcc67a`) | 1.0.0 | Synced / Healthy | — |
| 13:35:17 | Merge PR image 2.0.0 | PR #3 (`5247aa8`) | 2.0.0 | Sync auto à 13:36:09, Healthy à 13:36:21 | Détection en 52 s, déploiement complet en 1 min 04 s |
| 13:39:13 | `kubectl scale --replicas=1` (dérive) | — | 4 replicas | OutOfSync → sync auto immédiate → Healthy à 13:39:20 | Correction en 0 s, retour à 4 pods en 7 s |
| 13:41:10 | `kubectl set image ...:1.1.0` (dérive) | — | 2.0.0 | Corrigé à 13:41:10 ; nouvel OutOfSync à 13:41:24, re-sync à 13:42:04, Healthy à 13:42:11 | 0 s, puis 40 s sur le second cycle |
| 13:45:54 | Merge PR Revert (bouton GitHub) | PR #4 (`19ce3cb`) | 1.0.0 | Sync auto à 13:46:29, Healthy à 13:46:37 | Détection en 35 s, retour complet en 43 s |

Heures de merge relevées avec `git log` :

![Heure du merge de la 2.0.0](docs/images/git-log-2.0.0.png)

![Heure du merge du revert](docs/images/git-log-revert.png)

### Réponses

**Push ou pull ?**

Pull. Aucun outil ne pousse les changements vers le cluster : c'est Argo CD, installé dans le cluster, qui relit régulièrement le dépôt Git et applique ce qui a changé. Les mesures le montrent : après un merge, le déploiement n'est pas immédiat, il arrive au prochain cycle de lecture (52 s pour la 2.0.0, 35 s pour le revert, toujours sous les 60 s de `timeout.reconciliation`). Conséquence côté sécurité : GitHub n'a besoin d'aucun accès au cluster, c'est le cluster qui vient chercher l'état voulu.

**Qui a corrigé quoi ?**

Les modifications manuelles faites avec `kubectl` ont été corrigées par **Argo CD**, grâce à `selfHeal` : le passage à 1 replica et le changement d'image vers 1.1.0 ont été annulés dans la seconde, par une synchronisation partielle qui réapplique uniquement le Deployment modifié. Sur la dérive d'image, une seconde détection n'a été corrigée qu'après 40 s ; nous l'interprétons comme un délai croissant appliqué par Argo CD entre deux self-heals successifs, sans l'avoir vérifié dans la documentation. Le retour de la 2.0.0 vers la 1.0.0, lui, a été décidé et fait par **nous**, via une PR de revert relue et approuvée : Argo CD n'a fait qu'appliquer ce que Git contenait.

**Pourquoi git revert ?**

`git revert` ajoute un nouveau commit qui annule le précédent, sans réécrire l'historique. Le retour arrière passe donc par le même circuit qu'un déploiement : PR, approbation du binôme, ruleset (le force push étant interdit sur `main`, un `git reset` ne serait de toute façon pas possible). L'historique garde la trace de qui a annulé quoi et quand, et Git reste la seule source de vérité. À l'inverse, un `kubectl rollout undo` serait une dérive comme les autres, qu'Argo CD annulerait immédiatement grâce au self-heal.
---

## Lab de l'après-midi : Blue-Green, Canary et version défectueuse

Heures de Paris. Le Deployment est remplacé par un **Rollout** Argo Rollouts (`apps/taskflow/rollout.yaml`), toujours déployé par PR via Argo CD.

### 1. Blue-Green

**Mise en place (PR #6, merge à 14:48:08).** Le Deployment devient un Rollout en stratégie BlueGreen, avec un service `taskflow` (actif) et un service `taskflow-preview`. Argo CD synchronise et l'application repasse en Healthy.

![Rollout BlueGreen en 1.0.0](docs/images/bg-rollout-1.0.0.png)

![Synchronisation Argo CD après la PR #6](docs/images/bg-pr6-sync.png)

![Tous les appels répondent en 1.0.0](docs/images/bg-observe-1.0.0.png)

**Déploiement de la 1.1.0 (PR #7, merge à 14:55:09).** La nouvelle version démarre en parallèle (8 pods au total) et le Rollout se met en pause (`BlueGreenPause`) : la 1.0.0 reste `stable, active`, la 1.1.0 est seulement `preview`.

![Rollout en pause, 1.1.0 en preview](docs/images/bg-paused-preview.png)

Les deux services répondent en même temps, chacun avec sa version : le trafic des utilisateurs reste sur la 1.0.0 pendant qu'on teste la 1.1.0 via le service de preview.

![taskflow en 1.0.0, taskflow-preview en 1.1.0](docs/images/bg-observe-deux-versions.png)

**Promotion à 14:56:32** avec `kubectl argo rollouts promote`. Le basculement est instantané : les 40 requêtes suivantes répondent toutes en 1.1.0.

![Promotion et bascule en 1.1.0](docs/images/bg-apres-promote.png)

Après la promotion, la 1.1.0 est `stable, active` et l'ancien ReplicaSet (1.0.0) est réduit à zéro.

![État final Blue-Green](docs/images/bg-final-1.1.0.png)

![Services taskflow et taskflow-preview](docs/images/bg-services.png)

### 2. Canary

**Passage en Canary (PR #8, merge à 15:03:30).** Les étapes sont : 25 % puis pause manuelle, 50 % pendant 60 s, 75 % pendant 30 s, puis 100 %. Sans maillage de service, la part de trafic suit la proportion de pods (4 replicas : 25 % = 1 pod sur 4).

![Rollout Canary en 1.1.0 (étape 6/6)](docs/images/canary-initial-1.1.0.png)

![Heures de merge des PR #7 et #8](docs/images/canary-heures-merge.png)

**Déploiement de la 2.0.0 (merge à 15:12:40).** Le Rollout s'arrête à l'étape 1/6 : 1 pod en 2.0.0 (canary) et 3 pods en 1.1.0 (stable), soit 25 % du trafic.

![Canary en pause à 25 %](docs/images/canary-paused-25.png)

Sur 40 requêtes, 12 répondent en 2.0.0 et 28 en 1.1.0 : la répartition suit à peu près les 25 %.

![Répartition 28 / 12](docs/images/canary-observe-25.png)

**Promotions.** Une première promotion à 15:13:46 lance les paliers suivants, une seconde à 15:14:11 termine le déploiement. Après la première, 32 requêtes sur 40 répondent déjà en 2.0.0, puis toutes après la seconde.

![Première promotion à 15:13:46](docs/images/canary-promote-1.png)

![Répartition 8 / 32 après la première promotion](docs/images/canary-observe-apres-promote.png)

![Promotions et résultat final : 40 réponses en 2.0.0](docs/images/canary-promotes-recap.png)

![Rollout Healthy, 4 pods en 2.0.0](docs/images/canary-final-2.0.0.png)

### 3. Version défectueuse : la 2.1.0 est stoppée

**Déploiement de la 2.1.0 (merge à 15:55:14, sync Argo CD à 15:55:41).** Le Rollout démarre le canary et se met en pause à 25 % (`RolloutPaused`, 15:55:48).

![Canary 2.1.0 en cours de démarrage](docs/images/canary-210-progressing.png)

![Rollout en pause et événements Argo CD](docs/images/canary-210-paused-events.png)

**Le canary est défectueux.** Sur 40 requêtes, 30 répondent en 2.0.0, 6 en 2.1.0 et **4 en erreur HTTP 500** : la nouvelle version casse une partie des appels, mais l'impact reste limité à la part du trafic envoyée au canary.

![Réponses mélangées avec des erreurs 500](docs/images/canary-210-observe-500.png)

**Arrêt du déploiement (15:57:09).** Le Rollout est abandonné (`RolloutAborted: Rollout aborted update to revision 4`) : le ReplicaSet canary est réduit à zéro et les pods 2.0.0 reviennent à 4.

![Rollout Degraded, canary réduit à zéro](docs/images/canary-210-degraded.png)

![Événements Rollout : étape 1/6 puis abort](docs/images/canary-210-events-abort.png)

Les 40 requêtes suivantes répondent toutes en 2.0.0 : les utilisateurs ne subissent plus d'erreurs.

![Retour à 40 réponses en 2.0.0](docs/images/canary-210-observe-apres-abort.png)

**État dans Argo CD.** Git demande toujours la 2.1.0 alors que le cluster tourne en 2.0.0 : le Rollout reste `Degraded` (avec `Step 0/6`, `SetWeight 0`) et l'application est `Synced / Degraded`.

![Rollout aborté et application Degraded](docs/images/canary-210-app-degraded.png)

Après un rafraîchissement (`argocd.argoproj.io/refresh=normal`), l'application repasse en `Synced / Healthy`. Le Rollout, lui, reste en `Degraded` tant que Git contient la 2.1.0 : pour que Git et le cluster soient de nouveau alignés, il faut une PR qui revient à la 2.0.0 (ou qui corrige la 2.1.0).

![Application Healthy après rafraîchissement](docs/images/canary-210-refresh-healthy.png)

### Journal des déploiements de l'après-midi

| Heure | Action | Commit / PR | Résultat |
|---|---|---|---|
| 14:48:08 | Merge Blue-Green | PR #6 (`234541b`) | Rollout BlueGreen en 1.0.0, Healthy |
| 14:55:09 | Merge image 1.1.0 | PR #7 (`5e870f3`) | Pause : 1.0.0 active, 1.1.0 en preview |
| 14:56:32 | `kubectl argo rollouts promote` | — | Bascule instantanée en 1.1.0 |
| 15:03:30 | Merge stratégie Canary | PR #8 (`4fe3e89`) | Rollout Canary en 1.1.0 |
| 15:12:40 | Merge image 2.0.0 | `a3708f2` | Pause à 25 % (1 pod sur 4) |
| 15:13:46 / 15:14:11 | Deux `promote` | — | Déploiement complet en 2.0.0 |
| 15:55:14 | Merge image 2.1.0 | `922cb3b` | Pause à 25 %, erreurs HTTP 500 |
| 15:57:09 | Rollout abandonné | — | Retour à 4 pods en 2.0.0, application Degraded puis Healthy |
