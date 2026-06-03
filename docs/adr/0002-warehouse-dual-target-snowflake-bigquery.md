# ADR 0002 — Dual-target Snowflake / BigQuery

## Statut
Accepté — 2026-06-03

## Contexte
FuelFlow vise un double objectif :
1. **Signal CV** — Snowflake est le warehouse le plus demandé sur les
   offres Analytics Engineer reçues. Le projet doit montrer Snowflake en
   production, avec des contrats, des tests, une CI, des screenshots.
2. **Démo publique durable** — un dashboard live consultable par un
   recruteur, sans coût récurrent ni risque d'expiration.

Le conflit : **Snowflake n'a pas de tier gratuit permanent**. Le trial
expire à 30 jours ou $400 de crédits, ce qui interdit une démo
publique stable. À l'inverse, BigQuery offre 1 To de requêtes et 10 Go
de stockage **gratuits chaque mois**, à perpétuité, et s'intègre
nativement à Looker Studio (gratuit aussi).

Alternatives écartées :
- **Snowflake seul** : démo expire après le trial, impossible de
  laisser le lien dans un CV.
- **BigQuery seul** : pas de Snowflake sur le CV — c'est précisément le
  gap qu'on veut combler.
- **DuckDB / MotherDuck en remplacement de Snowflake** : MotherDuck est
  encore peu cité dans les offres Analytics Engineer (2026) ;
  signal CV plus faible.

## Décision
On **maintient les deux warehouses** avec des rôles différenciés :

| Warehouse | Rôle | Région | Garde-fou coût |
|---|---|---|---|
| **Snowflake** | Warehouse principal (build, headline CV, contracts, screenshots, case study Power BI) | GCP — région à confirmer en L2 | Warehouse **XS** + **AUTO_SUSPEND = 60 s** + AUTO_RESUME |
| **BigQuery** | Démo live publique durable + cible CI/CD | europe-west1 | Free tier suffit ; pas de réservation |

Le projet dbt est **portable** entre les deux via deux targets dans
`profiles.yml`. La CI tourne sur BigQuery uniquement (free tier, rapide,
pas de réveil de warehouse Snowflake à chaque PR). Les screenshots
"production" pour le case study sont pris sur Snowflake.

## Conséquences
**Positives :**
- Le CV affiche Snowflake **et** un dashboard public durable.
- La CI ne consomme pas de crédits Snowflake (free tier BQ).
- dbt portable = compétence visible (refs adaptatives, macros
  cross-database) ; ce n'est plus un détail tooling, c'est un atout.

**Négatives :**
- **Surcoût de complexité** estimé à +1,5–2 jours/homme sur le projet
  (double couche de chargement bronze → silver, doubles tests
  d'intégration, doubles types/contracts).
- Les **équivalences de types** Snowflake/BigQuery sont à gérer
  explicitement (cf. `docs/data-model/star-schema.md` section
  portabilité — ex. `NUMBER(10,3)` ↔ `NUMERIC`, `TIMESTAMP_NTZ` ↔
  `TIMESTAMP`).
- Un oubli de coupure Snowflake = facturation. AUTO_SUSPEND 60 s + alerte
  budget GCP à mettre en place en L2 sont les mitigations.

## Notes opérationnelles
- Le secret Snowflake et la clé service-account GCP ne sont **jamais**
  commités. `.env` est gitignoré, hook gitleaks actif.
- L'ADR 0007 (data contracts) impose des types **abstraits** dans les
  YAML dbt, traduits par macros au moment du build pour chaque target.
