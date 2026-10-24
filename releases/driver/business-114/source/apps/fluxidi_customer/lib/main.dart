import 'package:flutter/material.dart';

import 'app/customer_app_config.dart';
import 'app/fluxidi_customer_app.dart';
import 'bridge/customer_runtime.dart';
import 'deeplinks/customer_deep_link_source.dart';

Future<void> main() async {
  await bootCustomerRuntime(config: kCustomerAppConfig);
  runApp(
    FluxidiCustomerApp(deepLinkSource: AppLinksCustomerDeepLinkSource()),
  );
}
