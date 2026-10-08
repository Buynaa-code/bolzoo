import 'package:hamtdaa/billing/subscription_controller.dart';
import 'package:hamtdaa/cloudflare/cloudflare_auth_repository.dart';

import '../billing/billing_fakes.dart';

SubscriptionController shellBilling(CloudflareAuthRepository auth) =>
    SubscriptionController(
      repository: FakeBillingRepository(),
      store: FakeStoreGateway(provider: null),
    );
