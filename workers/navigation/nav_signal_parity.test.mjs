import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  bearingsFromHeadingDeg,
  buildMapboxDirectionsSearchParams,
  buildRouteCacheKeyMaterial,
  extractManeuvers,
  normalizeNavigationLanguage,
  planWorkerMapboxDirectionsRequest,
  preserveRouteLegs,
  resolveMapboxDirectionsLanguage,
  summarizeSignalCounts,
  formatNavSignalResponseLog,
} from "./nav_signal_parity.js";

function richRoute() {
  return {
    distance: 1200,
    duration: 180,
    geometry: {
      type: "LineString",
      coordinates: [
        [4.4, 50.85],
        [4.41, 50.86],
      ],
    },
    legs: [
      {
        steps: [
          {
            distance: 120,
            duration: 15,
            name: "Teststraat",
            ref: "N5",
            destinations: ["Brussel"],
            driving_side: "right",
            maneuver: {
              type: "turn",
              modifier: "right",
              instruction: "Turn right",
              location: [4.4, 50.85],
              bearing_before: 10,
              bearing_after: 90,
            },
            bannerInstructions: [
              {
                distanceAlongGeometry: 500,
                primary: {
                  text: "Teststraat",
                  components: [
                    {
                      text: "N5",
                      type: "icon",
                      imageBaseURL: "https://example.invalid/shields/",
                    },
                    { text: "Teststraat", type: "text" },
                  ],
                },
                secondary: {
                  text: "Brussel",
                  components: [{ text: "Brussel", type: "text" }],
                },
                sub: {
                  components: [
                    {
                      type: "lane",
                      directions: ["straight", "right"],
                      active: true,
                      active_direction: "right",
                    },
                  ],
                },
              },
              {
                distanceAlongGeometry: 80,
                primary: {
                  text: "Turn right",
                  components: [{ text: "Turn right", type: "text" }],
                },
              },
            ],
            intersections: [
              {
                location: [4.401, 50.851],
                bearings: [0, 90, 180],
                entry: [true, true, false],
                in: 0,
                out: 1,
                classes: ["motorway"],
                lanes: [
                  {
                    indications: ["straight", "right"],
                    valid: true,
                    active: true,
                    valid_indication: "right",
                    access: { designated: ["taxi"] },
                  },
                  {
                    indications: ["left"],
                    valid: false,
                  },
                ],
              },
            ],
          },
          {
            distance: 80,
            duration: 10,
            name: "",
            maneuver: {
              type: "roundabout",
              modifier: "right",
              instruction: "Take the 2nd exit",
              location: [4.41, 50.86],
              exit: 2,
            },
            bannerInstructions: [
              {
                distanceAlongGeometry: 200,
                primary: {
                  text: "2nd exit",
                  components: [{ text: "2nd exit", type: "text" }],
                },
              },
            ],
          },
        ],
      },
    ],
  };
}

describe("NAV-SIGNAL-P0A-WORKER-PARITY-1", () => {
  it("request params match Flutter live Directions path", () => {
    const params = buildMapboxDirectionsSearchParams({
      language: "nl",
      accessToken: "test-token",
    });
    assert.equal(params.get("geometries"), "geojson");
    assert.equal(params.get("overview"), "full");
    assert.equal(params.get("steps"), "true");
    assert.equal(params.get("banner_instructions"), "true");
    assert.equal(params.get("roundabout_exits"), "true");
    assert.equal(params.get("alternatives"), "false");
    assert.equal(params.get("language"), "nl");
    assert.equal(params.get("voice_instructions"), null);
    assert.equal(params.get("access_token"), "test-token");
  });

  it("preserveRouteLegs keeps banners, lanes, exit, ref, destinations", () => {
    const legs = preserveRouteLegs(richRoute());
    assert.equal(legs.length, 1);
    const steps = legs[0].steps;
    assert.equal(steps[0].ref, "N5");
    assert.deepEqual(steps[0].destinations, ["Brussel"]);
    assert.equal(steps[0].bannerInstructions.length, 2);
    assert.equal(steps[0].bannerInstructions[0].distanceAlongGeometry, 500);
    assert.equal(steps[0].bannerInstructions[1].distanceAlongGeometry, 80);
    assert.equal(
      steps[0].bannerInstructions[0].primary.components.length,
      2,
    );
    assert.equal(
      steps[0].bannerInstructions[0].primary.components[0].imageBaseURL,
      "https://example.invalid/shields/",
    );
    assert.equal(steps[0].intersections[0].lanes.length, 2);
    assert.equal(steps[0].intersections[0].lanes[0].valid_indication, "right");
    assert.deepEqual(
      steps[0].intersections[0].lanes[0].access.designated,
      ["taxi"],
    );
    assert.equal(steps[1].maneuver.exit, 2);
  });

  it("optional lane active may be absent without failure", () => {
    const route = {
      legs: [
        {
          steps: [
            {
              maneuver: { type: "turn", location: [1, 2] },
              intersections: [
                {
                  lanes: [{ indications: ["left"], valid: true }],
                },
              ],
            },
          ],
        },
      ],
    };
    const legs = preserveRouteLegs(route);
    const lane = legs[0].steps[0].intersections[0].lanes[0];
    assert.equal(lane.valid, true);
    assert.equal(lane.active, undefined);
    assert.equal(lane.valid_indication, undefined);
  });

  it("bannerInstructions order is preserved", () => {
    const legs = preserveRouteLegs(richRoute());
    const banners = legs[0].steps[0].bannerInstructions;
    assert.equal(banners[0].distanceAlongGeometry, 500);
    assert.equal(banners[1].distanceAlongGeometry, 80);
  });

  it("extractManeuvers remains available for older clients", () => {
    const maneuvers = extractManeuvers(richRoute());
    assert.equal(maneuvers.length, 2);
    assert.equal(maneuvers[0].type, "turn");
    assert.equal(maneuvers[1].type, "roundabout");
    assert.equal(maneuvers[0].bannerInstructions, undefined);
  });

  it("signal summary is bounded and non-PII", () => {
    const summary = summarizeSignalCounts(preserveRouteLegs(richRoute()));
    assert.equal(summary.steps, 2);
    assert.equal(summary.banners, 3);
    assert.equal(summary.laneGroups, 1);
    assert.equal(summary.refs, 1);
    assert.equal(summary.destinations, 1);
    assert.equal(summary.roundaboutExits, 1);
    const line = formatNavSignalResponseLog(summary, "worker");
    assert.match(line, /^\[NAV_SIGNAL_RESPONSE\]/);
    assert.doesNotMatch(line, /Teststraat|Brussel|Turn right/);
  });
});

describe("NAV-SIGNAL-P0A1-WORKER-LANGUAGE-PARITY", () => {
  it("A) UI=en + country=BE => Mapbox language=en", () => {
    const planned = planWorkerMapboxDirectionsRequest({
      kind: "route",
      bodyLanguage: "en",
      countryLanguageHint: "nl",
    });
    assert.equal(planned.language, "en");
    assert.equal(planned.params.get("language"), "en");
  });

  it("B) UI=fr + country=BE => language=fr", () => {
    const planned = planWorkerMapboxDirectionsRequest({
      kind: "route",
      bodyLanguage: "fr",
      countryLanguageHint: "nl",
    });
    assert.equal(planned.params.get("language"), "fr");
  });

  it("C) UI=es + country=BE => language=es", () => {
    const planned = planWorkerMapboxDirectionsRequest({
      kind: "route",
      bodyLanguage: "es",
      countryLanguageHint: "nl",
    });
    assert.equal(planned.params.get("language"), "es");
  });

  it("D) UI=nl + country=FR => language=nl (country does not overwrite)", () => {
    const planned = planWorkerMapboxDirectionsRequest({
      kind: "route",
      bodyLanguage: "nl",
      countryLanguageHint: "fr",
    });
    assert.equal(planned.params.get("language"), "nl");
  });

  it("E) missing language + country=BE => fallback nl", () => {
    assert.equal(
      resolveMapboxDirectionsLanguage({
        bodyLanguage: undefined,
        countryLanguageHint: "nl",
      }),
      "nl",
    );
  });

  it("F) unsupported language + country=FR => fallback fr", () => {
    assert.equal(
      resolveMapboxDirectionsLanguage({
        bodyLanguage: "de",
        countryLanguageHint: "fr",
      }),
      "fr",
    );
    assert.equal(normalizeNavigationLanguage("BE"), null);
    assert.equal(normalizeNavigationLanguage("en-BE"), "en");
  });

  it("G/J) /route and /reroute both use explicit language in Mapbox query", () => {
    const routePlan = planWorkerMapboxDirectionsRequest({
      kind: "route",
      bodyLanguage: "en",
      countryLanguageHint: "nl",
    });
    const reroutePlan = planWorkerMapboxDirectionsRequest({
      kind: "reroute",
      bodyLanguage: "en",
      countryLanguageHint: "nl",
    });
    assert.equal(routePlan.kind, "route");
    assert.equal(reroutePlan.kind, "reroute");
    assert.equal(routePlan.params.get("language"), "en");
    assert.equal(reroutePlan.params.get("language"), "en");
    assert.equal(routePlan.params.get("banner_instructions"), "true");
    assert.equal(reroutePlan.params.get("roundabout_exits"), "true");
    assert.equal(routePlan.params.get("voice_instructions"), null);
  });

  it("NAV-REROUTE-P0) /reroute forwards heading as Mapbox bearings; /route does not", () => {
    assert.equal(bearingsFromHeadingDeg(175.5), "175.5,45;");
    assert.equal(bearingsFromHeadingDeg(-1), "");
    assert.equal(bearingsFromHeadingDeg(Number.NaN), "");

    const withHeading = buildMapboxDirectionsSearchParams({
      language: "nl",
      accessToken: "test-token",
      bearings: bearingsFromHeadingDeg(90),
    });
    assert.equal(withHeading.get("bearings"), "90.0,45;");
    assert.equal(withHeading.get("banner_instructions"), "true");

    const without = buildMapboxDirectionsSearchParams({
      language: "nl",
      accessToken: "test-token",
    });
    assert.equal(without.get("bearings"), null);

    const reroutePlan = planWorkerMapboxDirectionsRequest({
      kind: "reroute",
      bodyLanguage: "nl",
      countryLanguageHint: "nl",
      headingDeg: 175.5,
    });
    assert.equal(reroutePlan.kind, "reroute");
    assert.equal(reroutePlan.params.get("bearings"), "175.5,45;");
    assert.equal(reroutePlan.bearings, "175.5,45;");

    const routePlan = planWorkerMapboxDirectionsRequest({
      kind: "route",
      bodyLanguage: "nl",
      countryLanguageHint: "nl",
      headingDeg: 175.5,
    });
    assert.equal(routePlan.kind, "route");
    assert.equal(routePlan.params.get("bearings"), null);
    assert.equal(routePlan.bearings, "");
  });

  it("NAV-REROUTE-P0) destination/origin coords stay caller-owned (same dest contract)", () => {
    // Worker parse uses body.current + body.destination; this parity helper only
    // builds Mapbox query params. Prove normal route params remain stable.
    const params = buildMapboxDirectionsSearchParams({
      language: "en",
      accessToken: "tok",
    });
    assert.equal(params.get("alternatives"), "false");
    assert.equal(params.get("overview"), "full");
    assert.equal(params.get("steps"), "true");
    assert.equal(params.get("geometries"), "geojson");
  });

  it("H) cache keys differ for otherwise identical NL and EN requests", () => {
    const shared = {
      kind: "route",
      country: "BE",
      profile: "driving",
      originLat: "50.8500",
      originLng: "4.3500",
      destLat: "50.8600",
      destLng: "4.3600",
      avoidKey: "",
    };
    const nlKey = buildRouteCacheKeyMaterial({ ...shared, language: "nl" });
    const enKey = buildRouteCacheKeyMaterial({ ...shared, language: "en" });
    assert.notEqual(nlKey, enKey);
    assert.match(nlKey, /\|nl$/);
    assert.match(enKey, /\|en$/);
  });

  it("I) older request without language uses country hint", () => {
    const planned = planWorkerMapboxDirectionsRequest({
      kind: "route",
      bodyLanguage: undefined,
      countryLanguageHint: "nl",
    });
    assert.equal(planned.params.get("language"), "nl");
  });
});
