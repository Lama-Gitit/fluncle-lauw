import { describe, expect, it } from "vitest";

import { anchorSearchQuery, pickIsrcCandidate, pickVerifiedCandidate } from "./anchor";

// The verification rungs are pure, so they are unit-tested here without a database — the exact
// title fold, artist set, ±2s duration window, and ISRC equality that decide whether a candidate
// is genuinely the same recording. The `anchorTrack` write path (rails + stamping) is exercised
// against the real schema in anchor.integration.test.ts.

describe("anchorSearchQuery", () => {
  it("joins the row's artists then its title, trimmed", () => {
    expect(anchorSearchQuery(["Etherwood"], "Weightless")).toBe("Etherwood Weightless");
    expect(anchorSearchQuery(["Nu:Tone", "Logistics"], "Roller")).toBe("Nu:Tone Logistics Roller");
  });

  it("handles a row with no artists", () => {
    expect(anchorSearchQuery([], "Amen Break")).toBe("Amen Break");
  });
});

describe("pickIsrcCandidate — the exact rung", () => {
  it("picks the candidate whose ISRC equals the row's (case-insensitive, trimmed)", () => {
    const candidates = [
      { durationMs: 240_000, isrc: "USAAA0000001", spotifyTrackId: "wrong" },
      { durationMs: 240_000, isrc: "gbcjy1300173", spotifyTrackId: "right" },
    ];

    expect(pickIsrcCandidate("  GBCJY1300173 ", 240_000, candidates)?.spotifyTrackId).toBe("right");
  });

  it("when several candidates share the ISRC (a re-press), the closest duration wins", () => {
    // The pilot4 case: one ISRC resolves several Spotify track ids (different pressings). The row's
    // duration is the tiebreak — a wrong-length pressing must not win over the true recording.
    const candidates = [
      { durationMs: 200_000, isrc: "GBCJY1300173", spotifyTrackId: "long-press" },
      { durationMs: 261_500, isrc: "GBCJY1300173", spotifyTrackId: "true-press" },
    ];

    expect(pickIsrcCandidate("GBCJY1300173", 261_901, candidates)?.spotifyTrackId).toBe(
      "true-press",
    );
  });

  it("returns undefined when no candidate carries the row's ISRC", () => {
    const candidates = [{ durationMs: 240_000, isrc: "USAAA0000001", spotifyTrackId: "x" }];

    expect(pickIsrcCandidate("GBCJY1300173", 240_000, candidates)).toBeUndefined();
  });

  it("returns undefined for an empty row ISRC (never anchors on a blank key)", () => {
    const candidates = [{ durationMs: 240_000, isrc: "", spotifyTrackId: "x" }];

    expect(pickIsrcCandidate("   ", 240_000, candidates)).toBeUndefined();
  });
});

describe("pickVerifiedCandidate — the verified search triple", () => {
  const base = { spotifyTrackId: "hit" };

  it("anchors a candidate that clears folded artist + title + ±2s duration", () => {
    const candidates = [{ ...base, artists: ["Muffler"], durationMs: 201_000, title: "Dribble" }];

    expect(pickVerifiedCandidate(["Muffler"], "Dribble", 200_000, candidates)?.spotifyTrackId).toBe(
      "hit",
    );
  });

  it("does NOT anchor when the duration is off by more than the 3s window", () => {
    const candidates = [{ ...base, artists: ["Hold Tight"], durationMs: 203_001, title: "Lounge" }];

    expect(pickVerifiedCandidate(["Hold Tight"], "Lounge", 200_000, candidates)).toBeUndefined();
  });

  it("anchors at 2.6s off — the calibrated window (same-recording drift P99 ≈ 5s, wrong-recording ≥21s)", () => {
    // The measured 2026-07-26 false-miss: compilation master vs single master, Δ2.6s.
    const candidates = [
      { ...base, artists: ["Donnie Dubson"], durationMs: 320_000, title: "Monday" },
    ];

    expect(
      pickVerifiedCandidate(["Donnie Dubson"], "Monday", 322_600, candidates)?.spotifyTrackId,
    ).toBe("hit");
  });

  it("does NOT anchor a '- VIP' to a plain-title row (the fold keeps descriptors distinct)", () => {
    const candidates = [
      { ...base, artists: ["DJ Fresh"], durationMs: 200_000, title: "Bad Company - VIP" },
    ];

    expect(pickVerifiedCandidate(["DJ Fresh"], "Bad Company", 200_000, candidates)).toBeUndefined();
  });

  it("does NOT anchor when the artist set differs (disjoint is never a subset)", () => {
    const candidates = [
      { ...base, artists: ["Someone Else"], durationMs: 200_000, title: "Dribble" },
    ];

    expect(pickVerifiedCandidate(["Muffler"], "Dribble", 200_000, candidates)).toBeUndefined();
  });

  it("SUBSET fallback: a primary-only credit anchors when the duration is within the tight 1s window", () => {
    // The measured class (~9% of stable misses): "LSB & DRS — Could Be" listed under "LSB" alone.
    const candidates = [{ ...base, artists: ["LSB"], durationMs: 340_400, title: "Could Be" }];

    expect(
      pickVerifiedCandidate(["LSB", "DRS"], "Could Be", 340_000, candidates)?.spotifyTrackId,
    ).toBe("hit");
  });

  it("SUBSET fallback refuses outside the tight window, even inside the full gate's 3s", () => {
    const candidates = [{ ...base, artists: ["LSB"], durationMs: 342_000, title: "Could Be" }];

    expect(pickVerifiedCandidate(["LSB", "DRS"], "Could Be", 340_000, candidates)).toBeUndefined();
  });

  it("SUBSET fallback is one-way: a candidate crediting MORE artists than the row never matches", () => {
    const candidates = [
      { ...base, artists: ["LSB", "DRS"], durationMs: 340_000, title: "Could Be" },
    ];

    expect(pickVerifiedCandidate(["LSB"], "Could Be", 340_000, candidates)).toBeUndefined();
  });

  it("SUBSET fallback still enforces the version descriptor", () => {
    const candidates = [
      { ...base, artists: ["LSB"], durationMs: 340_000, title: "Could Be (Anile Remix)" },
    ];

    expect(pickVerifiedCandidate(["LSB", "DRS"], "Could Be", 340_000, candidates)).toBeUndefined();
  });

  it("SUBSET fallback drops a candidate with no artists at all", () => {
    const candidates = [{ ...base, artists: [], durationMs: 340_000, title: "Could Be" }];

    expect(pickVerifiedCandidate(["LSB", "DRS"], "Could Be", 340_000, candidates)).toBeUndefined();
  });

  it("the FULL gate wins over a closer-duration subset candidate", () => {
    const candidates = [
      {
        ...base,
        artists: ["LSB"],
        durationMs: 340_000,
        spotifyTrackId: "subset",
        title: "Could Be",
      },
      {
        ...base,
        artists: ["LSB", "DRS"],
        durationMs: 341_500,
        spotifyTrackId: "full",
        title: "Could Be",
      },
    ];

    expect(
      pickVerifiedCandidate(["LSB", "DRS"], "Could Be", 340_000, candidates)?.spotifyTrackId,
    ).toBe("full");
  });

  it("drops a candidate with no duration (unverifiable), and picks the closest of those that clear", () => {
    const candidates = [
      {
        ...base,
        artists: ["Muffler"],
        durationMs: null,
        spotifyTrackId: "no-dur",
        title: "Dribble",
      },
      {
        ...base,
        artists: ["Muffler"],
        durationMs: 201_800,
        spotifyTrackId: "far",
        title: "Dribble",
      },
      {
        ...base,
        artists: ["Muffler"],
        durationMs: 200_200,
        spotifyTrackId: "near",
        title: "Dribble",
      },
    ];

    expect(pickVerifiedCandidate(["Muffler"], "Dribble", 200_000, candidates)?.spotifyTrackId).toBe(
      "near",
    );
  });
});
