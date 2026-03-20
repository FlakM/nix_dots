Parse a Phrase TMS bilingual DOCX file and extract translation segments.

## Input
The user will provide a path to a Phrase TMS bilingual DOCX file. If not provided, look for .docx files in the current directory.

## Package
Use python-docx via nix: `nix-shell -p python3Packages.python-docx --run 'python3 script.py'`

## Document Structure
Phrase TMS bilingual DOCX files store translations in tables with these columns:

| Index | Column |
|-------|--------|
| 0 | Segment ID |
| 1 | ICU marker |
| 2 | # (sequential number) |
| 3 | Source text |
| 4 | Source duplicate |
| 5 | Target text (editable) |
| 6 | Score (0-101) |
| 7 | Comment |

Tables 0-2 are metadata. Tables 3+ contain data (typically 1000 rows each).

## Score Meanings
- 101+ = repetition/locked (skip)
- 100 = exact match (light review only)
- 75-99 = fuzzy match (review carefully)
- <75 = new/low match (deep review)

## Tags
Phrase TMS inline tags: `{N>` (opening paired), `<N}` (closing paired), `{N}` (standalone). NEVER modify tags.

## Structural/Non-Translatable Patterns
Skip these source patterns: `E:Name`, `X:text`, `DIV`, `HTML`, `Ref_`, `Level`, `openObject`, `&#NNN;`, single letters/numbers.

## Task
1. Extract all segments to JSON with fields: table, row, num, source, target, score
2. Report statistics: total segments, by score range, empty targets
3. Save extraction to a JSON file
4. If the user wants to apply corrections, load correction JSONs and write to target column (cells[5])

## Cell Editing Pattern
```python
cell = row.cells[5]
for paragraph in cell.paragraphs:
    for run in paragraph.runs:
        run.text = ''
if cell.paragraphs and cell.paragraphs[0].runs:
    cell.paragraphs[0].runs[0].text = new_text
else:
    cell.paragraphs[0].text = new_text
```

## Batch Processing
For large docs: split into batches of 200-300 segments, process in parallel, merge by (table,row) key, apply to original doc.
