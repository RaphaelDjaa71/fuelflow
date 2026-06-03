# ADR 0004 — Cadence d'ingestion horaire (micro-batch)

## Statut
Accepté — 2026-06-03

## Contexte
La source open data `donnees.roulez-eco.fr` publie un flux **instantané**
mis à jour environ toutes les 10 minutes (snapshot complet, ~11 000
stations, ~5 carburants). Le flux est un XML-ZIP de quelques Mo.

Trois cadences envisagées :

| Cadence | Coût Cloud Run / mois | Volume données | Signal analytique gagné |
|---|---|---|---|
| **10 min** (4320 runs/mois) | ~quelques €/mois | ~30 Go bronze/mois | Marginal — un prix change ~1 à 2× par jour |
| **Horaire** (720 runs/mois) | ~négligeable | ~5 Go bronze/mois | Capture >99 % des changements de prix |
| **Quotidienne** | Quasi nul | ~200 Mo bronze/mois | Perd les changements infra-journaliers (info qui intéresse un trader) |

Le mot "temps réel" est tentant côté CV, mais il serait **trompeur** :
le flux source est lui-même un snapshot, et les prix ne fluctuent pas
au tick. Une cadence 10 min ne change pas le signal métier de façon
sensible, juste le coût et le bruit dans les logs.

## Décision
On adopte une cadence **horaire en micro-batch**. La pipeline est
conçue **incrémentale et idempotente** dès le départ, sur le grain de
mise à jour 10 min (cf. ADR 0006 : clé de dédup
`(station_id, carburant_id, maj_timestamp)`).

Conséquence pratique : **passer à 10 min = changer un cron**. Aucune
réécriture de logique requise. Idempotence garantie par la clé de
dédup en silver/gold (MERGE / `unique_key` dbt).

On **n'utilise jamais le terme "temps réel"** dans le README, les ADR,
le case study ou le CV. Le terme honnête est "**micro-batch horaire,
idempotent sur grain 10 min**".

## Conséquences
**Positives :**
- Coût Cloud Run négligeable (~720 invocations/mois).
- Pipeline prête pour 10 min sans refonte.
- Discipline d'honnêteté technique — éviter "temps réel" est un signal
  de maturité ; un senior repère immédiatement les abus de langage.

**Négatives :**
- Léger délai (jusqu'à ~1 h) entre publication source et apparition en
  gold. Acceptable pour le cas d'usage (KPI prix carburants).
- Le DAG de tests `freshness` doit accepter ce SLA : freshness OK si
  ingestion < 90 min (cf. ADR 0007).
- La doctrine "incrémental dès J1" ajoute une exigence à L1 (logique de
  watermark) qu'on aurait pu reporter avec une cadence quotidienne.
  Choix assumé.
