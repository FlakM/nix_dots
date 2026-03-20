Manage Mealie recipes: scrape from URL, view, and edit sections/ingredients.

## API Access

- **Base URL**: `https://mealie.house.flakm.com/api`
- **Token file**: `~/.mealie_token` (SOPS-decrypted on amd-pc)
- **Token env var fallback**: `$MEALIE_TOKEN`

Read the token:
```bash
MEALIE_TOKEN=$(cat ~/.mealie_token 2>/dev/null || echo "${MEALIE_TOKEN:-}")
[ -z "$MEALIE_TOKEN" ] && echo "ERROR: No token at ~/.mealie_token" && exit 1
MEALIE_BASE="https://mealie.house.flakm.com/api"
```

## Operations

### List recipes
```bash
curl -s "$MEALIE_BASE/recipes?page=1&perPage=50" \
  -H "Authorization: Bearer $MEALIE_TOKEN" | jq '.items[] | {name, slug}'
```

### Scrape recipe from URL (creates it in Mealie)
```bash
curl -s -X POST "$MEALIE_BASE/recipes/create/url" \
  -H "Authorization: Bearer $MEALIE_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary '{"url":"<URL>","includeTags":true}'
# Returns: slug string
```

### Test-scrape without creating
```bash
curl -s -X POST "$MEALIE_BASE/recipes/test-scrape-url" \
  -H "Authorization: Bearer $MEALIE_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary '{"url":"<URL>"}' | jq '.'
```

### Get recipe
```bash
curl -s "$MEALIE_BASE/recipes/<slug>" \
  -H "Authorization: Bearer $MEALIE_TOKEN" | jq '.'
```

### Update recipe (PUT with full body)
IMPORTANT: Always GET the recipe first, modify the JSON, then PUT back.
The PUT body must include `id`, `userId`, `householdId`, `groupId`.

```bash
RECIPE=$(curl -s "$MEALIE_BASE/recipes/<slug>" -H "Authorization: Bearer $MEALIE_TOKEN")
# Modify RECIPE with python3 or jq, then:
echo "$MODIFIED" | curl -s -X PUT "$MEALIE_BASE/recipes/<slug>" \
  -H "Authorization: Bearer $MEALIE_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @- | jq '.slug // .detail'
```

### Delete recipe
```bash
# By slug:
curl -s -X DELETE "$MEALIE_BASE/recipes/<slug>" \
  -H "Authorization: Bearer $MEALIE_TOKEN"
# Bulk delete by ID (more reliable):
curl -s -X POST "$MEALIE_BASE/recipes/bulk-actions/delete" \
  -H "Authorization: Bearer $MEALIE_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary '{"recipes":["<id>"]}'
```

## Recipe Structure

### Ingredient sections
Sections are created by setting `title` on the **first ingredient** of each group.
Subsequent ingredients in the section have `"title": null`.

```json
"recipeIngredient": [
  {"title": "Sauce", "note": "2 cups tomato sauce", "display": "2 cups tomato sauce", "quantity": 2.0},
  {"title": null,    "note": "1 tsp salt",          "display": "1 tsp salt"},
  {"title": "Pasta", "note": "500g spaghetti",       "display": "500g spaghetti", "quantity": 500.0},
  {"title": null,    "note": "1L water",             "display": "1L water",        "quantity": 1.0}
]
```

### Instruction sections
Each instruction step can have an optional `title` (displayed as a subheading):
```json
"recipeInstructions": [
  {"title": "Prepare the sauce", "text": "...", "summary": "", "ingredientReferences": []},
  {"title": "Cook pasta",        "text": "...", "summary": "", "ingredientReferences": []}
]
```

## Workflow: Scrape + Improve

1. **Scrape** the URL → get slug
2. **GET** the recipe and review its structure
3. **Analyse** ingredients and instructions — identify logical groups
4. **Update** using python3 to modify titles:

```python
import subprocess, json

token = open('/root/.mealie_token').read().strip()  # adjust path
base = 'https://mealie.house.flakm.com/api'

def api(method, path, body=None):
    cmd = ['curl', '-s', '-X', method, f'{base}{path}',
           '-H', f'Authorization: Bearer {token}',
           '-H', 'Content-Type: application/json']
    if body:
        cmd += ['--data-binary', json.dumps(body)]
    return json.loads(subprocess.check_output(cmd))

slug = 'my-recipe'
r = api('GET', f'/recipes/{slug}')

# Restructure ingredients into sections
r['recipeIngredient'][0]['title'] = 'Batter'
r['recipeIngredient'][3]['title'] = 'Filling'
for i in [1, 2, 4, 5]:
    r['recipeIngredient'][i]['title'] = None

# Add section titles to instructions
r['recipeInstructions'][0]['title'] = 'Prepare batter'
r['recipeInstructions'][2]['title'] = 'Assemble'

api('PUT', f'/recipes/{slug}', r)
```

## When scraping fails

Some sites block scrapers. Options:
1. Use `create/html-or-json` endpoint with fetched HTML:
   ```bash
   curl -s -X POST "$MEALIE_BASE/recipes/create/html-or-json" \
     -H "Authorization: Bearer $MEALIE_TOKEN" \
     -H "Content-Type: application/json" \
     --data-binary '{"data":"<raw HTML or JSON-LD>","includeTags":true}'
   ```
2. Manually build the recipe JSON and POST to `/api/recipes`, then PUT the full body.

## Arguments

`$ARGUMENTS` — one of:
- `list` — list all recipes
- `scrape <URL>` — scrape and import a recipe, then show its structure and suggest section improvements
- `view <slug>` — show recipe structure
- `update-sections <slug>` — analyse and improve sections on an existing recipe
- `delete <slug>` — delete a recipe
- (empty) — ask the user what they want to do

## Notes

- Token is stored in SOPS secrets on amd-pc, decrypted to `~/.mealie_token`
- `curl`, `jq`, and `python3` are available via nix
- When scraping, always review the result and offer to improve sections using Claude's understanding of the recipe
- Instruction `title` fields are optional section subheadings — use them when a recipe has distinct phases (e.g. "Marinate", "Cook", "Serve")
- Keep ingredient `display` in sync with `note` when modifying
