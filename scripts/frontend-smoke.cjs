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
    documentationHealthLoaded: false,
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

    await page.screenshot({ path: screenshotPath, fullPage: true });

    report.finishedAt = new Date().toISOString();
    report.success =
      report.headingFound &&
      report.backendOnline &&
      report.portfolioAssessmentLoaded &&
      report.documentationHealthLoaded &&
      report.failedRequests.length === 0 &&
      report.errorResponses.length === 0 &&
      report.consoleMessages.filter(entry => entry.type === 'error').length === 0;

    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

    if (!report.success) {
      const problems = [];
      if (!report.backendOnline) problems.push('backend health badge did not report online');
      if (!report.portfolioAssessmentLoaded) problems.push('portfolio assessment panel did not finish loading');
      if (!report.documentationHealthLoaded) problems.push('documentation health panel did not finish loading');
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
