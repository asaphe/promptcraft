# Authoring .drawio (diagrams.net) Files

Non-obvious decoder traps and a validation workflow for generating draw.io diagrams programmatically (diagram-as-code).

When producing `.drawio` files, generate **native `<mxCell>` XML** from a data model — never hand-author by eye, and never import SVG/HTML (draw.io imports those as a single locked image, not editable shapes).

## The `setId is not a function` trap (load error)

diagrams.net's mxCell decoder throws **`setId is not a function`** (the minified receiver prefix varies per build) at load time when a cell's `id` equals a **reserved token**. Confirmed offenders as cell ids: `edge`, `map`. Likely others in the same class (`source`, `target`, `style`, `value`, `parent`, `vertex`, `group`, `class`, `id`).

- The XML is perfectly well-formed and `xml.etree.ElementTree.parse()` accepts it — this is a *decoder* rejection, not a syntax error. XML validators won't catch it.
- **Fix (permanent):** namespace-prefix every vertex id (e.g. `n_<key>`) so a label-derived id can never collide. Update edge `source`/`target` refs to match. Don't play whack-a-mole renaming individual ids.

## Other load-breakers (each independently throws on decode)

- **XML comments inside `<root>`** — diagrams.net's own files never contain `<!-- -->`. Strip them.
- **Edges declared before the vertices they reference** — emit all vertices first, then edges. Forward `source`/`target` refs can fail decode.
- **Duplicate `<diagram id="...">` across files opened in one session** — give each file a unique diagram id (not load-fatal on its own in testing, but avoid).

## Validation before handing off a generated .drawio

```python
import xml.etree.ElementTree as ET, re
s = open(f).read(); t = ET.parse(f)                      # well-formed
ids = re.findall(r'<mxCell id="([^"]+)"', s)
assert not [i for i in ids if i in {'edge','map','source','target','style','value','parent','vertex','group','class','id'}]
idset = set(ids)                                          # no dangling edges
for c in t.findall('.//mxCell'):
    if c.get('edge') == '1':
        for a in ('source','target'):
            assert not c.get(a) or c.get(a) in idset
```

Also check: no duplicate cell ids; the `<diagram>` element should have empty text content (no compressed-payload ambiguity).

## Diagnosis method when a generated file fails but a minimal control loads

Bisect by cell sets, not by theory: strip all edges → split vertices in halves → split the failing half → isolate the single cell → confirm by removing AND by renaming it. A vertex with a reserved-token id is the most likely find.
