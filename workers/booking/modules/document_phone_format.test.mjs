// FLUXIDI-INVOICE-RECOVERY-ACCEPTANCE-AND-PRESENTATION-P0-1
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  formatDocumentPhoneDisplay,
  looksLikeCoordinatePair,
  pickCustomerVisibleAddress,
} from "./document_phone_format.js";

test("+3204… phone display is corrected to +32 4XX XX XX XX", () => {
  assert.equal(
    formatDocumentPhoneDisplay("+320470123456"),
    "+32 470 12 34 56",
  );
});

test("standard +324… formats cleanly", () => {
  assert.equal(
    formatDocumentPhoneDisplay("+32470123456"),
    "+32 470 12 34 56",
  );
});

test("looksLikeCoordinatePair detects lon,lat and lat,lon", () => {
  assert.equal(looksLikeCoordinatePair("50.772006, 3.669447"), true);
  assert.equal(looksLikeCoordinatePair("3.669447,50.772006"), true);
  assert.equal(
    looksLikeCoordinatePair("Scheldestraat 5, 9690 Kluisbergen"),
    false,
  );
});

test("pickCustomerVisibleAddress skips coordinates and prefers snapshot", () => {
  assert.equal(
    pickCustomerVisibleAddress(
      "Scheldestraat 5, 9690 Kluisbergen",
      "50.772006, 3.669447",
    ),
    "Scheldestraat 5, 9690 Kluisbergen",
  );
  assert.equal(
    pickCustomerVisibleAddress(
      "50.772006, 3.669447",
      "Koekamerstraat 48A, 9688 Schorisse",
    ),
    "Koekamerstraat 48A, 9688 Schorisse",
  );
  assert.equal(pickCustomerVisibleAddress("50.772006, 3.669447"), "");
  assert.equal(pickCustomerVisibleAddress("Straatrit"), "");
});
