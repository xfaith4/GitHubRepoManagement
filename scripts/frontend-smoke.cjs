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
    // Release 2.6 Phase 1 — trust & orientation.
    dataSourceIndicatorVisible: false,
    dataSourceIndicatorPersistsAcrossTabs: false,
    dataSourceKind: null,
    toolbarButtonsLabeled: false,
    needsAttentionRescoped: false,
    needsAttentionValue: null,
    totalReposValue: null,
    // Release 2.6 Phase 2 — navigation & naming.
    orientationOverlayShown: false,
    orientationListsAllTabs: false,
    orientationDismissalPersists: false,
    viewSubtitleOk: false,
    queuesRenamed: false,
    // Release 2.6 Phase 3 — progressive disclosure.
    advancedFiltersToggleOk: false,
    workQueueWhyInlineOk: false,
    // Release 2.6 Phase 4 — consistency pass.
    actionLabelPatternOk: false,
    badgeDefinitionsOk: false,
    // Release 2.6 Phase 5 — contextual help & empty states.
    bulkSelectionNotePromoted: false,
    executionLaneEmptyStateOk: false,
    dependenciesEmptyStateShown: false,
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
      const errorText = req.failure() ? req.failure().errorText : 'unknown';
      // Ignore client-side aborts (navigation / component unmount /
      // AbortController timeouts). These are cancellations, not server failures;
      // real API errors surface via errorResponses (HTTP >= 400). Tab switches
      // in this smoke routinely abort an in-flight /health/live or poll request.
      if (errorText === 'net::ERR_ABORTED') return;
      report.failedRequests.push({
        url: req.url(),
        method: req.method(),
        errorText,
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

    // ── Release 2.6 Phase 2 — navigation & naming (runs first: the overlay is
    // a modal that would intercept the Phase 1 tab clicks below). ────────────
    try {
      const overlay = page.locator('[data-testid="orientation-overlay"]');
      await overlay.waitFor({ state: 'visible', timeout: timeoutMs });
      const overlayText = await overlay.innerText();
      const sixLabels = ['Repository Grid', 'Insights', 'Operations', 'Doc Readiness Queue', 'Dispatch Board', 'Dependencies'];
      report.orientationListsAllTabs = sixLabels.every(l => overlayText.includes(l));
      await page.locator('[data-testid="orientation-dismiss"]').click();
      await overlay.waitFor({ state: 'hidden', timeout: timeoutMs });
      // Dismissal is persisted to localStorage so the overlay never reappears on
      // a later visit. Assert the flag directly rather than reloading — a reload
      // aborts the app's in-flight polling requests (net::ERR_ABORTED), which is
      // unrelated to this check and would trip the failed-request gate.
      const dismissedFlag = await page.evaluate(() => {
        try { return localStorage.getItem('ghrm.orientationDismissed.v1'); } catch { return null; }
      });
      report.orientationDismissalPersists = dismissedFlag === '1';
      report.orientationOverlayShown = true;
    } catch (err) {
      report.orientationOverlayShown = false;
      report.orientationError = err && err.message ? err.message : String(err);
    }

    // Per-view purpose subtitle reflects the active tab (landing = Repository Grid).
    try {
      const subtitle = page.locator('[data-testid="view-subtitle"]').first();
      await subtitle.waitFor({ state: 'visible', timeout: timeoutMs });
      report.viewSubtitleText = (await subtitle.innerText()).trim();
      report.viewSubtitleOk = /main workspace/i.test(report.viewSubtitleText);
    } catch (err) {
      report.viewSubtitleOk = false;
      report.viewSubtitleError = err && err.message ? err.message : String(err);
    }

    // Queue renames: the two colliding tabs now carry distinct, self-describing
    // names, and the old ambiguous names are gone.
    try {
      await page.getByRole('button', { name: 'Doc Readiness Queue', exact: false }).first().waitFor({ state: 'visible', timeout: timeoutMs });
      // Lane 0.17 — renamed from "Copilot Execution Lanes": a dispatch board,
      // not an execution monitor.
      await page.getByRole('button', { name: 'Dispatch Board', exact: false }).first().waitFor({ state: 'visible', timeout: timeoutMs });
      const oldWork = await page.getByRole('button', { name: 'Work Queue', exact: true }).count();
      const oldExec = await page.getByRole('button', { name: 'Execution Queue', exact: true }).count();
      const oldLanes = await page.getByRole('button', { name: 'Copilot Execution Lanes', exact: true }).count();
      report.queuesRenamed = oldWork === 0 && oldExec === 0 && oldLanes === 0;
    } catch (err) {
      report.queuesRenamed = false;
      report.queuesRenamedError = err && err.message ? err.message : String(err);
    }

    // Release 2.6 Phase 1 — trust & orientation affordances (desktop viewport).
    // (a) Persistent, color-coded data-source indicator, visible on every tab.
    try {
      const indicator = page.locator('[data-testid="data-source-indicator"]').first();
      await indicator.waitFor({ state: 'visible', timeout: timeoutMs });
      report.dataSourceKind = await indicator.getAttribute('data-source-kind');
      report.dataSourceIndicatorVisible = true;
      // Must stay visible after switching tabs — Operations changes what is
      // shown without touching the active-source signal.
      await page.getByRole('button', { name: 'Operations', exact: false }).first().click();
      await indicator.waitFor({ state: 'visible', timeout: timeoutMs });
      report.dataSourceIndicatorPersistsAcrossTabs = true;
      await page.getByRole('button', { name: 'Repository Grid', exact: true }).first().click();
    } catch (err) {
      report.dataSourceIndicatorPersistsAcrossTabs = false;
      report.dataSourceIndicatorError = err && err.message ? err.message : String(err);
    }

    // (b) Icon-only toolbar controls expose accessible names (help/book/refresh/gear).
    try {
      for (const name of ['Help', 'API docs', 'Refresh', 'Settings']) {
        await page.getByRole('button', { name, exact: true }).first().waitFor({ state: 'visible', timeout: timeoutMs });
      }
      report.toolbarButtonsLabeled = true;
    } catch (err) {
      report.toolbarButtonsLabeled = false;
      report.toolbarButtonsError = err && err.message ? err.message : String(err);
    }

    // (c) "Needs Attention" is a meaningful subset (< total) with a discoverable
    // definition — not the ~100% ambient count the old predicate produced.
    try {
      const readCardValue = async (testId) => {
        const valueText = await page.locator(`[data-testid="${testId}"] p`).first().innerText();
        return Number(String(valueText).replace(/[^0-9-]/g, ''));
      };
      const total = await readCardValue('summary-total-repositories');
      const attention = await readCardValue('summary-needs-attention');
      report.totalReposValue = total;
      report.needsAttentionValue = attention;
      const hasDefinition = (await page.locator('[aria-label^="Needs Attention —"]').count()) > 0;
      report.needsAttentionRescoped =
        Number.isFinite(total) && Number.isFinite(attention) && total > 0 && attention < total && hasDefinition;
    } catch (err) {
      report.needsAttentionRescoped = false;
      report.needsAttentionError = err && err.message ? err.message : String(err);
    }

    // ── Release 2.6 Phase 3 — progressive disclosure ─────────────────────────
    // (a) Advanced-filters toggle: secondary filters are collapsed by default
    // and expand on click (proven via the "Duplicates" chip).
    try {
      const dupChip = page.getByRole('button', { name: 'Duplicates', exact: true });
      const hiddenByDefault = (await dupChip.count()) === 0 || !(await dupChip.first().isVisible());
      await page.locator('[data-testid="advanced-filters-toggle"]').first().click();
      await page.locator('[data-testid="advanced-filters-panel"]').first().waitFor({ state: 'visible', timeout: timeoutMs });
      await dupChip.first().waitFor({ state: 'visible', timeout: timeoutMs });
      report.advancedFiltersToggleOk = hiddenByDefault;
    } catch (err) {
      report.advancedFiltersToggleOk = false;
      report.advancedFiltersError = err && err.message ? err.message : String(err);
    }

    // (b) Doc Readiness Queue "Why?" opens the value rationale inline (not just
    // a hover tooltip).
    try {
      await page.getByRole('button', { name: 'Doc Readiness Queue', exact: false }).first().click();
      const whyToggle = page.locator('[data-testid="value-why-toggle"]').first();
      await whyToggle.waitFor({ state: 'visible', timeout: timeoutMs });
      await whyToggle.click();
      await page.locator('[data-testid="value-why-detail"]').first().waitFor({ state: 'visible', timeout: timeoutMs });
      report.workQueueWhyInlineOk = true;
    } catch (err) {
      report.workQueueWhyInlineOk = false;
      report.workQueueWhyError = err && err.message ? err.message : String(err);
    }
    // Return to the Repository Grid so downstream steps start from a known view.
    try { await page.getByRole('button', { name: 'Repository Grid', exact: true }).first().click(); } catch { /* best-effort */ }

    // ── Release 2.6 Phase 4 — consistency pass ───────────────────────────────
    // (a) Unified action-label pattern: "Planned" is a separate tag, never baked
    // into the label; no button accessible name contains "(Planned)".
    try {
      await page.getByRole('button', { name: 'Clone', exact: true }).first().waitFor({ state: 'visible', timeout: timeoutMs });
      await page.locator('[data-testid="action-status-tag"]', { hasText: 'Planned' }).first().waitFor({ state: 'visible', timeout: timeoutMs });
      const legacyPlanned = await page.getByRole('button', { name: /\(Planned\)/ }).count();
      report.actionLabelPatternOk = legacyPlanned === 0;
    } catch (err) {
      report.actionLabelPatternOk = false;
      report.actionLabelError = err && err.message ? err.message : String(err);
    }

    // (b) Filter chips carry hover-definition titles (no separate legend lookup).
    try {
      const dirtyTitle = await page.getByRole('button', { name: 'Dirty only', exact: true }).first().getAttribute('title');
      await page.locator('[data-testid="advanced-filters-toggle"]').first().click();
      await page.locator('[data-testid="advanced-filters-panel"]').first().waitFor({ state: 'visible', timeout: timeoutMs });
      const roadmapFlaggedTitle = await page.getByRole('button', { name: 'ROADMAP flagged', exact: true }).first().getAttribute('title');
      report.badgeDefinitionsOk = Boolean(dirtyTitle && dirtyTitle.length > 10 && roadmapFlaggedTitle && roadmapFlaggedTitle.length > 10);
    } catch (err) {
      report.badgeDefinitionsOk = false;
      report.badgeDefinitionsError = err && err.message ? err.message : String(err);
    }

    // ── Release 2.6 Phase 5 — contextual help & empty states ─────────────────
    // (a) Behavior-changing bulk-selection note is promoted (icon + bold key
    // phrase), not plain gray metadata.
    // With zero repositories in scope the implicit-bulk-scope note is replaced
    // by the actual blocker ("scan a workspace first"), so accept either
    // variant — but require the state-appropriate one.
    try {
      const note = page.locator('[data-testid="bulk-selection-note"]').first();
      await note.waitFor({ state: 'visible', timeout: timeoutMs });
      const noteText = await note.innerText();
      const hasNoReposHint = (await note.locator('[data-testid="no-repos-hint"]').count()) > 0;
      if (hasNoReposHint) {
        report.bulkSelectionNoteState = 'no-repos';
        report.bulkSelectionNotePromoted = /scan a workspace first/i.test(noteText);
      } else {
        const strongCount = await note.locator('strong').count();
        report.bulkSelectionNoteState = 'bulk-scope';
        report.bulkSelectionNotePromoted = strongCount > 0 && /full filtered repository set/i.test(noteText);
      }
    } catch (err) {
      report.bulkSelectionNotePromoted = false;
      report.bulkSelectionNoteError = err && err.message ? err.message : String(err);
    }

    // (b) Empty Dispatch Board lanes carry explanatory guidance (how to fill).
    try {
      await page.getByRole('button', { name: 'Dispatch Board', exact: false }).first().click();
      const emptyLane = page.locator('[data-testid="execution-lane-empty"]').first();
      await emptyLane.waitFor({ state: 'visible', timeout: timeoutMs });
      report.executionLaneEmptyStateOk = /queue below/i.test(await emptyLane.innerText());
    } catch (err) {
      report.executionLaneEmptyStateOk = false;
      report.executionLaneEmptyError = err && err.message ? err.message : String(err);
    }

    // (c) Dependencies zero-result explanatory empty state (best-effort — only
    // meaningful when the portfolio has no detected edges; not gated).
    try {
      await page.getByRole('button', { name: 'Dependencies', exact: false }).first().click();
      report.dependenciesEmptyStateShown = await page.locator('[data-testid="dependencies-empty-state"]').first()
        .waitFor({ state: 'visible', timeout: 20000 }).then(() => true).catch(() => false);
    } catch { /* best-effort */ }
    try { await page.getByRole('button', { name: 'Repository Grid', exact: true }).first().click(); } catch { /* best-effort */ }

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
      report.dataSourceIndicatorVisible &&
      report.dataSourceIndicatorPersistsAcrossTabs &&
      report.toolbarButtonsLabeled &&
      report.needsAttentionRescoped &&
      report.orientationOverlayShown &&
      report.orientationListsAllTabs &&
      report.orientationDismissalPersists &&
      report.viewSubtitleOk &&
      report.queuesRenamed &&
      report.advancedFiltersToggleOk &&
      report.workQueueWhyInlineOk &&
      report.actionLabelPatternOk &&
      report.badgeDefinitionsOk &&
      report.bulkSelectionNotePromoted &&
      report.executionLaneEmptyStateOk &&
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
      if (!report.dataSourceIndicatorVisible) problems.push(`persistent data-source indicator not visible${report.dataSourceIndicatorError ? ': ' + report.dataSourceIndicatorError : ''}`);
      if (!report.dataSourceIndicatorPersistsAcrossTabs) problems.push('data-source indicator did not persist after switching tabs');
      if (!report.toolbarButtonsLabeled) problems.push(`icon-only toolbar buttons lack accessible labels${report.toolbarButtonsError ? ': ' + report.toolbarButtonsError : ''}`);
      if (!report.needsAttentionRescoped) problems.push(`"Needs Attention" not a defined subset < total (attention ${report.needsAttentionValue} / total ${report.totalReposValue})${report.needsAttentionError ? ': ' + report.needsAttentionError : ''}`);
      if (!report.orientationOverlayShown) problems.push(`orientation overlay did not show/dismiss on first visit${report.orientationError ? ': ' + report.orientationError : ''}`);
      if (!report.orientationListsAllTabs) problems.push('orientation overlay did not name all six tabs');
      if (!report.orientationDismissalPersists) problems.push('orientation overlay reappeared after reload (dismissal not persisted)');
      if (!report.viewSubtitleOk) problems.push(`per-view subtitle missing/incorrect on landing (${report.viewSubtitleText || 'n/a'})`);
      if (!report.queuesRenamed) problems.push(`queue tabs not renamed to distinct names${report.queuesRenamedError ? ': ' + report.queuesRenamedError : ''}`);
      if (!report.advancedFiltersToggleOk) problems.push(`advanced-filters toggle did not collapse/expand secondary filters${report.advancedFiltersError ? ': ' + report.advancedFiltersError : ''}`);
      if (!report.workQueueWhyInlineOk) problems.push(`Doc Readiness Queue "Why?" did not expand inline${report.workQueueWhyError ? ': ' + report.workQueueWhyError : ''}`);
      if (!report.actionLabelPatternOk) problems.push(`action-label pattern wrong (legacy "(Planned)" label or missing status tag)${report.actionLabelError ? ': ' + report.actionLabelError : ''}`);
      if (!report.badgeDefinitionsOk) problems.push(`filter chips missing hover-definition titles${report.badgeDefinitionsError ? ': ' + report.badgeDefinitionsError : ''}`);
      if (!report.bulkSelectionNotePromoted) problems.push(`bulk-selection note not promoted (icon + bold key phrase)${report.bulkSelectionNoteError ? ': ' + report.bulkSelectionNoteError : ''}`);
      if (!report.executionLaneEmptyStateOk) problems.push(`empty execution lane missing explanatory guidance${report.executionLaneEmptyError ? ': ' + report.executionLaneEmptyError : ''}`);
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
