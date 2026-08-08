## Variant: The Hybrid

### Design stance
The update's structure (seed hero, browse promoted up, radar with dual view, logbook teaser, floating radio) rebuilt in Fluncle's canon, with the Journey's chapter flow and the full 6-item sitemap nav with scrollspy. All data is real, pulled from the live API.

### The chapters
| # | Nav item | The chapter | Real data used |
|---|---|---|---|
| 01 | Launch Control | The seed hero | 95,784 scanned, 91 certified |
| 02 | Browse | The crates, promoted up | 5,497 artists, 7,852 albums, 651 labels |
| 03 | Galaxy | The radar + dual view | Real certified findings with real Log IDs, BPM, keys, galaxies |
| 04 | Listen | Now playing + playlist | Real top-of-orbit track, 91-track playlist |
| 05 | Logbook | The trail | Real latest findings from the certified API |
| 06 | Builder | The machine | Real archive totals, pipeline stages |

### Key choices
- Layout: seed hero → browse tiles → radar (radar/matrix toggle) → listen → logbook → builder, with a floating radio widget
- Typography: Oxanium headlines and numbers, Space Grotesk reading, Monaspace Krypton for kickers, LOG IDs, telemetry, and the matrix view
- Color: canon tokens only; the update's amber/zinc/emerald/blue retinted to Eclipse Gold and warm blacks
- Interaction: scrollspy nav, seed re-renders radar cards + now playing + radio widget, radar node click highlights the matching card, radar/matrix toggle, radio widget collapse + play feint

### Real data notes
- The mockup's tracks were actually real: Take Me Away (038.8.7K), Elevate (039.6.2Q), Crossfire (039.8.7J) are all certified findings
- BPM and key pulled from each finding's JSON-LD (174 BPM B minor, 174 D minor, 174 C minor)
- Counts from the live API: 91 certified, 95,784 scanned, 5,497 artists, 7,852 albums, 651 labels
- The seed sectors (Pulsar, Lunar, Nebular) are the real galaxy names from the finding descriptions

### Trade-offs
- Strong at: the best of both directions in one page; every number and track is real; the radar is the clearest translation of the vector engine yet
- Weak at: the longest page of the set; the seed results are still a mock mapping (needs the real vector search API to ship); the radar node positions are illustrative, not real embedding projections

### Best for
- The direction to take to production: this is the page to build against the real API.
