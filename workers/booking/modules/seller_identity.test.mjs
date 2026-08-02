import { test } from "node:test";
import assert from "node:assert/strict";
import {
  normalizeLegalForm,
  legalFormLabelNl,
  formatBelgianEnterpriseNumber,
  formatBelgianVatNumber,
  extractSellerIdentityFieldsFromProfile,
  resolveLegalSellerName,
  resolveCanonicalSellerIdentity,
  buildSellerSnapshotFromBusinessProfile,
  validateSellerIdentityForInvoiceIssuance,
  assertSellerProfileScopeMatch,
  formatSellerIdentityPresentationLines,
  isUnsafeInventedSellerLegalName,
  LEGAL_FORM_EENMANSZAAK,
} from "./seller_identity.js";

const CANONICAL_SOLE = {
  companyName: "Fluxidi",
  trading_name: "Fluxidi",
  legal_entrepreneur_name: "Christophe Vanrokeghem",
  legal_form: "eenmanszaak",
  enterprise_number: "0772931038",
  vat_number: "BE0772931038",
  address: "Koekamerstraat 48A",
  postcode: "9688",
  city: "Schorisse",
  country: "BE",
  invoiceEmail: "billing@fluxidi.com",
  address_is_visitor: false,
};

test("sole proprietor keeps legal entrepreneur and trading name separate", () => {
  const id = resolveCanonicalSellerIdentity(CANONICAL_SOLE);
  assert.equal(id.legal_entrepreneur_name, "Christophe Vanrokeghem");
  assert.equal(id.trading_name, "Fluxidi");
  assert.equal(id.legal_seller_name, "Christophe Vanrokeghem");
  assert.notEqual(id.legal_seller_name, id.trading_name);
  assert.equal(id.legal_form, LEGAL_FORM_EENMANSZAAK);
  assert.equal(id.legal_form_label_nl, "Eenmanszaak");
  assert.equal(id.is_sole_proprietorship, true);
});

test("seller snapshot stores entrepreneur as legal seller and Fluxidi as trading name", () => {
  const snap = buildSellerSnapshotFromBusinessProfile(CANONICAL_SOLE);
  assert.equal(snap.legal_name, "Christophe Vanrokeghem");
  assert.equal(snap.legal_entrepreneur_name, "Christophe Vanrokeghem");
  assert.equal(snap.name, "Fluxidi");
  assert.equal(snap.trading_name, "Fluxidi");
  assert.equal(snap.legal_form, LEGAL_FORM_EENMANSZAAK);
  assert.equal(snap.enterprise_number, "0772931038");
  assert.equal(snap.vat_number, "BE0772931038");
  assert.equal(snap.address_is_visitor, false);
  assert.equal(snap.email, "billing@fluxidi.com");
});

test("no BV wording unless explicitly configured", () => {
  const soleLines = formatSellerIdentityPresentationLines(
    resolveCanonicalSellerIdentity(CANONICAL_SOLE),
  ).join("\n");
  assert.match(soleLines, /Christophe Vanrokeghem/);
  assert.match(soleLines, /handelend onder de naam Fluxidi/);
  assert.match(soleLines, /Eenmanszaak/);
  assert.doesNotMatch(soleLines, /\bBV\b/);

  const bv = resolveCanonicalSellerIdentity({
    ...CANONICAL_SOLE,
    legal_form: "bv",
    legal_entrepreneur_name: "",
    legalName: "Example Mobility BV",
    companyName: "Example Mobility",
  });
  assert.equal(bv.legal_form_label_nl, "BV");
  assert.match(
    formatSellerIdentityPresentationLines(bv).join("\n"),
    /\bBV\b/,
  );
});

test("legacy profile fields remain readable where unambiguous", () => {
  const legacy = extractSellerIdentityFieldsFromProfile({
    companyName: "Fluxidi",
    legalName: "VC Construct & Graphics",
    vatNumber: "BE0772931038",
    enterpriseNumber: "0772931038",
    address: "Koekamerstraat 48A",
  });
  assert.equal(legacy.legacy_legal_name, "VC Construct & Graphics");
  assert.equal(legacy.trading_name, "Fluxidi");
  assert.equal(resolveLegalSellerName(legacy), "VC Construct & Graphics");
});

test("legacy legalName=VC Construct is not silently replaced by a default", () => {
  const id = resolveCanonicalSellerIdentity({
    companyName: "Fluxidi",
    legalName: "VC Construct & Graphics",
    vat_number: "BE0772931038",
    enterprise_number: "0772931038",
  });
  assert.equal(id.legal_seller_name, "VC Construct & Graphics");
  assert.equal(id.legacy_legal_name, "VC Construct & Graphics");
  assert.equal(isUnsafeInventedSellerLegalName(id.legal_seller_name), false);
  assert.notEqual(id.legal_seller_name, "Fluxidi Taxi");
  assert.notEqual(id.legal_seller_name, "Fluxidi BV");
});

test("missing legal entrepreneur for sole-prop invoice fails closed", () => {
  const result = validateSellerIdentityForInvoiceIssuance({
    companyName: "Fluxidi",
    trading_name: "Fluxidi",
    legal_form: "eenmanszaak",
    vat_number: "BE0772931038",
    enterprise_number: "0772931038",
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "seller_identity_incomplete");
  assert.ok(result.missing_fields.length > 0);
});

test("trading name alone is insufficient as legal seller identity", () => {
  const result = validateSellerIdentityForInvoiceIssuance({
    companyName: "Fluxidi",
    trading_name: "Fluxidi",
    vat_number: "BE0772931038",
  });
  assert.equal(result.ok, false);
  assert.ok(
    result.missing_fields.includes("legal_entrepreneur_or_legal_name_missing") ||
      result.missing_fields.includes("trading_name_insufficient_as_legal_seller"),
  );
});

test("existing issued seller_snapshot remains unchanged by builders", () => {
  const issued = Object.freeze({
    name: "Fluxidi",
    legal_name: "VC Construct & Graphics",
    vat_number: "BE0772931038",
    registration_number: "0772931038",
  });
  // Building a new snapshot from a corrected profile must not mutate issued.
  const next = buildSellerSnapshotFromBusinessProfile(CANONICAL_SOLE);
  assert.equal(issued.legal_name, "VC Construct & Graphics");
  assert.notEqual(next.legal_name, issued.legal_name);
  assert.equal(issued.name, "Fluxidi");
});

test("cross-tenant profile resolution is rejected", () => {
  const check = assertSellerProfileScopeMatch(
    { tenant_id: "t1", company_id: "c1" },
    { tenant_id: "other", company_id: "c1", legalName: "X" },
  );
  assert.equal(check.ok, false);
  assert.equal(check.error, "seller_profile_tenant_mismatch");
});

test("invoice rendering lines include entrepreneur, trading, form, enterprise, VAT", () => {
  const lines = formatSellerIdentityPresentationLines(
    resolveCanonicalSellerIdentity(CANONICAL_SOLE),
  );
  assert.deepEqual(
    lines.slice(0, 5),
    [
      "Christophe Vanrokeghem",
      "handelend onder de naam Fluxidi",
      "Eenmanszaak",
      "Ondernemingsnummer: 0772.931.038",
      "BTW: BE 0772.931.038",
    ],
  );
});

test("format helpers and legal form normalization", () => {
  assert.equal(formatBelgianEnterpriseNumber("0772931038"), "0772.931.038");
  assert.equal(formatBelgianVatNumber("BE0772931038"), "BE 0772.931.038");
  assert.equal(normalizeLegalForm("Belgian sole proprietorship"), LEGAL_FORM_EENMANSZAAK);
  assert.equal(legalFormLabelNl(null), "");
  assert.equal(legalFormLabelNl("eenmanszaak"), "Eenmanszaak");
  assert.equal(isUnsafeInventedSellerLegalName("Fluxidi BV"), true);
  assert.equal(isUnsafeInventedSellerLegalName("Fluxidi Taxi"), true);
});

test("canonical sole prop is ready for issue", () => {
  const result = validateSellerIdentityForInvoiceIssuance(CANONICAL_SOLE);
  assert.equal(result.ok, true);
  assert.equal(result.identity.legal_seller_name, "Christophe Vanrokeghem");
});
