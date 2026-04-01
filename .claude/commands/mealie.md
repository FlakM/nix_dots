Manage recipes in the self-hosted Mealie instance. Use this skill when the user wants to:
- Add or import a recipe from a URL
- List, search, or view existing recipes
- Edit a recipe's ingredients, sections, or instructions
- Delete a recipe
- Improve recipe structure (grouping ingredients into sections, adding instruction titles)

## Setup

Read the API token:
```bash
MEALIE_TOKEN=$(cat ~/.mealie_token)
MEALIE_BASE="https://mealie.house.flakm.com/api"
```

## API Reference

| Action | Method | Path | Body |
|--------|--------|------|------|
| List recipes | GET | `/recipes?page=1&perPage=50` | — |
| Scrape from URL | POST | `/recipes/create/url` | `{"url":"...","includeTags":true}` → returns slug |
| Test scrape (no import) | POST | `/recipes/test-scrape-url` | `{"url":"..."}` |
| Get recipe | GET | `/recipes/{slug}` | — |
| Update recipe | PUT | `/recipes/{slug}` | full recipe JSON (see note below) |
| Delete by slug | DELETE | `/recipes/{slug}` | — |
| Bulk delete by ID | POST | `/recipes/bulk-actions/delete` | `{"recipes":["<id>"]}` |

**Update note:** always GET first, modify, then PUT back. The body must include `id`, `userId`, `householdId`, `groupId`.

## Recipe Structure

### Ingredient sections
`title` on the **first** ingredient in a group creates a visible section header. Subsequent items have `"title": null`.

```json
[
  {"title": "Sauce",  "note": "2 cups tomato sauce", "display": "2 cups tomato sauce"},
  {"title": null,     "note": "1 tsp salt",           "display": "1 tsp salt"},
  {"title": "Pasta",  "note": "500g spaghetti",        "display": "500g spaghetti"}
]
```

### Instruction sections
Each step has an optional `title` (rendered as a subheading) plus required `summary` and `ingredientReferences`:
```json
{"title": "Cook the sauce", "text": "...", "summary": "", "ingredientReferences": []}
```

## Workflow: Scrape and Improve

```python
import subprocess, json, os

def mealie(method, path, body=None):
    token = open(os.path.expanduser('~/.mealie_token')).read().strip()
    cmd = ['curl', '-s', '-X', method,
           f'https://mealie.house.flakm.com/api{path}',
           '-H', f'Authorization: Bearer {token}',
           '-H', 'Content-Type: application/json']
    if body:
        cmd += ['--data-binary', json.dumps(body)]
    return json.loads(subprocess.check_output(cmd))

# 1. Import
slug = mealie('POST', '/recipes/create/url', {'url': '<URL>', 'includeTags': True}).strip('"')

# 2. Get and inspect
r = mealie('GET', f'/recipes/{slug}')

# 3. Add sections (set title on first ingredient of each group, null on rest)
r['recipeIngredient'][0]['title'] = 'Section A'
r['recipeIngredient'][3]['title'] = 'Section B'
for i in [1, 2]:
    r['recipeIngredient'][i]['title'] = None

# 4. Add instruction titles
r['recipeInstructions'][0]['title'] = 'Prepare'
r['recipeInstructions'][2]['title'] = 'Cook'

# 5. Save
mealie('PUT', f'/recipes/{slug}', r)
```

## When scraping fails

Fall back to `create/html-or-json` with the raw page HTML:
```bash
curl -s -X POST "$MEALIE_BASE/recipes/create/html-or-json" \
  -H "Authorization: Bearer $MEALIE_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary '{"data":"<raw HTML or JSON-LD>","includeTags":true}'
```

## Notes

- Token is at `~/.mealie_token` (SOPS secret, decrypted on amd-pc)
- `curl`, `jq`, and `python3` are available
- After scraping, always review ingredients and suggest logical section groupings
- Keep `display` in sync with `note` when modifying ingredients
- Use instruction `title` fields for distinct recipe phases (e.g. "Marinate", "Cook", "Serve")
