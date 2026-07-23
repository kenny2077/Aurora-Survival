# ADR 0007: Open offline-map boundary

Status: Accepted

The map contract targets MapLibre-compatible regional packages such as PMTiles,
with explicit geometry, zoom, source date, attribution, gazetteer, routing, and
artifact hashes.

Consequence: bulk-cached Google Maps data is not part of the product
architecture; real map assets remain license-gated.
