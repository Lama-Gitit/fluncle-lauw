## Variant: Dual Layer

### Design stance
The dual-layer strategy made literal: a global Consumer/Builder toggle above the page. Consumer shows the crew-facing discovery surface; Builder flips the same page into telemetry (archive totals, pipeline stages, embedding readouts on every row).

### Key choices
- Layout: layer bar (hint + toggle) → Consumer layer (hero + feed) | Builder layer (telemetry grid + pipeline + telemetry rows)
- Typography: Space Grotesk for consumer, Monaspace Krypton for every builder readout (The One Voice Rule: mono speaks only for the machine)
- Color: canon tokens; gold stays on the consumer CTA and the archive total
- Interaction: the toggle actually switches layers (verified in browser); builder rows carry mono telemetry instead of chips

### Trade-offs
- Strong at: the vision board's architecture in one screen; the Builder nav item gets a real home; progressive disclosure without a separate route
- Weak at: the toggle is a new global control the canon does not have; two layers double the surface to design and test; the builder layer risks feeling like a dashboard (the anti-reference) if the telemetry is not kept quiet

### Best for
- If the dual-layer product hierarchy is the point of this exercise, this is the variant that proves it.
