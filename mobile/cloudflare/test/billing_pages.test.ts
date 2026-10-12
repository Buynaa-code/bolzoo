import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { handleBillingPage } from '../src/billing_pages';
const configured = { ...env, LEGAL_OPERATOR_NAME: 'Test service', LEGAL_SUPPORT_EMAIL: 'support@example.test' };
const request = (path: string, method = 'GET') => new Request(`https://auth.test${path}`, { method });
describe('standalone billing and legal pages', () => {
  it('renders an explicitly disabled draft until legal identity is provided', async () => {
    const response = handleBillingPage(request('/plans'), { ...env, BILLING_ENABLED: 'true', BILLING_WEB_ENABLED: 'true',
      LEGAL_OPERATOR_NAME: undefined, LEGAL_SUPPORT_EMAIL: undefined })!;
    expect(response.status).toBe(200);
    const text = await response.text();
    expect(text).toContain('data-legal-ready="false"');
    expect(text).toContain('Төсөл · Төлбөр идэвхгүй');
    expect(text).toContain('id="buy" type="button" disabled');
    expect(text).toContain('9,900 ₮'); expect(text).toContain('79,900 ₮');
    expect(text).toContain('30 хоног'); expect(text).toContain('365 хоног');
    expect(text).toContain('Автоматаар сунгахгүй.');
  });
  it('uses external local assets and a strict no-inline-script content policy', async () => {
    for (const path of ['/plans', '/privacy', '/terms', '/web-terms']) {
      const response = handleBillingPage(request(path), configured)!;
      const csp = response.headers.get('Content-Security-Policy')!;
      expect(csp).toContain("script-src 'self'");
      expect(csp).toContain("connect-src 'self'");
      expect(csp).toContain("frame-ancestors 'none'");
      expect(csp).not.toContain('unsafe-inline');
      expect(response.headers.get('Referrer-Policy')).toBe('no-referrer');
      const text = await response.text();
      expect(text).not.toMatch(/<script(?! src=)/);
      expect(text).not.toMatch(/\son[a-z]+=/i);
      expect(text).not.toContain('style=');
    }
  });
  it('escapes operator identity and never interpolates secrets or query tokens', async () => {
    const response = handleBillingPage(request('/plans?token=do-not-render'), { ...configured,
      LEGAL_OPERATOR_NAME: '<script>alert("x")</script>', WIRE_API_KEY: 'sk_live_do_not_render',
      WIRE_WEBHOOK_SECRET: 'whsec_do_not_render', BETTER_AUTH_SECRET: 'private-do-not-render' })!;
    const text = await response.text();
    expect(text).toContain('&lt;script&gt;');
    expect(text).not.toContain('<script>alert');
    expect(text).not.toContain('do-not-render');
    expect(text).not.toContain('do_not_render');
    expect(text).toContain('data-legal-ready="true"');
  });
  it('keeps legal pages independent of the alternative checkout route', async () => {
    for (const path of ['/terms', '/privacy', '/web-terms']) {
      const text = await handleBillingPage(request(path), configured)!.text();
      expect(text).not.toContain('href="/plans"');
      expect(text).not.toContain('plans.js');
      expect(text).toContain('support@example.test');
    }
  });
  it('separates native terms from the web purchase terms without checkout links', async () => {
    const native = await handleBillingPage(request('/terms'), configured)!.text();
    expect(native).not.toContain('QPay'); expect(native).not.toContain('9,900');
    expect(native).not.toContain('/web-terms'); expect(native).not.toContain('/plans');
    const web = await handleBillingPage(request('/web-terms'), configured)!.text();
    expect(web).toContain('9,900'); expect(web).toContain('79,900'); expect(web).not.toContain('href="/plans"');
    const plans = await handleBillingPage(request('/plans'), configured)!.text();
    expect(plans).toContain('href="/web-terms"'); expect(plans).not.toContain('href="/terms"');
  });
  it('ships client guards for legal readiness, exact hosted origin, ownership polling and memory-only credentials', async () => {
    const response = handleBillingPage(request('/billing-assets/plans.js'), configured)!;
    expect(response.headers.get('Content-Type')).toContain('text/javascript');
    const js = await response.text();
    expect(js).toContain("url.origin === 'https://pay.wire.mn'");
    expect(js).toContain("credentials: 'omit'");
    expect(js).toContain("headers.Authorization = 'Bearer ' + token");
    expect(js).toContain("api('/v1/billing/web/status', { order_id: pending.order_id })");
    expect(js).toContain('if (!legalReady || !catalog || !catalog.web || catalog.web.ready !== true)');
    expect(js).toContain('sessionStorage.setItem(storageKey, JSON.stringify(pending))');
    expect(js).not.toContain('localStorage');
    expect(js).not.toContain('innerHTML');
    expect(js).not.toContain('document.write');
    expect(js).not.toContain('console.');
    expect(js).not.toMatch(/(?:sessionStorage|localStorage)[^\n]*token/);
  });
  it('serves HEAD without a body, rejects mutations and ignores unrelated routes', async () => {
    const head = handleBillingPage(request('/privacy', 'HEAD'), configured)!;
    expect(head.status).toBe(200); expect(await head.text()).toBe('');
    expect(handleBillingPage(request('/plans', 'POST'), configured)!.status).toBe(405);
    expect(handleBillingPage(request('/unrelated'), configured)).toBeNull();
  });
});
