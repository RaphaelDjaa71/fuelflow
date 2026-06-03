# ADR 0001 — Tenir un journal des décisions d'architecture

## Statut
Accepté — 2026-06-03

## Contexte
FuelFlow est un projet portfolio dont la valeur tient autant aux choix
techniques justifiés qu'au code lui-même. Un recruteur ou un ingénieur
senior qui découvre le repo doit pouvoir reconstituer **pourquoi** un
choix a été fait sans avoir à fouiller l'historique git ni à interroger
l'auteur.

Sans journal de décisions, deux risques :
1. Les compromis (coût Snowflake, cadence horaire, dual-target) passent
   inaperçus et le lecteur les interprète comme de la naïveté technique.
2. Les futures évolutions (ex. passage à 10 min, ajout d'un troisième
   warehouse) sont prises sans contexte sur ce qui a été écarté et
   pourquoi.

## Décision
On adopte le format **Nygard** (Titre / Statut / Contexte / Décision /
Conséquences), un fichier Markdown par décision, numérotation
incrémentale à 4 chiffres dans `docs/adr/`. Les ADR sont rédigés en
**français** (cohérent avec la doctrine README/case study en français,
code/commits en anglais).

Chaque ADR doit expliciter :
- Le **problème** ou la tension qu'on résout.
- Les **alternatives écartées** et la raison.
- Les **conséquences négatives** assumées (pas seulement les positives).

Un ADR est *immuable* après acceptation : on n'édite pas un ADR pour
changer d'avis, on en écrit un nouveau qui le supersède (et on met le
statut de l'ancien à `Superseded by ADR XXXX`).

## Conséquences
**Positives :**
- Raisonnement traçable, lisible en quelques minutes. Signal "senior"
  fort pour un projet portfolio.
- Discipline forcée : écrire un ADR oblige à formaliser le compromis,
  ce qui révèle parfois des angles morts.

**Négatives :**
- Coût d'écriture à chaque décision structurante (~15-30 min par ADR).
- Risque d'ADR bavards ou vides si la discipline retombe. Mitigé en
  imposant la triade alternatives/conséquences/négatives ci-dessus.

## Index
- ADR 0001 — Tenir un journal des décisions d'architecture (ce document)
- ADR 0002 — Dual-target Snowflake / BigQuery
- ADR 0003 — Orchestration Cloud Run Job + Cloud Scheduler
- ADR 0004 — Cadence d'ingestion horaire (micro-batch)
- ADR 0005 — Architecture médaillon, bronze sur GCS
- ADR 0006 — Grain du fait et clé de déduplication
- ADR 0007 — Stratégie data contracts
