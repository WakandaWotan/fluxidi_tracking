/// Public partner routing fields on a quote or booking body.
///
/// Ported from golden commit 9df7e7b92ecc86a11184ee995e255da7b8f6fb68:
/// `lib/customer_booking/customer_booking_quote.dart` —
/// `CustomerBookingQuoteClient.decorateBody`.
///
/// This is routing and scope, not authentication: a public partner id gives the
/// server the company to price for, it is never a company login.
library;

class FluxidiPartnerScope {
  const FluxidiPartnerScope({
    this.partnerId = '',
    this.tenantId = '',
    this.companyId = '',
    this.companyName = '',
    this.entryKind = 'taxi',
    this.sourceLabel = '',
  });

  final String partnerId;
  final String tenantId;
  final String companyId;
  final String companyName;

  /// How the customer entered the flow, e.g. `taxi` or `companyPage`.
  final String entryKind;

  final String sourceLabel;

  /// Partner id the server routes on: the explicit partner id, else the company.
  String get routingPartnerId {
    final partner = partnerId.trim();
    if (partner.isNotEmpty) return partner;
    return companyId.trim();
  }

  bool get hasRouting => routingPartnerId.isNotEmpty;

  /// Adds the routing fields to [body] without touching anything else.
  Map<String, dynamic> decorate(Map<String, dynamic> body) {
    final next = Map<String, dynamic>.from(body);
    final routing = routingPartnerId;
    if (routing.isNotEmpty) {
      next['public_partner_id'] = routing;
      next['publicPartnerId'] = routing;
      next['partner_id'] = routing;
      next['partnerId'] = routing;
    }
    if (tenantId.trim().isNotEmpty) {
      next['tenant_id'] = tenantId.trim();
      next['tenantId'] = tenantId.trim();
    }
    if (companyId.trim().isNotEmpty) {
      next['company_id'] = companyId.trim();
      next['companyId'] = companyId.trim();
    }
    if (companyName.trim().isNotEmpty) {
      next['public_partner_name'] = companyName.trim();
    }
    if (sourceLabel.trim().isNotEmpty) {
      next['source_label'] = sourceLabel.trim();
    }
    next['entry_kind'] = entryKind;
    return next;
  }
}
