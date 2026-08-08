## Variant: The Journey

### Design stance
The homepage as the sitemap journey: one scroll, six chapters, each chapter IS one nav destination. The top nav tracks the chapter on screen (scrollspy), and the seed search personalizes the page as you move through it.

### The chapters
| # | Nav item | The chapter | What it previews |
|---|---|---|---|
| 01 | Launch Control | The seed hero | The interactive seed search, presets |
| 02 | Galaxy | Your sector | Seeded track cards, re-rendered per seed |
| 03 | Listen | Hear the sector | Now playing (top of the seed's orbit), playlist + radio stats |
| 04 | Browse | The crates | Artist/label/album tiles, seed genre highlighted |
| 05 | Logbook | The trail | The real archive feed with canon track rows |
| 06 | Builder | The machine | Quiet mono telemetry, pipeline stages |

### Key choices
- Layout: full-width hero, then five chapters with identical anatomy (mono kicker, Oxanium headline, one lede line, real preview, quiet "go deeper" link)
- Typography: Oxanium for headlines and numbers, Space Grotesk for reading, Monaspace Krypton for kickers, LOG IDs, and telemetry
- Color: canon tokens; gold on kickers, the seed CTA, and the primary actions
- Interaction: scrollspy nav (IntersectionObserver), seed re-renders Galaxy cards + Listen now-playing + Browse genre highlights, sonar scan feint, card lift on hover

### Trade-offs
- Strong at: the homepage teaches the nav; the seed is a through-line, not a one-off widget; every destination gets a content preview
- Weak at: the longest page of the set; the canon's "the tracklist is the page" is set aside for a guided tour; the seed data is a mock (needs the real vector API to ship)

### Best for
- The "proper flow" direction: a homepage that is also a navigation, in content and UX.
