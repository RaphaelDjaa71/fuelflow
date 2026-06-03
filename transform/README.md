# transform/

**Lot responsable :** L3 (init) → L4 (intermediate) → L5 (gold + contracts).

**Statut :** non démarré.

Contenu attendu :
- Projet dbt Core (`dbt init` viendra en L3, **pas en L0**).
- `profiles.yml` avec deux targets : `snowflake` (principal) et
  `bigquery` (CI + démo live).
- Modèles `stg_*`, `int_*`, `dim_*`, `fct_*`.
- Tests génériques + custom + `contracts: enforced: true` sur le gold.
- `sources.yml` avec freshness (warn 90 min / error 6 h).

Spec de référence : `docs/data-model/star-schema.md` + ADR 0002 + ADR 0007.
