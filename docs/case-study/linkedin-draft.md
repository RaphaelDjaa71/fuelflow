# Brouillon LinkedIn — annonce FuelFlow

> ~330 mots. Ton sobre, factuel, sans buzzword IA, sans auto-proclamation de niveau.
> À ajuster avant publication.

---

J'ai passé les dernières semaines à construire **FuelFlow**, un projet Analytics Engineer de bout en bout sur l'open data des prix carburants français — et je le partage parce qu'il répond concrètement à une question qu'on me pose souvent : « tu sais faire quoi en pratique ? »

**Le problème métier.** Le flux public `donnees.roulez-eco.fr` couvre ~11 000 stations en France, est rafraîchi toutes les ~10 minutes, et arrive en XML-ZIP ISO-8859-1. Trois pièges invisibles : la source peut changer de format sans prévenir, c'est un snapshot ré-empilé à chaque tirage, et sans gardes-fous un drift silencieux corrompt le warehouse pendant des semaines.

**Ce que FuelFlow livre.**

🔹 Pipeline autonome : Cloud Run Job + Cloud Scheduler, micro-batch horaire (jamais « temps réel » — je suis allergique au mot), idempotent au niveau objet GCS et au niveau ligne via clé naturelle.

🔹 dbt **portable** Snowflake ↔ BigQuery, avec `contracts: enforced` sur le fait et les 4 dimensions, types rendus par Jinja en fonction du target — pas un copier-coller par moteur.

🔹 CI GitHub Actions qui **bloque vraiment le merge**. J'ai ouvert une PR avec un test volontairement cassé : la CI a viré au rouge, le `mergeStateStatus` est passé à `BLOCKED`, la branch protection a refusé le bouton merge. La preuve compte plus que le badge vert.

🔹 dbt docs publiques sur GitHub Pages, coût d'exploitation ≈ 0 €, free tier d'un bout à l'autre.

**Trois bugs réels capturés, racontés sans masque** dans le case study : `TIMESTAMP_MICROS` lu comme secondes par Snowflake (années en 54 M, invisible aux tests), cast NTZ → TZ qui utilise le timezone de session (835 fausses « lignes futures »), et l'API `bq add-iam-policy-binding` en silent-fail. Le **dual-warehouse a agi comme détecteur de bugs** — un seul moteur les aurait laissés passer.

📖 **Case study complet** : [raphaeldjaa.fr/fuelflow](https://raphaeldjaa.fr) *(à jour quand publié)*
🔗 **Code & dbt docs** : <https://github.com/RaphaelDjaa71/fuelflow>

Curieux des retours — surtout sur ce qui semble manquer ou ce qui ressemblerait à un anti-pattern. Je suis en recherche active d'un poste **Analytics Engineer** (CDI, Paris ou full-remote France).

#AnalyticsEngineering #dbt #Snowflake #BigQuery #DataEngineering
