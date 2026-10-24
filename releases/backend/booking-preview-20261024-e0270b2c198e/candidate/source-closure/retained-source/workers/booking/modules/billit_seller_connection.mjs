// Reserved platform seller authority; company OAuth connections are separate.
export const BILLIT_SELLER_SCOPE = Object.freeze({tenant_id: 'fluxidi_platform', company_id: 'fluxidi_be0772931038'});
export const BILLIT_SELLER_PARTY_ID = '6532054';
export function isBillitSellerScope(scope) {
  return scope?.tenant_id === BILLIT_SELLER_SCOPE.tenant_id && scope?.company_id === BILLIT_SELLER_SCOPE.company_id;
}
export function billitSellerConnectionGuard(scope, config, partyId) {
  if (!isBillitSellerScope(scope)) return {ok: true};
  if (config?.environment !== 'production') return {ok: false, error: 'seller_requires_production'};
  for (const [field, host] of [['api_base_url', 'api.billit.be'], ['token_url', 'api.billit.be'], ['authorize_url', 'my.billit.be']]) {
    try {
      const url = new URL(config[field]);
      if (url.protocol !== 'https:' || url.hostname !== host || url.port || url.username || url.password) return {ok: false, error: 'seller_provider_host_invalid'};
    } catch (_) { return {ok: false, error: 'seller_provider_host_invalid'}; }
  }
  if (partyId !== undefined && String(partyId) !== BILLIT_SELLER_PARTY_ID) return {ok: false, error: 'seller_party_mismatch'};
  return {ok: true};
}
