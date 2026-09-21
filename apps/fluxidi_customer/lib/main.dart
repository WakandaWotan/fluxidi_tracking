import 'package:flutter/material.dart';

import 'app/fluxidi_customer_app.dart';
import 'deeplinks/customer_deep_link_source.dart';

void main() {
  runApp(
    FluxidiCustomerApp(deepLinkSource: AppLinksCustomerDeepLinkSource()),
  );
}
