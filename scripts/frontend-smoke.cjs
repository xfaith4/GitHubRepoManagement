const fs = require('fs');
const path = require('path');

async function main() {
  const { chromium } = require('playwright');

  const baseUrl = process.env.FRONTEND_SMOKE_BASE_URL || 'http://127.0.0.1:7071';
  const outputDir = process.env.FRONTEND_SMOKE_OUTPUT_DIR || process.cwd();
  const screenshotPath = process.env.FRONTEND_SMOKE_SCREENSHOT || path.join(outputDir, 'frontend-smoke.png');
  const reportPath = process.env.FRONTEND_SMOKE_REPORT || path.join(outputDir, 'frontend-smoke.json');
  const timeoutMs = Number(process.env.FRONTEND_SMOKE_TIMEOUT_MS || '90000');
  const headingText = 'GitHub Repo Manager';

  fs.mkdirSync(outputDir, { recursive: true });

  const report = {
    baseUrl,
    startedAt: new Date().toISOString(),
    headingFound: false,
    backendOnline: false,
    portfolioAssessmentLoaded: false,
    portfolioAnalyticsLoaded: false,
    documentationHealthLoaded: false,
    executionThroughputLoaded: false,
    narrowViewportOk: false,
    narrowViewport: null,
    narrowBottomNavVisible: false,
    narrowBodyScrollWidth: null,
    narrowInnerWidth: null,
    manifestLinked: false,
    manifestValid: false,
    manifestStatus: null,
    setupWizardRendered: false,
    agentActivityIndicatorVisible: false,
    mobileRepoHealthVisible: false,
    consoleMessages: [],
    failedRequests: [],
    errorResponses: [],
    screenshotPath,
    success: false,
  };

  let browser;
  try {
    try {
      browser = await chromium.launch({ headless: true, channel: 'msedge' });
      report.browser = 'msedge';
    } catch {
      browser = await chromium.launch({ headless: true });
      report.browser = 'chromium';
    }

    const page = await browser.newPage({ viewport: { width: 1440, height: 1600 } });
    page.setDefaultTimeout(timeoutMs);

    page.on('console', msg => {
      const type = msg.type();
      if (type === 'error' || type === 'warning') {
        report.consoleMessages.push({
          type,
          text: msg.text(),
        });
      }
    });

    page.on('requestfailed', req => {
      report.failedRequests.push({
        url: req.url(),
        method: req.method(),
        errorText: req.failure() ? req.failure().errorText : 'unknown',
      });
    });

    page.on('response', res => {
      const url = res.url();
      if (url.includes('/api/') && res.status() >= 400) {
        report.errorResponses.push({
          url,
          status: res.status(),
          statusText: res.statusText(),
        });
      }
    });

    await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
    await page.getByText(headingText, { exact: true }).waitFor();
    report.headingFound = true;

    try {
      await page.getByText('Backend: Online', { exact: false }).waitFor({ timeout: 30000 });
      report.backendOnline = true;
    } catch {
      report.backendOnline = false;
    }

    // Release 2.5 Phase 2 — always-visible agent-activity indicator.
    try {
      await page.locator('[data-testid="agent-activity-indicator"]').first().waitFor({ state: 'visible', timeout: timeoutMs });
      report.agentActivityIndicatorVisible = true;
    } catch {
      report.agentActivityIndicatorVisible = false;
    }

    // The secondary analytics widgets (Portfolio Analytics, Execution
    // Throughput, Documentation Health) were moved into the Insights view by
    // the 2026-07-03 Repository-Grid UX refactor, so navigate there before
    // asserting them. The desktop view tab (first DOM match) is visible at the
    // 1440px probe width; the mobile bottom-nav twin is md:hidden here.
    try {
      await page.getByRole('button', { name: 'Insights', exact: true }).first().click();
      report.insightsViewOpened = true;
    } catch (err) {
      report.insightsViewOpened = false;
    }

    const portfolioLoading = page.getByText('Loading portfolio assessment…', { exact: true });
    const docsLoading = page.getByText('Computing documentation health…', { exact: true });

    try {
      await portfolioLoading.waitFor({ state: 'hidden', timeout: timeoutMs });
      report.portfolioAssessmentLoaded = true;
    } catch {
      report.portfolioAssessmentLoaded = false;
    }

    try {
      await docsLoading.waitFor({ state: 'hidden', timeout: timeoutMs });
      report.documentationHealthLoaded = true;
    } catch {
      report.documentationHealthLoaded = false;
    }

    try {
      const portfolioAnalyticsSection = page.locator('section').filter({
        has: page.getByRole('heading', { name: 'Portfolio Analytics' }),
      }).first();
      await portfolioAnalyticsSection.waitFor({ state: 'visible', timeout: timeoutMs });
      await portfolioAnalyticsSection.getByText('Loading portfolio analytics…', { exact: true }).waitFor({ state: 'hidden', timeout: timeoutMs });
      await portfolioAnalyticsSection.getByText('Avg Maturity', { exact: true }).first().waitFor({ timeout: timeoutMs });
      await portfolioAnalyticsSection.getByText('Visible Window', { exact: true }).first().waitFor({ timeout: timeoutMs });
      report.portfolioAnalyticsLoaded = true;
    } catch {
      report.portfolioAnalyticsLoaded = false;
    }

    try {
      await page.getByRole('heading', { name: 'Execution Throughput' }).waitFor({ timeout: timeoutMs });
      await page.getByText('Loading execution metrics…', { exact: true }).waitFor({ state: 'hidden', timeout: timeoutMs });
      await page.getByText('Done Today', { exact: true }).waitFor({ timeout: timeoutMs });
      await page.getByText('Ready Queue', { exact: true }).waitFor({ timeout: timeoutMs });
      report.executionThroughputLoaded = true;
    } catch {
      report.executionThroughputLoaded = false;
    }

    await page.screenshot({ path: screenshotPath, fullPage: true });

    // Release 2.5 Phase 1 — narrow-viewport (Android phone) acceptance check.
    // Acceptance criterion: at a 360-412px viewport the dashboard renders with
    // no horizontal body scrolling (wide content must scroll inside its own
    // container, never the page body) and the mobile bottom nav takes over.
    try {
      const narrowWidth = 390;
      await page.setViewportSize({ width: narrowWidth, height: 844 });
      report.narrowViewport = { width: narrowWidth, height: 844 };
      // Allow CSS media-query reflow to settle, then re-assert the app shell.
      await page.getByText(headingText, { exact: true }).first().waitFor({ timeout: timeoutMs });
      const bottomNav = page.locator('nav[aria-label="Primary views"]');
      await bottomNav.waitFor({ state: 'visible', timeout: timeoutMs });
      report.narrowBottomNavVisible = true;

      // Release 2.5 Phase 2 — glanceable mobile Repo-Health panel (mobile-only).
      try {
        await page.locator('[data-testid="mobile-repo-health"]').first().waitFor({ state: 'visible', timeout: timeoutMs });
        report.mobileRepoHealthVisible = true;
      } catch {
        report.mobileRepoHealthVisible = false;
      }

      const metrics = await page.evaluate(() => {
        const el = document.scrollingElement || document.documentElement;
        return { scrollWidth: el.scrollWidth, innerWidth: window.innerWidth };
      });
      report.narrowBodyScrollWidth = metrics.scrollWidth;
      report.narrowInnerWidth = metrics.innerWidth;
      // 1px tolerance for sub-pixel rounding. A body wider than the viewport
      // means content is overflowing the page body — a Phase 1 regression.
      const noHorizontalBodyScroll = metrics.scrollWidth <= metrics.innerWidth + 1;
      report.narrowViewportOk = report.narrowBottomNavVisible && noHorizontalBodyScroll;

      const narrowScreenshotPath = screenshotPath.replace(/\.png$/i, '') + '-narrow.png';
      await page.screenshot({ path: narrowScreenshotPath, fullPage: true });
      report.narrowScreenshotPath = narrowScreenshotPath;
    } catch (err) {
      report.narrowViewportOk = false;
      report.narrowViewportError = err && err.message ? err.message : String(err);
    }

    // Release 2.5 Phase 4 — installable web app manifest (home-screen install).
    try {
      const manifestHref = await page.getAttribute('link[rel="manifest"]', 'href');
      report.manifestLinked = !!manifestHref;
      const manifestUrl = new URL(manifestHref || '/manifest.webmanifest', baseUrl).toString();
      const mResp = await page.request.get(manifestUrl);
      report.manifestStatus = mResp.status();
      const mJson = await mResp.json();
      report.manifestValid = !!(
        mJson &&
        mJson.name &&
        mJson.start_url &&
        mJson.display === 'standalone' &&
        Array.isArray(mJson.icons) &&
        mJson.icons.length > 0
      );
    } catch (err) {
      report.manifestValid = false;
      report.manifestError = err && err.message ? err.message : String(err);
    }

    // Release 2.2 — guided Setup Wizard renders on first run (?setup=1 forces it).
    try {
      await page.setViewportSize({ width: 1440, height: 1600 });
      await page.goto(baseUrl + '?setup=1', { waitUntil: 'domcontentloaded' });
      const wizard = page.locator('[role="dialog"][aria-label="Setup Wizard"]');
      await wizard.waitFor({ state: 'visible', timeout: timeoutMs });
      await page.getByText('Step 1 of 4', { exact: false }).waitFor({ timeout: timeoutMs });
      report.setupWizardRendered = true;
    } catch (err) {
      report.setupWizardRendered = false;
      report.setupWizardError = err && err.message ? err.message : String(err);
    }

    report.finishedAt = new Date().toISOString();
    report.success =
      report.headingFound &&
      report.backendOnline &&
      report.portfolioAssessmentLoaded &&
      report.portfolioAnalyticsLoaded &&
      report.documentationHealthLoaded &&
      report.executionThroughputLoaded &&
      report.narrowViewportOk &&
      report.manifestLinked &&
      report.manifestValid &&
      report.setupWizardRendered &&
      report.agentActivityIndicatorVisible &&
      report.mobileRepoHealthVisible &&
      report.failedRequests.length === 0 &&
      report.errorResponses.length === 0 &&
      report.consoleMessages.filter(entry => entry.type === 'error').length === 0;

    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

    if (!report.success) {
      const problems = [];
      if (!report.backendOnline) problems.push('backend health badge did not report online');
      if (!report.portfolioAssessmentLoaded) problems.push('portfolio assessment panel did not finish loading');
      if (!report.portfolioAnalyticsLoaded) problems.push('portfolio analytics panel did not finish loading');
      if (!report.documentationHealthLoaded) problems.push('documentation health panel did not finish loading');
      if (!report.executionThroughputLoaded) problems.push('execution throughput card did not finish loading');
      if (!report.narrowViewportOk) {
        const detail = report.narrowViewportError
          ? report.narrowViewportError
          : `body scrollWidth ${report.narrowBodyScrollWidth} > viewport ${report.narrowInnerWidth} (horizontal body scroll) or bottom nav missing`;
        problems.push(`narrow-viewport (390px) check failed: ${detail}`);
      }
      if (!report.manifestLinked) problems.push('no <link rel="manifest"> in the app shell');
      if (!report.manifestValid) {
        problems.push(`web app manifest invalid or unreachable (status ${report.manifestStatus}${report.manifestError ? ': ' + report.manifestError : ''})`);
      }
      if (!report.setupWizardRendered) {
        problems.push(`setup wizard did not render at ?setup=1${report.setupWizardError ? ': ' + report.setupWizardError : ''}`);
      }
      if (!report.agentActivityIndicatorVisible) problems.push('agent-activity indicator not visible in the header');
      if (!report.mobileRepoHealthVisible) problems.push('mobile Repo-Health panel not visible at 390px');
      if (report.failedRequests.length > 0) problems.push(`${report.failedRequests.length} request(s) failed`);
      if (report.errorResponses.length > 0) problems.push(`${report.errorResponses.length} API response(s) returned >= 400`);
      if (report.consoleMessages.some(entry => entry.type === 'error')) problems.push('browser console contained error messages');
      throw new Error(`Frontend smoke failed: ${problems.join('; ')}`);
    }
  } finally {
    if (browser) {
      await browser.close();
    }
    if (!report.finishedAt) {
      report.finishedAt = new Date().toISOString();
      fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    }
  }
}

main().catch(err => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
