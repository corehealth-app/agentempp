// Exact public TRANSFER example retrieved 2026-10-29 from:
// https://www.revenuecat.com/docs/integrations/webhooks/sample-events
// Static vendor sample identifiers, not real Performe customer data.
export const officialRevenueCatTransfer = {
  event: {
    app_id: '1234567890',
    event_timestamp_ms: 78789789798798,
    id: 'CD489E0E-5D52-4E03-966B-A7F17788E432',
    store: 'APP_STORE',
    transferred_from: ['00005A1C-6091-4F81-BE77-F0A83A271AB6'],
    transferred_to: ['4BEDB450-8EF2-11E9-B475-0800200C9A66'],
    type: 'TRANSFER',
    environment: 'PRODUCTION',
  },
  api_version: '1.0',
}

// Derived from the documented TEST/identity/lifecycle field contract, not an
// observed dashboard delivery or an exact published TEST sample:
// https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields
export const contractRevenueCatTest = {
  api_version: '1.0',
  event: {
    id: 'synthetic-dashboard-test-001',
    type: 'TEST',
    event_timestamp_ms: 1784887200000,
    app_id: 'synthetic-app',
    app_user_id: 'synthetic-test-user',
    original_app_user_id: 'synthetic-test-user',
    aliases: ['synthetic-test-user'],
    product_id: 'synthetic-test-product',
    period_type: 'NORMAL',
    purchased_at_ms: 1784887200000,
    expiration_at_ms: 1787565600000,
    environment: 'SANDBOX',
    entitlement_id: null,
    entitlement_ids: null,
    presented_offering_id: null,
    transaction_id: 'synthetic-test-transaction',
    original_transaction_id: 'synthetic-test-transaction',
    is_family_share: false,
    country_code: 'US',
    store: 'APP_STORE',
  },
}
