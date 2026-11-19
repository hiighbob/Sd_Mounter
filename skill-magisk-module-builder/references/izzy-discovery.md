# Module Discovery Protocol — IzzySoft + MMAR (OPTIONAL BONUS)

> **This is opt-in, not a gate.** Per SKILL.md Phase 0, only run this protocol
> when the user explicitly asks "does this exist already?" or the request is a
> generic, well-trodden category (hosts blocker, app freezer, audio mod, etc.).
> If the user already described a specific custom module, skip this entirely
> and go straight to building — don't make discovery a prerequisite step.
>
> This file describes the endpoints, JSON-V2 schema, scoring logic, and cache
> rules for when discovery *is* run.

---

## Endpoints primaires (JSON-V2 / MRepo format)

```
IZZY : https://apt.izzysoft.de/magisk/json/modules.json        ← principal (F-Droid quality)
MMAR : https://magisk-modules-alt-repo.github.io/json-v2/json/modules.json  ← fallback étendu
```

Schéma JSON-V2 :
```json
{
  "modules": [
    {
      "id": "string",
      "name": "string",
      "author": "string",
      "description": "string",
      "version": "string",
      "versionCode": 1234,
      "track": {
        "source": "https://github.com/...",
        "added": 1700000000,
        "updated": 1710000000,
        "license": "GPL-3.0"
      },
      "versions": [
        {
          "timestamp": 1710000000,
          "version": "v1.2",
          "versionCode": 1200,
          "zipUrl": "https://...",
          "changelog": "https://..."
        }
      ]
    }
  ]
}
```

Clé de fallback pour la liste : `"data"` si `"modules"` absent.

---

## Fichiers de cache (dans references/)

```
references/izzy_cache.json       ← snapshot des modules (tableau JSON plat)
references/izzy_cache_meta.json  ← métadonnées du cache
```

### Format izzy_cache_meta.json
```json
{
  "last_fetched": "2026-04-15",
  "source": "izzy",
  "module_count": 142,
  "version": 1
}
```

### Format d'une entrée dans izzy_cache.json
```json
{
  "id": "module-id",
  "name": "Module Name",
  "author": "username",
  "description": "Short description",
  "version": "v1.2",
  "versionCode": 1200,
  "source": "https://github.com/author/repo",
  "zipUrl": "https://...",
  "updated_ts": 1710000000,
  "last_checked": "2026-04-01"
}
```

---

## Scoring — comment chercher dans le cache

Extraire 3-6 mots-clés du besoin utilisateur, puis scorer chaque module :

| Critère | Points |
|---------|--------|
| Mot-clé exact dans `id` | +4 |
| Mot-clé exact dans `name` | +3 |
| Mot-clé exact dans `description` | +2 |
| Mot-clé partiel dans `description` | +1 |
| Module mis à jour dans les 6 mois | +1 |
| Source IzzySoft (vetted) | +1 |

Retenir les modules avec score ≥ 3. Afficher max 8 résultats.

---

## Règles de fraîcheur du cache

### Index global (izzy_cache_meta.json)
- Vérifier `last_fetched` au lancement de Phase 0
- Si `today - last_fetched > 30 jours` → proposer une mise à jour complète
- Message : *"L'index local date de X jours — veux-tu le rafraîchir avant de chercher ?"*
- Si l'utilisateur accepte → `web_fetch(IZZY_ENDPOINT)` → rebuild cache → maj `last_fetched`

### Sync individuel (lors de la validation approfondie)
Quand l'utilisateur choisit un ou plusieurs modules de l'index :

```
Pour chaque module sélectionné :
  delta = today - last_checked (en jours)
  Si delta >= 14 :
    → web_fetch(module.source) — vérifier version courante, compatibilité, changelog
    → Mettre à jour l'entrée dans izzy_cache.json (version, updated_ts, last_checked = today)
  Sinon :
    → Utiliser le cache tel quel (vérifié récemment, pas de re-fetch)
```

### Cas "index vide ou absent"
Si `izzy_cache.json` est absent ou vide (module_count = 0) → faire un fetch live
automatique sans demander (premier usage).

---

## Présentation des résultats à l'utilisateur

Pour chaque module trouvé, afficher :
```
📦 [Nom]  v[version]  ·  par [author]  ·  màj [date lisible]
   [Description — max 120 chars]
   🔗 Source   : [URL GitHub]
   🏪 IzzySoft : https://apt.izzysoft.de/packages/[id]   (si source=izzy)
```

Puis proposer les 3 options (voir SKILL.md Phase 0).

---

## Portage de code — stratégie d'intégration (Option B)

Quand l'utilisateur choisit de combiner 2-5 modules :

1. **Fetch les sources** : `web_fetch(module.source)` pour lire README + fichiers clés
2. **Identifier les composants réutilisables** :
   - Scripts shell (service.sh, post-fs-data.sh) → porter tel quel ou adapter
   - WebUI patterns (HTML/JS/CSS) → extraire les sections pertinentes
   - Config formats (JSON, .prop) → standardiser selon le template principal
3. **Intégration** :
   - Conserver les crédits dans README.md (section "Credits / Based on")
   - Documenter les modifications dans CHANGELOG.md
   - Respecter les licences (si GPL → notre module = GPL aussi)
4. **Ne pas réécrire** ce qui fonctionne — porter et adapter seulement

---

## Fallback si IzzySoft inaccessible

Si `web_fetch(IZZY_ENDPOINT)` échoue (timeout, réseau) :
1. Essayer MMAR : `web_fetch("https://magisk-modules-alt-repo.github.io/json-v2/json/modules.json")`
2. Si les deux échouent : `web_search "Magisk module <keywords> site:github.com"` et présenter
   les résultats manuellement dans le même format 📦
3. Signaler à l'utilisateur que le cache n'a pas pu être mis à jour.
