Review and correct French (fr-FR) translations in a Phrase TMS bilingual DOCX file.

## Input
The user provides a Phrase TMS bilingual DOCX file path. Use `/parse-tms-docx` knowledge for parsing.

## Workflow
1. Extract segments using python-docx (`nix-shell -p python3Packages.python-docx`)
2. Build terminology glossary from 100% match segments
3. Filter: structural vs translatable, by score tier
4. Launch parallel review agents for each batch
5. Merge corrections, apply to ORIGINAL document
6. Run programmatic NBSP final pass
7. Save to `_final.docx` and copy to ~/Downloads/

## Review Tiers
- **Deep (score <100)**: Full quality - accuracy, NBSP, tags, terminology, typography
- **Light (score =100)**: NBSP, obvious errors, tag corruption only
- **Skip (score >=101)**: Ignore (repetitions)

## NBSP Rules (CRITICAL)
| Before | Unicode | Character |
|--------|---------|-----------|
| `:` | U+00A0 | NBSP |
| `;` `?` `!` | U+202F | NNBSP |
| Inside `<< >>` | U+00A0 | NBSP |

Exceptions: NOT inside tags, HTML entities, structural patterns (E:Name), URLs.

## Terminology Glossary
Next=Suivant, Back=Retour, Exit=Quitter, Save=Enregistrer, Cancel=Annuler, Continue=Continuer, Settings=Parametres, Setup=Configuration, Enable=Activer, Disable=Desactiver, Touch/Press/Tap=Appuyez sur, Select=Selectionnez, View All Products=Voir tous les produits, Kiosk=Kiosk (brand), Printer=Imprimante, Print=Imprimer/Impression, Photo book=Livre photo, Troubleshooting=Depannage, Direct transfer=Transfert direct, USB Flash Drive=Lecteur Flash USB, Hard disk=Disque dur, Touchscreen=Ecran tactile, Network=Reseau, Driver=Pilote, Default=Par defaut

## Typography
- Sentence case everywhere (no Title Case from English)
- Imperative (vous): "Appuyez sur...", "Selectionnez..."
- Guillemets: use NBSP inside French guillemets
- Cross-refs: "Voir page" with NBSP before the number

## Common Mistakes to Catch
1. Missing NBSP before `:;?!`
2. Tag corruption (removed/renumbered/restructured)
3. Calques (word-for-word English syntax)
4. "Touchez" instead of "Appuyez sur"
5. Title Case from English
6. Untranslated segments
7. "Kiosque" instead of "Kiosk"
8. English quotes instead of guillemets
9. Index entries: preserve colon-separated structure, translate terms

## Agent Prompt Template
Include: file path, NBSP rules with Unicode, tag rules, glossary, typography rules, output format `[{"table":N,"row":N,"num":"...","new_target":"...","reason":"..."}]`, instruction to only output changes.

## Final NBSP Pass
After applying corrections, sweep all non-structural targets replacing regular space before `:` with U+00A0 and before `;?!` with U+202F. Use python regex with actual Unicode chars (not `\u00a0` in replacement strings).
