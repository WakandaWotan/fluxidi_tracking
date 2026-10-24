// Invoice parties are private reviewed evidence, never a public checkout input.
// User-confirmed proprietor identity is distinct from active VAT verification.
export const FLUXIDI_SELLER_ID = 'fluxidi_be0772931038';
const seller = Object.freeze({ version: 'invoice_party_v1', party_id: FLUXIDI_SELLER_ID, revision: 1,
  legal_name: 'Christophe Vanrokeghem', trade_name: 'Fluxidi', enterprise_number: '0772931038', vat_number: 'BE0772931038',
  street: 'Koekamerstraat', house_number: '48A', postal_code: '9688', locality: 'Maarkedal', country: 'BE' });
const text = (v, max = 200) => typeof v === 'string' && v.length > 0 && v.length <= max && v.trim() === v &&
  !/[\x00-\x1f\x7f]/.test(v);
const plain = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const fail = () => ({ ok: false, error: 'subscription_invoice_parties_unproved' });
export function confirmedFluxidiSellerIdentity() { return { ...seller }; }
export function subscriptionInvoiceParties(decision) {
  const raw = decision?.invoice_parties_json;
  if (raw === undefined && decision?.seller_id !== FLUXIDI_SELLER_ID) return { ok: true };
  if (!text(raw, 6000)) return fail();
  let source;
  try { source = JSON.parse(raw); } catch (_) { return fail(); }
  if (!plain(source) || source.version !== 'subscription_invoice_parties_v1' || !plain(source.seller) || !plain(source.customer)) return fail();
  if (decision.seller_id !== FLUXIDI_SELLER_ID || decision.seller_country !== seller.country ||
      Object.entries(seller).some(([key, value]) => source.seller[key] !== value)) return fail();
  const customer = source.customer;
  if (customer.version !== 'invoice_party_v1' || customer.party_id !== decision.company_id ||
      !Number.isSafeInteger(customer.revision) || customer.revision < 1 || customer.country !== decision.customer_country || !/^[A-Z]{2}$/.test(customer.country || '') ||
      !text(customer.legal_name) || !text(customer.street) || !text(customer.house_number, 40) ||
      !text(customer.postal_code, 20) || !text(customer.locality, 120) ||
      !text(customer.enterprise_number, 80)) return fail();
  if (decision.customer_vat_status === 'verified_valid' && (!text(customer.vat_number, 40) ||
      !new RegExp('^' + customer.country + '[A-Z0-9]{2,20}$').test(customer.vat_number))) return fail();
  if (customer.vat_number !== undefined && (!text(customer.vat_number, 40) ||
      !new RegExp('^' + customer.country + '[A-Z0-9]{2,20}$').test(customer.vat_number))) return fail();
  const clean = { version: 'invoice_party_v1', party_id: customer.party_id, revision: customer.revision,
    legal_name: customer.legal_name, enterprise_number: customer.enterprise_number,
    ...(customer.vat_number !== undefined ? { vat_number: customer.vat_number } : {}),
    street: customer.street, house_number: customer.house_number, postal_code: customer.postal_code,
    locality: customer.locality, country: customer.country };
  return { ok: true, invoice_parties_json: JSON.stringify({ version: source.version, seller: { ...seller }, customer: clean }) };
}
