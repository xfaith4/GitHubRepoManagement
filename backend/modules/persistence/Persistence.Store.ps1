<#
.SYNOPSIS
    SQLite persistence foundation for Release 2.1 (Persistent Data Layer),
    Phase 1.

.DESCRIPTION
    Provides the first persistence boundary for the application:

      - SQLite capability detection (Get-SqliteCapability). No external
        dependency is required on Windows: the bridge P/Invokes the
        OS-shipped winsqlite3.dll. On WSL/Linux/macOS it probes the system
        libsqlite3. A missing provider degrades gracefully — callers get a
        truthful capability report instead of an exception.
      - Database bootstrap (Initialize-AppDatabase) that creates
        output/app.db and applies the schema-v1 tables for execution,
        maturity, ops-log, portfolio-index, repo-signal, differential-scan,
        merge-readiness, agent-run, and agent-run-event history.
      - Thin query helpers (Invoke-AppDbQuery / Invoke-AppDbNonQuery) with
        parameterized SQL only — callers never string-interpolate values.
        Invoke-AppDbTransaction runs multi-statement work over one
        connection inside BEGIN IMMEDIATE / COMMIT.
      - The first migration seam: Write-AppDbAgentRunEvent mirrors
        agent-run lifecycle events into the database. During rollout the
        JSON/JSONL stores remain authoritative; the database is additive.
      - Phase 2 stores: Read-AppDbExecutionLedger / Write-AppDbExecutionLedger
        make SQLite the authoritative execution-ledger store for the
        initialized workspace (first read seeds from the legacy
        execution-ledger.json), and Write-AppDbOpsLogEntry /
        Get-AppDbOpsLogEntries / Invoke-AppDbOpsLogTrim /
        Import-AppDbOpsLogFromJsonl back the queryable operations log.
      - Phase 3 stores (schema v2): Write-AppDbAgentRun mirrors agent-run
        ledger records (timing/token/cost/work-unit metrics) into agent_runs,
        Write-AppDbQuotaBurnSnapshot captures each dispatch quota evaluation
        into quota_burn_snapshots, and Get-AppDbAgentRunMetricsHistory /
        Get-AppDbQuotaBurnHistory expose both as ordered time series (the
        metrics read seeds agent_runs from the JSON runs directory on first
        read, mirroring the execution-ledger pattern).

    Rollout contract (Release 2.1): JSON-backed artifacts keep working and
    keep being written. From Phase 2 the database is authoritative for the
    execution ledger and ops log when a provider is available; the JSON
    files remain the fallback store and a debugging export. Nothing in this
    module may throw for the mere absence of SQLite; only explicit query
    helpers throw on real SQL errors.

.NOTES
    Dot-source this file to load the public functions:
        . (Join-Path $persistenceModuleRoot 'Persistence.Store.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants and module state
# ---------------------------------------------------------------------------

$script:AppDbSchemaVersion = 2
$script:AppDbRelPath       = 'output\app.db'

# Current persistence-boundary state. Enabled only after a successful
# Initialize-AppDatabase; consumers (e.g. the agent-run event mirror) no-op
# while disabled so JSON-only environments behave exactly as before.
$script:AppDbState = @{
    enabled       = $false
    databasePath  = ''
    provider      = 'none'
    providerDetail = ''
    schemaVersion = $script:AppDbSchemaVersion
    initializedAt = $null
}

$script:SqliteCapabilityCache = $null

# ---------------------------------------------------------------------------
# Native bridge (compiled once per process)
# ---------------------------------------------------------------------------

function Get-SqliteBridgeSource {
    return @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace RepoMgmt.Persistence
{
    public static class SqliteBridge
    {
        private const int SQLITE_OK = 0;
        private const int SQLITE_ROW = 100;
        private const int SQLITE_DONE = 101;
        private const int OPEN_FLAGS = 0x2 | 0x4 | 0x10000; // READWRITE | CREATE | FULLMUTEX
        private static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr LibVersionFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int OpenV2Fn(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CloseV2Fn(IntPtr db);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ExecFn(IntPtr db, byte[] sql, IntPtr cb, IntPtr arg, out IntPtr errMsg);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void FreeFn(IntPtr p);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int PrepareV2Fn(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, out IntPtr tail);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int StepFn(IntPtr stmt);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int FinalizeFn(IntPtr stmt);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr ErrMsgFn(IntPtr db);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BusyTimeoutFn(IntPtr db, int ms);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BindParamIndexFn(IntPtr stmt, byte[] name);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BindTextFn(IntPtr stmt, int index, byte[] value, int nBytes, IntPtr destructor);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BindInt64Fn(IntPtr stmt, int index, long value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BindDoubleFn(IntPtr stmt, int index, double value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int BindNullFn(IntPtr stmt, int index);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ColumnCountFn(IntPtr stmt);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr ColumnNameFn(IntPtr stmt, int index);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ColumnTypeFn(IntPtr stmt, int index);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate long ColumnInt64Fn(IntPtr stmt, int index);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate double ColumnDoubleFn(IntPtr stmt, int index);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr ColumnTextFn(IntPtr stmt, int index);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ChangesFn(IntPtr db);

        private static LibVersionFn _libVersion;
        private static OpenV2Fn _openV2;
        private static CloseV2Fn _closeV2;
        private static ExecFn _exec;
        private static FreeFn _free;
        private static PrepareV2Fn _prepareV2;
        private static StepFn _step;
        private static FinalizeFn _finalize;
        private static ErrMsgFn _errMsg;
        private static BusyTimeoutFn _busyTimeout;
        private static BindParamIndexFn _bindParamIndex;
        private static BindTextFn _bindText;
        private static BindInt64Fn _bindInt64;
        private static BindDoubleFn _bindDouble;
        private static BindNullFn _bindNull;
        private static ColumnCountFn _columnCount;
        private static ColumnNameFn _columnName;
        private static ColumnTypeFn _columnType;
        private static ColumnInt64Fn _columnInt64;
        private static ColumnDoubleFn _columnDouble;
        private static ColumnTextFn _columnText;
        private static ChangesFn _changes;

        private static readonly object InitLock = new object();
        public static bool Initialized { get; private set; }
        public static string LibraryName { get; private set; }
        public static string Version { get; private set; }

        public static bool TryInitialize(out string detail)
        {
            lock (InitLock)
            {
                if (Initialized) { detail = LibraryName + " " + Version; return true; }
                // Windows ships winsqlite3.dll with the OS; Linux/WSL and
                // macOS ship libsqlite3. NativeLibrary.TryLoad simply fails
                // for names that do not fit the current platform.
                string[] candidates = new string[] {
                    "winsqlite3.dll", "sqlite3.dll", "e_sqlite3.dll",
                    "libsqlite3.so.0", "libsqlite3.so", "libsqlite3.dylib", "sqlite3"
                };
                StringBuilder errors = new StringBuilder();
                foreach (string name in candidates)
                {
                    IntPtr handle;
                    if (!NativeLibrary.TryLoad(name, out handle))
                    {
                        errors.Append(name).Append(": not loadable; ");
                        continue;
                    }
                    try
                    {
                        BindExports(handle);
                        LibraryName = name;
                        Version = PtrToString(_libVersion());
                        Initialized = true;
                        detail = name + " " + Version;
                        return true;
                    }
                    catch (Exception ex)
                    {
                        errors.Append(name).Append(": ").Append(ex.Message).Append("; ");
                    }
                }
                detail = errors.ToString();
                return false;
            }
        }

        private static T BindExport<T>(IntPtr handle, string export) where T : class
        {
            IntPtr addr = NativeLibrary.GetExport(handle, export);
            return Marshal.GetDelegateForFunctionPointer(addr, typeof(T)) as T;
        }

        private static void BindExports(IntPtr h)
        {
            _libVersion = BindExport<LibVersionFn>(h, "sqlite3_libversion");
            _openV2 = BindExport<OpenV2Fn>(h, "sqlite3_open_v2");
            _closeV2 = BindExport<CloseV2Fn>(h, "sqlite3_close_v2");
            _exec = BindExport<ExecFn>(h, "sqlite3_exec");
            _free = BindExport<FreeFn>(h, "sqlite3_free");
            _prepareV2 = BindExport<PrepareV2Fn>(h, "sqlite3_prepare_v2");
            _step = BindExport<StepFn>(h, "sqlite3_step");
            _finalize = BindExport<FinalizeFn>(h, "sqlite3_finalize");
            _errMsg = BindExport<ErrMsgFn>(h, "sqlite3_errmsg");
            _busyTimeout = BindExport<BusyTimeoutFn>(h, "sqlite3_busy_timeout");
            _bindParamIndex = BindExport<BindParamIndexFn>(h, "sqlite3_bind_parameter_index");
            _bindText = BindExport<BindTextFn>(h, "sqlite3_bind_text");
            _bindInt64 = BindExport<BindInt64Fn>(h, "sqlite3_bind_int64");
            _bindDouble = BindExport<BindDoubleFn>(h, "sqlite3_bind_double");
            _bindNull = BindExport<BindNullFn>(h, "sqlite3_bind_null");
            _columnCount = BindExport<ColumnCountFn>(h, "sqlite3_column_count");
            _columnName = BindExport<ColumnNameFn>(h, "sqlite3_column_name");
            _columnType = BindExport<ColumnTypeFn>(h, "sqlite3_column_type");
            _columnInt64 = BindExport<ColumnInt64Fn>(h, "sqlite3_column_int64");
            _columnDouble = BindExport<ColumnDoubleFn>(h, "sqlite3_column_double");
            _columnText = BindExport<ColumnTextFn>(h, "sqlite3_column_text");
            _changes = BindExport<ChangesFn>(h, "sqlite3_changes");
        }

        private static string PtrToString(IntPtr p)
        {
            if (p == IntPtr.Zero) { return null; }
            return Marshal.PtrToStringUTF8(p);
        }

        private static byte[] Utf8Z(string s)
        {
            byte[] raw = Encoding.UTF8.GetBytes(s ?? string.Empty);
            byte[] z = new byte[raw.Length + 1];
            Buffer.BlockCopy(raw, 0, z, 0, raw.Length);
            return z;
        }

        private static void EnsureInit()
        {
            if (!Initialized)
            {
                string detail;
                if (!TryInitialize(out detail))
                {
                    throw new InvalidOperationException("No SQLite native library available: " + detail);
                }
            }
        }

        private static IntPtr OpenDb(string path)
        {
            EnsureInit();
            IntPtr db;
            int rc = _openV2(Utf8Z(path), out db, OPEN_FLAGS, IntPtr.Zero);
            if (rc != SQLITE_OK)
            {
                string msg = db != IntPtr.Zero ? PtrToString(_errMsg(db)) : ("rc=" + rc);
                if (db != IntPtr.Zero) { _closeV2(db); }
                throw new InvalidOperationException("sqlite3_open_v2 failed for '" + path + "': " + msg);
            }
            // Waits instead of failing when another writer briefly holds the
            // file lock (host request loop vs. background scan overlap).
            _busyTimeout(db, 5000);
            return db;
        }

        public static void Execute(string dbPath, string sql)
        {
            IntPtr db = OpenDb(dbPath);
            try
            {
                IntPtr errMsg;
                int rc = _exec(db, Utf8Z(sql), IntPtr.Zero, IntPtr.Zero, out errMsg);
                if (rc != SQLITE_OK)
                {
                    string msg = errMsg != IntPtr.Zero ? PtrToString(errMsg) : ("rc=" + rc);
                    if (errMsg != IntPtr.Zero) { _free(errMsg); }
                    throw new InvalidOperationException("sqlite3_exec failed: " + msg);
                }
            }
            finally { _closeV2(db); }
        }

        private static long RunNonQuery(IntPtr db, string sql, string[] names, object[] values)
        {
            IntPtr stmt = PrepareAndBind(db, sql, names, values);
            try
            {
                int rc = _step(stmt);
                if (rc != SQLITE_DONE && rc != SQLITE_ROW)
                {
                    throw new InvalidOperationException("sqlite3_step failed: " + PtrToString(_errMsg(db)));
                }
            }
            finally { _finalize(stmt); }
            return _changes(db);
        }

        private static List<Dictionary<string, object>> RunQuery(IntPtr db, string sql, string[] names, object[] values)
        {
            List<Dictionary<string, object>> rows = new List<Dictionary<string, object>>();
            IntPtr stmt = PrepareAndBind(db, sql, names, values);
            try
            {
                int colCount = -1;
                while (true)
                {
                    int rc = _step(stmt);
                    if (rc == SQLITE_DONE) { break; }
                    if (rc != SQLITE_ROW)
                    {
                        throw new InvalidOperationException("sqlite3_step failed: " + PtrToString(_errMsg(db)));
                    }
                    if (colCount < 0) { colCount = _columnCount(stmt); }
                    Dictionary<string, object> row = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                    for (int i = 0; i < colCount; i++)
                    {
                        string name = PtrToString(_columnName(stmt, i));
                        int type = _columnType(stmt, i);
                        object value;
                        switch (type)
                        {
                            case 1: value = _columnInt64(stmt, i); break;
                            case 2: value = _columnDouble(stmt, i); break;
                            case 5: value = null; break;
                            default: value = PtrToString(_columnText(stmt, i)); break;
                        }
                        row[name] = value;
                    }
                    rows.Add(row);
                }
            }
            finally { _finalize(stmt); }
            return rows;
        }

        public static long ExecuteNonQuery(string dbPath, string sql, string[] names, object[] values)
        {
            IntPtr db = OpenDb(dbPath);
            try { return RunNonQuery(db, sql, names, values); }
            finally { _closeV2(db); }
        }

        public static List<Dictionary<string, object>> Query(string dbPath, string sql, string[] names, object[] values)
        {
            IntPtr db = OpenDb(dbPath);
            try { return RunQuery(db, sql, names, values); }
            finally { _closeV2(db); }
        }

        // Sessions hold one connection open across statements so callers can
        // wrap multi-statement work (e.g. replace-ledger writes) in a single
        // BEGIN IMMEDIATE transaction.
        private static readonly Dictionary<long, IntPtr> Sessions = new Dictionary<long, IntPtr>();
        private static long _nextSessionId = 0;

        public static long OpenSession(string dbPath)
        {
            IntPtr db = OpenDb(dbPath);
            lock (Sessions)
            {
                _nextSessionId++;
                Sessions[_nextSessionId] = db;
                return _nextSessionId;
            }
        }

        public static void CloseSession(long sessionId)
        {
            IntPtr db = IntPtr.Zero;
            lock (Sessions)
            {
                if (Sessions.TryGetValue(sessionId, out db)) { Sessions.Remove(sessionId); }
            }
            if (db != IntPtr.Zero) { _closeV2(db); }
        }

        private static IntPtr GetSessionDb(long sessionId)
        {
            lock (Sessions)
            {
                IntPtr db;
                if (!Sessions.TryGetValue(sessionId, out db))
                {
                    throw new InvalidOperationException("Unknown SQLite session: " + sessionId);
                }
                return db;
            }
        }

        public static long SessionNonQuery(long sessionId, string sql, string[] names, object[] values)
        {
            return RunNonQuery(GetSessionDb(sessionId), sql, names, values);
        }

        public static List<Dictionary<string, object>> SessionQuery(long sessionId, string sql, string[] names, object[] values)
        {
            return RunQuery(GetSessionDb(sessionId), sql, names, values);
        }

        private static IntPtr PrepareAndBind(IntPtr db, string sql, string[] names, object[] values)
        {
            IntPtr stmt;
            IntPtr tail;
            byte[] sqlBytes = Utf8Z(sql);
            int rc = _prepareV2(db, sqlBytes, sqlBytes.Length, out stmt, out tail);
            if (rc != SQLITE_OK)
            {
                throw new InvalidOperationException("sqlite3_prepare_v2 failed: " + PtrToString(_errMsg(db)));
            }
            if (names != null)
            {
                for (int i = 0; i < names.Length; i++)
                {
                    string name = names[i] != null && names[i].StartsWith("@") ? names[i] : "@" + names[i];
                    int idx = _bindParamIndex(stmt, Utf8Z(name));
                    if (idx <= 0)
                    {
                        _finalize(stmt);
                        throw new InvalidOperationException("Unknown SQL parameter: " + name);
                    }
                    object v = values[i];
                    int brc;
                    if (v == null || v is DBNull)
                    {
                        brc = _bindNull(stmt, idx);
                    }
                    else if (v is bool)
                    {
                        brc = _bindInt64(stmt, idx, ((bool)v) ? 1L : 0L);
                    }
                    else if (v is sbyte || v is byte || v is short || v is ushort || v is int || v is uint || v is long)
                    {
                        brc = _bindInt64(stmt, idx, Convert.ToInt64(v));
                    }
                    else if (v is float || v is double || v is decimal)
                    {
                        brc = _bindDouble(stmt, idx, Convert.ToDouble(v));
                    }
                    else if (v is DateTime)
                    {
                        byte[] b = Encoding.UTF8.GetBytes(((DateTime)v).ToUniversalTime().ToString("o"));
                        brc = _bindText(stmt, idx, b, b.Length, SQLITE_TRANSIENT);
                    }
                    else
                    {
                        byte[] b = Encoding.UTF8.GetBytes(v.ToString());
                        brc = _bindText(stmt, idx, b, b.Length, SQLITE_TRANSIENT);
                    }
                    if (brc != SQLITE_OK)
                    {
                        _finalize(stmt);
                        throw new InvalidOperationException("Parameter bind failed for " + name + ": " + PtrToString(_errMsg(db)));
                    }
                }
            }
            return stmt;
        }
    }
}
'@
}

function Initialize-SqliteBridgeType {
    <#
    .SYNOPSIS
        Compiles the native bridge type once per process. Returns a result
        object instead of throwing so capability detection can report why
        the bridge is unavailable.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if ('RepoMgmt.Persistence.SqliteBridge' -as [type]) {
        return [pscustomobject]@{ success = $true; error = '' }
    }
    try {
        Add-Type -TypeDefinition (Get-SqliteBridgeSource) -ErrorAction Stop
        return [pscustomobject]@{ success = $true; error = '' }
    } catch {
        return [pscustomobject]@{ success = $false; error = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------------------
# Capability detection
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Detects whether a SQLite provider is available on this machine.
.DESCRIPTION
    Never throws. Reports the native-library provider used by the bridge
    (winsqlite3.dll on Windows, libsqlite3 on WSL/Linux/macOS) plus an
    informational sqlite3 CLI path when one is on PATH. The result is
    cached per process; use -Refresh to re-probe.
#>
function Get-SqliteCapability {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][switch]$Refresh
    )

    if ($null -ne $script:SqliteCapabilityCache -and -not $Refresh) {
        return $script:SqliteCapabilityCache
    }

    $cap = [ordered]@{
        available      = $false
        provider       = 'none'
        providerDetail = ''
        sqliteVersion  = ''
        cliPath        = ''
        reasons        = @()
    }

    $bridge = Initialize-SqliteBridgeType
    if (-not $bridge.success) {
        $cap.reasons = @($cap.reasons) + @("bridge-compile-failed: $($bridge.error)")
    } else {
        $detail = ''
        $ok = [RepoMgmt.Persistence.SqliteBridge]::TryInitialize([ref]$detail)
        if ($ok) {
            $cap.available      = $true
            $cap.provider       = 'native-pinvoke'
            $cap.providerDetail = [string][RepoMgmt.Persistence.SqliteBridge]::LibraryName
            $cap.sqliteVersion  = [string][RepoMgmt.Persistence.SqliteBridge]::Version
        } else {
            $cap.reasons = @($cap.reasons) + @("no-native-sqlite-library: $detail")
        }
    }

    # Informational only in Phase 1 — the CLI is not used as an execution path.
    $cli = Get-Command -Name 'sqlite3' -ErrorAction SilentlyContinue
    if ($null -ne $cli) {
        $cap.cliPath = [string]$cli.Source
    }

    $script:SqliteCapabilityCache = [pscustomobject]$cap
    return $script:SqliteCapabilityCache
}

# ---------------------------------------------------------------------------
# Database bootstrap
# ---------------------------------------------------------------------------

function Get-AppDatabasePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot
    )
    return Join-Path $WorkspaceRoot $script:AppDbRelPath
}

function Get-AppDatabaseSchemaSql {
    # Schema v1 — one table per persisted store named in the Release 2.1
    # milestone: execution (ledger + history), maturity, ops-log,
    # portfolio-index, repo-signal, differential-scan, merge-readiness,
    # agent-run, and agent-run-event. Timestamps are ISO-8601 UTC TEXT.
    # *_json columns hold full-fidelity payloads so later phases can widen
    # typed columns without losing data.
    return @'
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     INTEGER PRIMARY KEY,
  description TEXT NOT NULL,
  applied_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS execution_ledger (
  repo_name            TEXT PRIMARY KEY,
  repo_path            TEXT,
  execution_state      TEXT NOT NULL,
  roadmap_path         TEXT,
  current_task_text    TEXT,
  current_task_section TEXT,
  current_run_id       TEXT,
  lane_slot            INTEGER,
  priority_score       INTEGER NOT NULL DEFAULT 0,
  assigned_at          TEXT,
  completed_at         TEXT,
  last_outcome         TEXT,
  retry_count          INTEGER NOT NULL DEFAULT 0,
  error_message        TEXT,
  updated_at           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS execution_history (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  repo_name     TEXT NOT NULL,
  event         TEXT NOT NULL,
  run_id        TEXT,
  task_text     TEXT,
  outcome       TEXT,
  error_message TEXT,
  timestamp     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_execution_history_repo_time ON execution_history(repo_name, timestamp);

CREATE TABLE IF NOT EXISTS maturity_history (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  repo_name      TEXT NOT NULL,
  roadmap_path   TEXT,
  maturity_level TEXT,
  maturity_score REAL,
  pending_count  INTEGER,
  captured_at    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_maturity_history_repo_time ON maturity_history(repo_name, captured_at);

CREATE TABLE IF NOT EXISTS ops_log (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  level     TEXT NOT NULL,
  source    TEXT,
  message   TEXT,
  data_json TEXT
);
CREATE INDEX IF NOT EXISTS idx_ops_log_time_level ON ops_log(timestamp, level);

CREATE TABLE IF NOT EXISTS portfolio_index_history (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  scan_id         TEXT NOT NULL,
  captured_at     TEXT NOT NULL,
  repo_name       TEXT NOT NULL,
  repo_path       TEXT,
  owner_repo      TEXT,
  lifecycle_state TEXT,
  source_coverage TEXT,
  record_json     TEXT
);
CREATE INDEX IF NOT EXISTS idx_portfolio_index_history_scan ON portfolio_index_history(scan_id);
CREATE INDEX IF NOT EXISTS idx_portfolio_index_history_repo_time ON portfolio_index_history(repo_name, captured_at);

CREATE TABLE IF NOT EXISTS repo_signals (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  repo_name          TEXT NOT NULL,
  captured_at        TEXT NOT NULL,
  readme_score       REAL,
  roadmap_score      REAL,
  doc_health_score   REAL,
  dirty_file_count   INTEGER,
  open_pr_count      INTEGER,
  actions_status     TEXT,
  actions_conclusion TEXT,
  pages_status       TEXT,
  signal_json        TEXT
);
CREATE INDEX IF NOT EXISTS idx_repo_signals_repo_time ON repo_signals(repo_name, captured_at);

CREATE TABLE IF NOT EXISTS differential_scans (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  scan_id       TEXT NOT NULL,
  scan_mode     TEXT NOT NULL,
  started_at    TEXT,
  completed_at  TEXT,
  repos_total   INTEGER,
  repos_changed INTEGER,
  changed_json  TEXT
);
CREATE INDEX IF NOT EXISTS idx_differential_scans_scan ON differential_scans(scan_id);

CREATE TABLE IF NOT EXISTS merge_readiness_snapshots (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  repo_id       TEXT NOT NULL,
  repo_name     TEXT,
  run_id        TEXT,
  pr_number     INTEGER,
  ready         INTEGER NOT NULL DEFAULT 0,
  captured_at   TEXT NOT NULL,
  blockers_json TEXT,
  evidence_json TEXT
);
CREATE INDEX IF NOT EXISTS idx_merge_readiness_repo_time ON merge_readiness_snapshots(repo_id, captured_at);

CREATE TABLE IF NOT EXISTS agent_runs (
  run_id                  TEXT PRIMARY KEY,
  repo_name               TEXT,
  status                  TEXT,
  dispatched_at           TEXT,
  started_at              TEXT,
  completed_at            TEXT,
  time_to_deliver_seconds REAL,
  prompt_count            INTEGER,
  retry_count             INTEGER,
  tokens_reported         INTEGER,
  direct_cost_usd         REAL,
  work_units_estimated    REAL,
  work_units_actual       REAL,
  release_name            TEXT,
  phase_name              TEXT,
  section_name            TEXT,
  record_json             TEXT,
  updated_at              TEXT
);
CREATE INDEX IF NOT EXISTS idx_agent_runs_repo ON agent_runs(repo_name);

CREATE TABLE IF NOT EXISTS agent_run_events (
  event_id       TEXT PRIMARY KEY,
  schema_version TEXT,
  run_id         TEXT,
  repo_name      TEXT,
  timestamp      TEXT NOT NULL,
  event_type     TEXT NOT NULL,
  actor          TEXT,
  summary        TEXT,
  data_json      TEXT
);
CREATE INDEX IF NOT EXISTS idx_agent_run_events_run_time ON agent_run_events(run_id, timestamp);

CREATE TABLE IF NOT EXISTS quota_burn_snapshots (
  snapshot_id          INTEGER PRIMARY KEY AUTOINCREMENT,
  repo_name            TEXT NOT NULL,
  budget_period        TEXT,
  evaluated_at         TEXT NOT NULL,
  estimated_work_units REAL,
  units_consumed       REAL,
  remaining_before     REAL,
  remaining_after      REAL,
  allowed              INTEGER NOT NULL DEFAULT 0,
  blocked_code         TEXT,
  planned_release      TEXT,
  planned_phase        TEXT,
  snapshot_json        TEXT
);
CREATE INDEX IF NOT EXISTS idx_quota_burn_repo_time ON quota_burn_snapshots(repo_name, evaluated_at);

CREATE TABLE IF NOT EXISTS repo_curation (
    repo_id         TEXT PRIMARY KEY,
    curation_state  TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    reason          TEXT
);
CREATE INDEX IF NOT EXISTS idx_repo_curation_state ON repo_curation(curation_state);
'@
}

<#
.SYNOPSIS
    Creates (or upgrades) output/app.db and applies the schema-v1 tables.
.DESCRIPTION
    Idempotent: every DDL statement is IF NOT EXISTS and the migration row
    is inserted once. On success the module-level persistence state is
    enabled so mirror writers (Write-AppDbAgentRunEvent) start persisting.
    Never throws for a missing SQLite provider — returns success=$false
    with the reason instead, because the JSON stores remain authoritative
    during the Release 2.1 rollout.
#>
function Initialize-AppDatabase {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][string]$DatabasePath = ''
    )

    $result = [ordered]@{
        success       = $false
        databasePath  = ''
        provider      = 'none'
        providerDetail = ''
        sqliteVersion = ''
        schemaVersion = $script:AppDbSchemaVersion
        tables        = @()
        error         = ''
    }

    $cap = Get-SqliteCapability
    $result.provider       = [string]$cap.provider
    $result.providerDetail = [string]$cap.providerDetail
    $result.sqliteVersion  = [string]$cap.sqliteVersion
    if (-not $cap.available) {
        $result.error = 'SQLite unavailable: ' + (@($cap.reasons) -join '; ')
        return [pscustomobject]$result
    }

    $dbPath = if (-not [string]::IsNullOrWhiteSpace($DatabasePath)) { $DatabasePath } else { Get-AppDatabasePath -WorkspaceRoot $WorkspaceRoot }

    try {
        $dbDir = Split-Path -Path $dbPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($dbDir) -and -not (Test-Path -LiteralPath $dbDir)) {
            $null = New-Item -ItemType Directory -Path $dbDir -Force
        }

        # WAL keeps readers unblocked while the host or a background scan writes.
        [RepoMgmt.Persistence.SqliteBridge]::Execute($dbPath, 'PRAGMA journal_mode=WAL;')
        [RepoMgmt.Persistence.SqliteBridge]::Execute($dbPath, (Get-AppDatabaseSchemaSql))

        $existing = [RepoMgmt.Persistence.SqliteBridge]::Query(
            $dbPath,
            'SELECT version FROM schema_migrations WHERE version = @version',
            @('@version'), @([object][long]$script:AppDbSchemaVersion))
        if (@($existing).Count -eq 0) {
            $null = [RepoMgmt.Persistence.SqliteBridge]::ExecuteNonQuery(
                $dbPath,
                'INSERT INTO schema_migrations (version, description, applied_at) VALUES (@version, @description, @applied_at)',
                @('@version', '@description', '@applied_at'),
                @([object][long]$script:AppDbSchemaVersion,
                  [object]'Release 2.1 Phase 3 - agent-run metrics and quota-burn snapshots (schema v2)',
                  [object](Get-Date).ToUniversalTime().ToString('o')))
        }

        $tableRows = [RepoMgmt.Persistence.SqliteBridge]::Query(
            $dbPath,
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
            $null, $null)
        $result.tables = @($tableRows | ForEach-Object { [string]$_['name'] })

        $result.databasePath = $dbPath
        $result.success = $true

        $script:AppDbState.enabled        = $true
        $script:AppDbState.databasePath   = $dbPath
        $script:AppDbState.provider       = [string]$cap.provider
        $script:AppDbState.providerDetail = [string]$cap.providerDetail
        $script:AppDbState.initializedAt  = (Get-Date).ToUniversalTime().ToString('o')
    } catch {
        $result.error = $_.Exception.Message
    }

    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Returns the current persistence-boundary state (enabled flag, database
    path, provider). Safe to call before Initialize-AppDatabase.
#>
function Get-AppDatabaseState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    return [pscustomobject]@{
        enabled        = [bool]$script:AppDbState.enabled
        databasePath   = [string]$script:AppDbState.databasePath
        provider       = [string]$script:AppDbState.provider
        providerDetail = [string]$script:AppDbState.providerDetail
        schemaVersion  = [int]$script:AppDbState.schemaVersion
        initializedAt  = $script:AppDbState.initializedAt
    }
}

<#
.SYNOPSIS
    Disables the persistence boundary for this process. Used by tests and
    tooling that point the module at short-lived temp databases so later
    code in the same session falls back to the JSON stores.
#>
function Disable-AppDatabase {
    [CmdletBinding()]
    param()

    $script:AppDbState.enabled        = $false
    $script:AppDbState.databasePath   = ''
    $script:AppDbState.provider       = 'none'
    $script:AppDbState.providerDetail = ''
    $script:AppDbState.initializedAt  = $null
}

# ---------------------------------------------------------------------------
# Query helpers (parameterized SQL only)
# ---------------------------------------------------------------------------

function _AppDbParameterArrays {
    param([hashtable]$Parameters)
    # ::new() (not New-Object): on pwsh 7.6 a New-Object-created List[object]
    # is PSObject-wrapped and @()-enumeration of PSCustomObject elements then
    # fails with 'Argument types do not match'.
    $names = [System.Collections.Generic.List[string]]::new()
    $values = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Parameters) {
        foreach ($key in $Parameters.Keys) {
            $names.Add([string]$key)
            $values.Add($Parameters[$key])
        }
    }
    return @{ names = $names.ToArray(); values = $values.ToArray() }
}

<#
.SYNOPSIS
    Executes a parameterized non-query (INSERT/UPDATE/DELETE) against the
    app database and returns the affected-row count.
#>
function Invoke-AppDbNonQuery {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter()][hashtable]$Parameters
    )

    $p = _AppDbParameterArrays -Parameters $Parameters
    return [long][RepoMgmt.Persistence.SqliteBridge]::ExecuteNonQuery($DatabasePath, $Sql, $p.names, $p.values)
}

<#
.SYNOPSIS
    Executes a parameterized SELECT against the app database and returns
    rows as PSCustomObjects (INTEGER -> long, REAL -> double, NULL -> $null,
    everything else -> string).
#>
function Invoke-AppDbQuery {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter()][hashtable]$Parameters
    )

    $p = _AppDbParameterArrays -Parameters $Parameters
    $rows = [RepoMgmt.Persistence.SqliteBridge]::Query($DatabasePath, $Sql, $p.names, $p.values)
    return _AppDbRowsToObjects -Rows $rows
}

function _AppDbRowsToObjects {
    param([object]$Rows)

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $Rows) {
        $obj = [ordered]@{}
        foreach ($kv in $row.GetEnumerator()) {
            $obj[$kv.Key] = $kv.Value
        }
        $out.Add([pscustomobject]$obj)
    }
    return $out.ToArray()
}

function _AppDbRecordValue {
    # StrictMode-safe property access for records that may be hashtables or
    # PSCustomObjects; returns $null when the member does not exist.
    param([object]$Record, [string]$Name)

    if ($null -eq $Record) { return $null }
    if ($Record -is [System.Collections.IDictionary]) {
        if ($Record.Contains($Name)) { return $Record[$Name] }
        return $null
    }
    if ($Record.PSObject.Properties.Name -contains $Name) { return $Record.$Name }
    return $null
}

function _AppDbFirstRecordValue {
    # Returns the first non-empty value from a list of candidate field names.
    param(
        [object]$Record,
        [string[]]$Names,
        [object]$Default = $null
    )

    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        $value = _AppDbRecordValue -Record $Record -Name $name
        if ($null -eq $value) { continue }
        if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { continue }
        return $value
    }

    return $Default
}

function _AppDbMatchesWorkspace {
    # The persistence boundary is initialized for exactly one workspace per
    # process. Workspace-scoped stores (execution ledger) must refuse to
    # serve a different workspace and let the caller fall back to JSON.
    param([string]$WorkspaceRoot)

    if (-not $script:AppDbState.enabled) { return $false }
    try {
        $expected = [System.IO.Path]::GetFullPath((Get-AppDatabasePath -WorkspaceRoot $WorkspaceRoot))
        $actual   = [System.IO.Path]::GetFullPath([string]$script:AppDbState.databasePath)
        return [string]::Equals($expected, $actual, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

<#
.SYNOPSIS
    Executes a parameterized non-query inside an open session created by
    Invoke-AppDbTransaction.
#>
function Invoke-AppDbSessionNonQuery {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)][long]$Session,
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter()][hashtable]$Parameters
    )

    $p = _AppDbParameterArrays -Parameters $Parameters
    return [long][RepoMgmt.Persistence.SqliteBridge]::SessionNonQuery($Session, $Sql, $p.names, $p.values)
}

<#
.SYNOPSIS
    Executes a parameterized SELECT inside an open session created by
    Invoke-AppDbTransaction.
#>
function Invoke-AppDbSessionQuery {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][long]$Session,
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter()][hashtable]$Parameters
    )

    $p = _AppDbParameterArrays -Parameters $Parameters
    $rows = [RepoMgmt.Persistence.SqliteBridge]::SessionQuery($Session, $Sql, $p.names, $p.values)
    return _AppDbRowsToObjects -Rows $rows
}

<#
.SYNOPSIS
    Runs a script block inside one SQLite transaction (BEGIN IMMEDIATE /
    COMMIT, ROLLBACK on error) over a single connection.
.DESCRIPTION
    The body receives the open session id and must issue its statements via
    Invoke-AppDbSessionNonQuery / Invoke-AppDbSessionQuery. BEGIN IMMEDIATE
    takes the write lock up front so a concurrent writer queues on the
    5-second busy timeout instead of failing mid-transaction.
#>
function Invoke-AppDbTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    $session = [RepoMgmt.Persistence.SqliteBridge]::OpenSession($DatabasePath)
    try {
        $null = [RepoMgmt.Persistence.SqliteBridge]::SessionNonQuery($session, 'BEGIN IMMEDIATE', $null, $null)
        try {
            & $Body $session
            $null = [RepoMgmt.Persistence.SqliteBridge]::SessionNonQuery($session, 'COMMIT', $null, $null)
        } catch {
            try { $null = [RepoMgmt.Persistence.SqliteBridge]::SessionNonQuery($session, 'ROLLBACK', $null, $null) } catch { }
            throw
        }
    } finally {
        [RepoMgmt.Persistence.SqliteBridge]::CloseSession($session)
    }
}

# ---------------------------------------------------------------------------
# First migration seam — agent-run event mirror
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Mirrors one agent-run lifecycle event into the agent_run_events table.
.DESCRIPTION
    The dual-write seam for Release 2.1 Phase 1: Write-AgentRunEvent calls
    this after its authoritative JSONL append. No-ops (success=$false with
    reason) while the persistence boundary is disabled, and never throws —
    telemetry must not break the run it describes. INSERT OR IGNORE keyed
    on event_id keeps replays idempotent.
#>
function Write-AppDbAgentRunEvent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][object]$EventRecord
    )

    $out = @{ success = $false; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        $get = {
            param([string]$Name)
            if ($EventRecord -is [System.Collections.IDictionary]) {
                if ($EventRecord.Contains($Name)) { return $EventRecord[$Name] }
                return $null
            }
            if ($EventRecord.PSObject.Properties.Name -contains $Name) { return $EventRecord.$Name }
            return $null
        }

        $data = & $get 'data'
        $dataJson = if ($null -eq $data) { $null } else { ConvertTo-Json -InputObject $data -Compress -Depth 6 }

        $null = Invoke-AppDbNonQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
INSERT OR IGNORE INTO agent_run_events
  (event_id, schema_version, run_id, repo_name, timestamp, event_type, actor, summary, data_json)
VALUES
  (@event_id, @schema_version, @run_id, @repo_name, @timestamp, @event_type, @actor, @summary, @data_json)
'@ -Parameters @{
            event_id       = [string](& $get 'eventId')
            schema_version = [string](& $get 'schemaVersion')
            run_id         = [string](& $get 'runId')
            repo_name      = [string](& $get 'repoName')
            timestamp      = [string](& $get 'timestamp')
            event_type     = [string](& $get 'eventType')
            actor          = [string](& $get 'actor')
            summary        = [string](& $get 'summary')
            data_json      = $dataJson
        }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

# ---------------------------------------------------------------------------
# Phase 2 migration — execution ledger store
# ---------------------------------------------------------------------------

function _AppDbLedgerEntryFromRow {
    param([object]$Row)

    $laneSlot = _AppDbRecordValue -Record $Row -Name 'lane_slot'
    return [pscustomobject]@{
        repoName           = [string](_AppDbRecordValue -Record $Row -Name 'repo_name')
        repoPath           = _AppDbRecordValue -Record $Row -Name 'repo_path'
        executionState     = [string](_AppDbRecordValue -Record $Row -Name 'execution_state')
        roadmapPath        = _AppDbRecordValue -Record $Row -Name 'roadmap_path'
        currentTaskText    = _AppDbRecordValue -Record $Row -Name 'current_task_text'
        currentTaskSection = _AppDbRecordValue -Record $Row -Name 'current_task_section'
        currentRunId       = _AppDbRecordValue -Record $Row -Name 'current_run_id'
        laneSlot           = if ($null -ne $laneSlot) { [int]$laneSlot } else { $null }
        priorityScore      = [int](_AppDbRecordValue -Record $Row -Name 'priority_score')
        assignedAt         = _AppDbRecordValue -Record $Row -Name 'assigned_at'
        completedAt        = _AppDbRecordValue -Record $Row -Name 'completed_at'
        lastOutcome        = _AppDbRecordValue -Record $Row -Name 'last_outcome'
        retryCount         = [int](_AppDbRecordValue -Record $Row -Name 'retry_count')
        errorMessage       = _AppDbRecordValue -Record $Row -Name 'error_message'
        updatedAt          = _AppDbRecordValue -Record $Row -Name 'updated_at'
    }
}

<#
.SYNOPSIS
    Writes the full execution ledger to the app database inside one
    transaction: current entries are replaced, new history records are
    appended (existing history rows are never rewritten).
.DESCRIPTION
    Release 2.1 Phase 2 seam for Execution.Ledger.ps1. Returns
    success=$false with a reason (never throws) when the persistence
    boundary is disabled or initialized for a different workspace, so the
    caller keeps the JSON store authoritative.
#>
function Write-AppDbExecutionLedger {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][object]$Ledger
    )

    $out = @{ success = $false; reason = '' }
    if (-not (_AppDbMatchesWorkspace -WorkspaceRoot $WorkspaceRoot)) {
        $out.reason = 'app-db-not-initialized-for-workspace'
        return [pscustomobject]$out
    }

    try {
        $entriesRaw = _AppDbRecordValue -Record $Ledger -Name 'entries'
        $historyRaw = _AppDbRecordValue -Record $Ledger -Name 'history'
        $entries = if ($null -ne $entriesRaw) { @($entriesRaw) } else { @() }
        $history = if ($null -ne $historyRaw) { @($historyRaw) } else { @() }
        $nowIso = (Get-Date).ToUniversalTime().ToString('o')

        Invoke-AppDbTransaction -DatabasePath ([string]$script:AppDbState.databasePath) -Body {
            param($session)

            $null = Invoke-AppDbSessionNonQuery -Session $session -Sql 'DELETE FROM execution_ledger'
            foreach ($entry in $entries) {
                if ($null -eq $entry) { continue }
                $laneSlot = _AppDbRecordValue -Record $entry -Name 'laneSlot'
                $priority = _AppDbRecordValue -Record $entry -Name 'priorityScore'
                $retries  = _AppDbRecordValue -Record $entry -Name 'retryCount'
                $entryUpdatedAt = _AppDbRecordValue -Record $entry -Name 'updatedAt'
                if ([string]::IsNullOrWhiteSpace([string]$entryUpdatedAt)) { $entryUpdatedAt = $nowIso }
                $null = Invoke-AppDbSessionNonQuery -Session $session -Sql @'
INSERT INTO execution_ledger
  (repo_name, repo_path, execution_state, roadmap_path, current_task_text, current_task_section,
   current_run_id, lane_slot, priority_score, assigned_at, completed_at, last_outcome,
   retry_count, error_message, updated_at)
VALUES
  (@repo_name, @repo_path, @execution_state, @roadmap_path, @current_task_text, @current_task_section,
   @current_run_id, @lane_slot, @priority_score, @assigned_at, @completed_at, @last_outcome,
   @retry_count, @error_message, @updated_at)
'@ -Parameters @{
                    repo_name            = [string](_AppDbRecordValue -Record $entry -Name 'repoName')
                    repo_path            = _AppDbRecordValue -Record $entry -Name 'repoPath'
                    execution_state      = [string](_AppDbRecordValue -Record $entry -Name 'executionState')
                    roadmap_path         = _AppDbRecordValue -Record $entry -Name 'roadmapPath'
                    current_task_text    = _AppDbRecordValue -Record $entry -Name 'currentTaskText'
                    current_task_section = _AppDbRecordValue -Record $entry -Name 'currentTaskSection'
                    current_run_id       = _AppDbRecordValue -Record $entry -Name 'currentRunId'
                    lane_slot            = if ($null -ne $laneSlot) { [long]$laneSlot } else { $null }
                    priority_score       = if ($null -ne $priority) { [long]$priority } else { 0L }
                    assigned_at          = _AppDbRecordValue -Record $entry -Name 'assignedAt'
                    completed_at         = _AppDbRecordValue -Record $entry -Name 'completedAt'
                    last_outcome         = _AppDbRecordValue -Record $entry -Name 'lastOutcome'
                    retry_count          = if ($null -ne $retries) { [long]$retries } else { 0L }
                    error_message        = _AppDbRecordValue -Record $entry -Name 'errorMessage'
                    updated_at           = [string]$entryUpdatedAt
                }
            }

            # History is append-only in the database. The in-memory ledger
            # carries the full history (reads hydrate it from these rows), so
            # anything beyond the current row count is new.
            $existingRows = Invoke-AppDbSessionQuery -Session $session -Sql 'SELECT COUNT(*) AS n FROM execution_history'
            $existingCount = [long]$existingRows[0].n
            if ($history.Count -gt $existingCount) {
                for ($i = $existingCount; $i -lt $history.Count; $i++) {
                    $record = $history[$i]
                    if ($null -eq $record) { continue }
                    $recordTs = _AppDbRecordValue -Record $record -Name 'timestamp'
                    if ([string]::IsNullOrWhiteSpace([string]$recordTs)) { $recordTs = $nowIso }
                    $null = Invoke-AppDbSessionNonQuery -Session $session -Sql @'
INSERT INTO execution_history (repo_name, event, run_id, task_text, outcome, error_message, timestamp)
VALUES (@repo_name, @event, @run_id, @task_text, @outcome, @error_message, @timestamp)
'@ -Parameters @{
                        repo_name     = [string](_AppDbRecordValue -Record $record -Name 'repoName')
                        event         = [string](_AppDbRecordValue -Record $record -Name 'event')
                        run_id        = _AppDbRecordValue -Record $record -Name 'runId'
                        task_text     = _AppDbRecordValue -Record $record -Name 'taskText'
                        outcome       = _AppDbRecordValue -Record $record -Name 'outcome'
                        error_message = _AppDbRecordValue -Record $record -Name 'errorMessage'
                        timestamp     = [string]$recordTs
                    }
                }
            }
        }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Reads the execution ledger from the app database. Returns $null when the
    persistence boundary is disabled or initialized for a different
    workspace, so Execution.Ledger.ps1 falls back to its JSON store.
.DESCRIPTION
    Release 2.1 Phase 2: the first read against empty ledger tables seeds
    them from the legacy execution-ledger.json (one-time migration). After
    that SQLite is authoritative and the JSON file is a debugging export.
    If the seed itself fails, $null is returned so no legacy data is lost.
#>
function Read-AppDbExecutionLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][string]$LedgerJsonPath = ''
    )

    if (-not (_AppDbMatchesWorkspace -WorkspaceRoot $WorkspaceRoot)) { return $null }
    $dbPath = [string]$script:AppDbState.databasePath

    $entryCount   = [long](Invoke-AppDbQuery -DatabasePath $dbPath -Sql 'SELECT COUNT(*) AS n FROM execution_ledger')[0].n
    $historyCount = [long](Invoke-AppDbQuery -DatabasePath $dbPath -Sql 'SELECT COUNT(*) AS n FROM execution_history')[0].n

    if ($entryCount -eq 0 -and $historyCount -eq 0 -and
        -not [string]::IsNullOrWhiteSpace($LedgerJsonPath) -and
        (Test-Path -LiteralPath $LedgerJsonPath)) {
        $legacy = $null
        try {
            $legacy = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $LedgerJsonPath -Raw -Encoding UTF8)
        } catch {
            Write-Warning "Persistence.Store: legacy ledger at '$LedgerJsonPath' could not be parsed for seeding: $_"
        }
        if ($null -ne $legacy) {
            $legacyEntries = _AppDbRecordValue -Record $legacy -Name 'entries'
            $legacyHistory = _AppDbRecordValue -Record $legacy -Name 'history'
            $seedLedger = @{
                entries = if ($null -ne $legacyEntries) { @($legacyEntries) } else { @() }
                history = if ($null -ne $legacyHistory) { @($legacyHistory) } else { @() }
            }
            if (@($seedLedger.entries).Count -gt 0 -or @($seedLedger.history).Count -gt 0) {
                $seed = Write-AppDbExecutionLedger -WorkspaceRoot $WorkspaceRoot -Ledger $seedLedger
                if (-not $seed.success) { return $null }
            }
        }
    }

    $entryRows = @(Invoke-AppDbQuery -DatabasePath $dbPath -Sql 'SELECT * FROM execution_ledger ORDER BY rowid')
    $historyRows = @(Invoke-AppDbQuery -DatabasePath $dbPath -Sql 'SELECT * FROM execution_history ORDER BY id')

    $entries = [System.Collections.Generic.List[object]]::new()
    $latest = ''
    foreach ($row in $entryRows) {
        $entries.Add((_AppDbLedgerEntryFromRow -Row $row))
        $rowUpdated = [string](_AppDbRecordValue -Record $row -Name 'updated_at')
        if ([string]::CompareOrdinal($rowUpdated, $latest) -gt 0) { $latest = $rowUpdated }
    }

    $history = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $historyRows) {
        $history.Add([pscustomobject]@{
            repoName     = [string](_AppDbRecordValue -Record $row -Name 'repo_name')
            event        = [string](_AppDbRecordValue -Record $row -Name 'event')
            runId        = _AppDbRecordValue -Record $row -Name 'run_id'
            taskText     = _AppDbRecordValue -Record $row -Name 'task_text'
            outcome      = _AppDbRecordValue -Record $row -Name 'outcome'
            errorMessage = _AppDbRecordValue -Record $row -Name 'error_message'
            timestamp    = _AppDbRecordValue -Record $row -Name 'timestamp'
        })
        $rowTs = [string](_AppDbRecordValue -Record $row -Name 'timestamp')
        if ([string]::CompareOrdinal($rowTs, $latest) -gt 0) { $latest = $rowTs }
    }

    if ([string]::IsNullOrWhiteSpace($latest)) { $latest = (Get-Date).ToUniversalTime().ToString('o') }

    return @{
        schemaVersion = '1.0'
        updatedAt     = $latest
        entries       = $entries.ToArray()
        history       = $history.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Phase 2 migration — operations log store
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Writes one operations-log entry into the ops_log table. No-ops with a
    reason while the persistence boundary is disabled and never throws —
    logging must not break the operation it describes.
#>
function Write-AppDbOpsLogEntry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][string]$Timestamp = '',
        [Parameter(Mandatory = $true)][string]$Level,
        [Parameter()][string]$Source = '',
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message,
        [Parameter()][object]$Data = $null
    )

    $out = @{ success = $false; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        $ts = if ([string]::IsNullOrWhiteSpace($Timestamp)) { (Get-Date).ToUniversalTime().ToString('o') } else { $Timestamp }
        $dataJson = if ($null -eq $Data) { $null } else { ConvertTo-Json -InputObject $Data -Compress -Depth 6 }
        $null = Invoke-AppDbNonQuery -DatabasePath ([string]$script:AppDbState.databasePath) `
            -Sql 'INSERT INTO ops_log (timestamp, level, source, message, data_json) VALUES (@timestamp, @level, @source, @message, @data_json)' `
            -Parameters @{
                timestamp = $ts
                level     = $Level.ToUpperInvariant()
                source    = $Source
                message   = $Message
                data_json = $dataJson
            }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Queries the ops_log table by time range, level, and keyword without
    reading the whole log. Returns available=$false when the persistence
    boundary is disabled so the caller can fall back to the JSONL tail.
.DESCRIPTION
    Filters combine with AND: Since keeps entries strictly newer than the
    ISO-8601 UTC timestamp, Level is an exact (case-insensitive) match, and
    Contains is a substring match on the message. The most recent MaxLines
    matching entries are returned in ascending id order.
#>
function Get-AppDbOpsLogEntries {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][string]$Since = '',
        [Parameter()][string]$Level = '',
        [Parameter()][string]$Contains = '',
        [Parameter()][int]$MaxLines = 100
    )

    if (-not $script:AppDbState.enabled) {
        return [pscustomobject]@{ available = $false; entries = @() }
    }

    if ($MaxLines -lt 1) { $MaxLines = 1 }
    $needle = [string]$Contains
    $pattern = '%' + ($needle -replace '([\\%_])', '\$1') + '%'

    $rows = @(Invoke-AppDbQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
SELECT timestamp, level, source, message FROM (
  SELECT id, timestamp, level, source, message
  FROM ops_log
  WHERE (@since = '' OR timestamp > @since)
    AND (@level = '' OR level = @level)
    AND (@needle = '' OR message LIKE @pattern ESCAPE '\')
  ORDER BY id DESC
  LIMIT @max
) ORDER BY id ASC
'@ -Parameters @{
        since   = [string]$Since
        level   = ([string]$Level).ToUpperInvariant()
        needle  = $needle
        pattern = $pattern
        max     = [long]$MaxLines
    })

    return [pscustomobject]@{ available = $true; entries = $rows }
}

<#
.SYNOPSIS
    Trims the ops_log table to at most MaxRows, keeping the newest rows.
    Mirrors the JSONL retention behavior; no-ops while disabled and never
    throws.
#>
function Invoke-AppDbOpsLogTrim {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][int]$MaxRows = 5000
    )

    $out = @{ success = $false; removed = 0L; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        if ($MaxRows -lt 1) { $MaxRows = 1 }
        $out.removed = Invoke-AppDbNonQuery -DatabasePath ([string]$script:AppDbState.databasePath) `
            -Sql 'DELETE FROM ops_log WHERE id NOT IN (SELECT id FROM ops_log ORDER BY id DESC LIMIT @max)' `
            -Parameters @{ max = [long]$MaxRows }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Imports operations-log entries from a JSONL file into ops_log, keeping
    only lines newer than the latest timestamp already stored.
.DESCRIPTION
    Gives the SQLite-backed log continuity across host restarts: startup
    lines written to the JSONL before the database initializes (and any
    history from before Phase 2) are pulled in once; already-imported lines
    are skipped by ordinal ISO-timestamp comparison. Supports both the
    api-host shape ({ts,level,msg}) and structured module logs
    ({timestamp,level,message,component}). Never throws.
#>
function Import-AppDbOpsLogFromJsonl {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$JsonlPath
    )

    $out = @{ success = $false; imported = 0; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }
    if (-not (Test-Path -LiteralPath $JsonlPath)) {
        $out.success = $true
        return [pscustomobject]$out
    }

    try {
        $dbPath = [string]$script:AppDbState.databasePath
        $maxRows = @(Invoke-AppDbQuery -DatabasePath $dbPath -Sql 'SELECT MAX(timestamp) AS m FROM ops_log')
        $maxTs = ''
        if ($maxRows.Count -gt 0) {
            $maxValue = _AppDbRecordValue -Record $maxRows[0] -Name 'm'
            if ($null -ne $maxValue) { $maxTs = [string]$maxValue }
        }

        $pending = [System.Collections.Generic.List[object]]::new()
        foreach ($line in [System.IO.File]::ReadAllLines($JsonlPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $obj = $null
            try { $obj = ConvertFrom-Json -InputObject $line } catch { continue }
            if ($null -eq $obj) { continue }

            $ts = [string](_AppDbRecordValue -Record $obj -Name 'ts')
            if ([string]::IsNullOrWhiteSpace($ts)) { $ts = [string](_AppDbRecordValue -Record $obj -Name 'timestamp') }
            if ([string]::IsNullOrWhiteSpace($ts)) { continue }
            if ($maxTs -ne '' -and [string]::CompareOrdinal($ts, $maxTs) -le 0) { continue }

            $lvl = [string](_AppDbRecordValue -Record $obj -Name 'level')
            if ([string]::IsNullOrWhiteSpace($lvl)) { $lvl = 'INFO' }
            $msg = [string](_AppDbRecordValue -Record $obj -Name 'msg')
            if ([string]::IsNullOrWhiteSpace($msg)) { $msg = [string](_AppDbRecordValue -Record $obj -Name 'message') }
            $src = [string](_AppDbRecordValue -Record $obj -Name 'component')
            if ([string]::IsNullOrWhiteSpace($src)) { $src = 'jsonl-import' }

            $pending.Add([pscustomobject]@{ ts = $ts; level = $lvl.ToUpperInvariant(); source = $src; message = $msg })
        }

        if ($pending.Count -gt 0) {
            Invoke-AppDbTransaction -DatabasePath $dbPath -Body {
                param($session)
                foreach ($row in $pending) {
                    $null = Invoke-AppDbSessionNonQuery -Session $session `
                        -Sql 'INSERT INTO ops_log (timestamp, level, source, message, data_json) VALUES (@timestamp, @level, @source, @message, NULL)' `
                        -Parameters @{
                            timestamp = [string]$row.ts
                            level     = [string]$row.level
                            source    = [string]$row.source
                            message   = [string]$row.message
                        }
                }
            }
        }

        $out.imported = $pending.Count
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

# ---------------------------------------------------------------------------
# Phase 3 migration — maturity + portfolio + differential snapshots
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Persists one portfolio-assessment capture into maturity_history,
    portfolio_index_history, and repo_signals.
.DESCRIPTION
    This is append-only time-series persistence for Release 2.1 Phase 3.
    It never throws so callers can keep in-memory and JSON paths healthy.
#>
function Write-AppDbPortfolioAssessmentSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][object[]]$Assessments,
        [Parameter()][string]$ScanId = '',
        [Parameter()][string]$CapturedAt = ''
    )

    $out = @{ success = $false; inserted = 0L; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        $capturedAtIso = if ([string]::IsNullOrWhiteSpace($CapturedAt)) { (Get-Date).ToUniversalTime().ToString('o') } else { $CapturedAt }
        $effectiveScanId = if ([string]::IsNullOrWhiteSpace($ScanId)) { [guid]::NewGuid().ToString('n') } else { $ScanId }
        $rows = @($Assessments)

        if ($rows.Count -eq 0) {
            $out.success = $true
            return [pscustomobject]$out
        }

        $dbPath = [string]$script:AppDbState.databasePath
        Invoke-AppDbTransaction -DatabasePath $dbPath -Body {
            param($session)

            foreach ($assessment in $rows) {
                if ($null -eq $assessment) { continue }

                $repoName = [string](_AppDbFirstRecordValue -Record $assessment -Names @('repoName', 'name') -Default '')
                if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

                $repoPath = [string](_AppDbFirstRecordValue -Record $assessment -Names @('localPath', 'repoPath') -Default '')
                $ownerRepo = [string](_AppDbFirstRecordValue -Record $assessment -Names @('githubFullName', 'ownerRepo') -Default '')
                $lifecycleState = [string](_AppDbFirstRecordValue -Record $assessment -Names @('lifecycleState') -Default '')
                $sourceCoverage = [string](_AppDbFirstRecordValue -Record $assessment -Names @('sourceCoverage') -Default '')

                $recordJson = ConvertTo-Json -InputObject $assessment -Compress -Depth 16
                $null = Invoke-AppDbSessionNonQuery -Session $session -Sql @'
INSERT INTO portfolio_index_history
  (scan_id, captured_at, repo_name, repo_path, owner_repo, lifecycle_state, source_coverage, record_json)
VALUES
  (@scan_id, @captured_at, @repo_name, @repo_path, @owner_repo, @lifecycle_state, @source_coverage, @record_json)
'@ -Parameters @{
                    scan_id         = $effectiveScanId
                    captured_at     = $capturedAtIso
                    repo_name       = $repoName
                    repo_path       = $repoPath
                    owner_repo      = $ownerRepo
                    lifecycle_state = $lifecycleState
                    source_coverage = $sourceCoverage
                    record_json     = $recordJson
                }

                $maturityLevel = [string](_AppDbFirstRecordValue -Record $assessment -Names @('maturityLevel') -Default '')
                $maturityScore = _AppDbFirstRecordValue -Record $assessment -Names @('maturityScore') -Default $null
                $pendingCount = _AppDbFirstRecordValue -Record $assessment -Names @('pendingItemCount', 'pendingCount') -Default $null
                $roadmapPath = [string](_AppDbFirstRecordValue -Record $assessment -Names @('roadmapPath') -Default '')

                $null = Invoke-AppDbSessionNonQuery -Session $session -Sql @'
INSERT INTO maturity_history
  (repo_name, roadmap_path, maturity_level, maturity_score, pending_count, captured_at)
VALUES
  (@repo_name, @roadmap_path, @maturity_level, @maturity_score, @pending_count, @captured_at)
'@ -Parameters @{
                    repo_name      = $repoName
                    roadmap_path   = $roadmapPath
                    maturity_level = $maturityLevel
                    maturity_score = if ($null -ne $maturityScore) { [double]$maturityScore } else { $null }
                    pending_count  = if ($null -ne $pendingCount) { [long]$pendingCount } else { $null }
                    captured_at    = $capturedAtIso
                }

                $readmeScore = _AppDbFirstRecordValue -Record $assessment -Names @('readmeScore') -Default $null
                $roadmapScore = _AppDbFirstRecordValue -Record $assessment -Names @('roadmapScore') -Default $null
                $docHealthScore = _AppDbFirstRecordValue -Record $assessment -Names @('documentationHealthScore', 'docHealthScore') -Default $null
                $dirtyFileCount = _AppDbFirstRecordValue -Record $assessment -Names @('localDirtyCount', 'dirtyFileCount') -Default 0
                $openPrCount = _AppDbFirstRecordValue -Record $assessment -Names @('openPrCount') -Default 0
                $actionsStatus = [string](_AppDbFirstRecordValue -Record $assessment -Names @('latestActionsStatus', 'actionsStatus') -Default '')
                $actionsConclusion = [string](_AppDbFirstRecordValue -Record $assessment -Names @('latestActionsConclusion', 'actionsConclusion') -Default '')
                $pagesStatus = [string](_AppDbFirstRecordValue -Record $assessment -Names @('pagesStatus') -Default '')

                $signal = [ordered]@{
                    readmeScore      = $readmeScore
                    roadmapScore     = $roadmapScore
                    docHealthScore   = $docHealthScore
                    dirtyFileCount   = $dirtyFileCount
                    openPrCount      = $openPrCount
                    actionsStatus    = $actionsStatus
                    actionsConclusion = $actionsConclusion
                    pagesStatus      = $pagesStatus
                }

                $null = Invoke-AppDbSessionNonQuery -Session $session -Sql @'
INSERT INTO repo_signals
  (repo_name, captured_at, readme_score, roadmap_score, doc_health_score,
   dirty_file_count, open_pr_count, actions_status, actions_conclusion, pages_status, signal_json)
VALUES
  (@repo_name, @captured_at, @readme_score, @roadmap_score, @doc_health_score,
   @dirty_file_count, @open_pr_count, @actions_status, @actions_conclusion, @pages_status, @signal_json)
'@ -Parameters @{
                    repo_name          = $repoName
                    captured_at        = $capturedAtIso
                    readme_score       = if ($null -ne $readmeScore) { [double]$readmeScore } else { $null }
                    roadmap_score      = if ($null -ne $roadmapScore) { [double]$roadmapScore } else { $null }
                    doc_health_score   = if ($null -ne $docHealthScore) { [double]$docHealthScore } else { $null }
                    dirty_file_count   = if ($null -ne $dirtyFileCount) { [long]$dirtyFileCount } else { 0L }
                    open_pr_count      = if ($null -ne $openPrCount) { [long]$openPrCount } else { 0L }
                    actions_status     = $actionsStatus
                    actions_conclusion = $actionsConclusion
                    pages_status       = $pagesStatus
                    signal_json        = (ConvertTo-Json -InputObject $signal -Compress -Depth 8)
                }

                $out.inserted = [long]$out.inserted + 1L
            }
        }

        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Persists one scan-level differential summary record.
#>
function Write-AppDbDifferentialScanSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$ScanId,
        [Parameter(Mandatory = $true)][string]$ScanMode,
        [Parameter()][string]$StartedAt = '',
        [Parameter()][string]$CompletedAt = '',
        [Parameter()][int]$ReposTotal = 0,
        [Parameter()][int]$ReposChanged = 0,
        [Parameter()][string[]]$ChangedRepoNames = @()
    )

    $out = @{ success = $false; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        $startedAtIso = if ([string]::IsNullOrWhiteSpace($StartedAt)) { (Get-Date).ToUniversalTime().ToString('o') } else { $StartedAt }
        $completedAtIso = if ([string]::IsNullOrWhiteSpace($CompletedAt)) { (Get-Date).ToUniversalTime().ToString('o') } else { $CompletedAt }
        $changedJson = ConvertTo-Json -InputObject @($ChangedRepoNames) -Compress -Depth 4
        $null = Invoke-AppDbNonQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
INSERT INTO differential_scans
  (scan_id, scan_mode, started_at, completed_at, repos_total, repos_changed, changed_json)
VALUES
  (@scan_id, @scan_mode, @started_at, @completed_at, @repos_total, @repos_changed, @changed_json)
'@ -Parameters @{
            scan_id       = $ScanId
            scan_mode     = $ScanMode
            started_at    = $startedAtIso
            completed_at  = $completedAtIso
            repos_total   = [long]$ReposTotal
            repos_changed = [long]$ReposChanged
            changed_json  = $changedJson
        }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Upserts one repo curation row in SQLite.
#>
function Write-AppDbRepoCurationEntry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$RepoId,
        [Parameter(Mandatory = $true)][string]$CurationState,
        [Parameter()][string]$UpdatedAt = '',
        [Parameter()][string]$Reason = ''
    )

    $out = @{ success = $false; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        $updatedAtIso = if ([string]::IsNullOrWhiteSpace($UpdatedAt)) { (Get-Date).ToUniversalTime().ToString('o') } else { $UpdatedAt }
        $null = Invoke-AppDbNonQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
INSERT INTO repo_curation (repo_id, curation_state, updated_at, reason)
VALUES (@repo_id, @curation_state, @updated_at, @reason)
ON CONFLICT(repo_id) DO UPDATE SET
  curation_state = excluded.curation_state,
  updated_at = excluded.updated_at,
  reason = excluded.reason
'@ -Parameters @{
            repo_id        = [string]$RepoId
            curation_state = [string]$CurationState
            updated_at     = [string]$updatedAtIso
            reason         = if ([string]::IsNullOrWhiteSpace($Reason)) { $null } else { [string]$Reason }
        }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Reads all persisted repo curation rows from SQLite.
#>
function Get-AppDbRepoCurationEntries {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if (-not $script:AppDbState.enabled) {
        return [pscustomobject]@{ available = $false; entries = @(); reason = 'app-db-not-initialized' }
    }

    try {
        $rows = @(Invoke-AppDbQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
SELECT repo_id, curation_state, updated_at, reason
FROM repo_curation
ORDER BY updated_at DESC
'@)

        $entries = @($rows | ForEach-Object {
            [pscustomobject]@{
                repoId        = [string](_AppDbRecordValue -Record $_ -Name 'repo_id')
                curationState = [string](_AppDbRecordValue -Record $_ -Name 'curation_state')
                updatedAt     = [string](_AppDbRecordValue -Record $_ -Name 'updated_at')
                reason        = [string](_AppDbRecordValue -Record $_ -Name 'reason')
            }
        })

        return [pscustomobject]@{ available = $true; entries = $entries; reason = '' }
    } catch {
        return [pscustomobject]@{ available = $false; entries = @(); reason = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Persists one merge-readiness evaluation snapshot in SQLite.
#>
function Write-AppDbMergeReadinessSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][object]$Evaluation
    )

    $out = @{ success = $false; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        $repoId = [string](_AppDbFirstRecordValue -Record $Evaluation -Names @('repoId') -Default '')
        if ([string]::IsNullOrWhiteSpace($repoId)) {
            $out.reason = 'missing-repo-id'
            return [pscustomobject]$out
        }

        $repoName = [string](_AppDbFirstRecordValue -Record $Evaluation -Names @('repoName') -Default '')
        $runId = [string](_AppDbFirstRecordValue -Record $Evaluation -Names @('runId') -Default '')
        $prNumber = _AppDbFirstRecordValue -Record $Evaluation -Names @('prNumber') -Default $null
        $ready = [bool](_AppDbFirstRecordValue -Record $Evaluation -Names @('ready') -Default $false)
        $capturedAt = [string](_AppDbFirstRecordValue -Record $Evaluation -Names @('evaluatedAt') -Default (Get-Date).ToUniversalTime().ToString('o'))
        $blockers = _AppDbFirstRecordValue -Record $Evaluation -Names @('blockers') -Default @()
        $evidence = _AppDbFirstRecordValue -Record $Evaluation -Names @('evidence') -Default @{}

        $null = Invoke-AppDbNonQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
INSERT INTO merge_readiness_snapshots
  (repo_id, repo_name, run_id, pr_number, ready, captured_at, blockers_json, evidence_json)
VALUES
  (@repo_id, @repo_name, @run_id, @pr_number, @ready, @captured_at, @blockers_json, @evidence_json)
'@ -Parameters @{
            repo_id       = $repoId
            repo_name     = $repoName
            run_id        = if ([string]::IsNullOrWhiteSpace($runId)) { $null } else { $runId }
            pr_number     = if ($null -ne $prNumber) { [long]$prNumber } else { $null }
            ready         = if ($ready) { 1L } else { 0L }
            captured_at   = $capturedAt
            blockers_json = (ConvertTo-Json -InputObject @($blockers) -Compress -Depth 8)
            evidence_json = (ConvertTo-Json -InputObject $evidence -Compress -Depth 8)
        }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Reads roadmap maturity history for one repo or all repos in a time range.
#>
function Get-AppDbRoadmapMaturityHistory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][string]$RepoName = '',
        [Parameter()][int]$Days = 30
    )

    if (-not $script:AppDbState.enabled) {
        return [pscustomobject]@{ available = $false; entries = @() }
    }

    if ($Days -lt 1) { $Days = 1 }
    $sinceIso = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('o')
    $rows = @(Invoke-AppDbQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
SELECT repo_name, roadmap_path, maturity_level, maturity_score, pending_count, captured_at
FROM maturity_history
WHERE (@repo_name = '' OR repo_name = @repo_name)
  AND captured_at >= @since
ORDER BY captured_at ASC, repo_name ASC
'@ -Parameters @{
        repo_name = [string]$RepoName
        since     = $sinceIso
    })

    $entries = @($rows | ForEach-Object {
        [pscustomobject]@{
            repoName      = [string](_AppDbRecordValue -Record $_ -Name 'repo_name')
            roadmapPath   = _AppDbRecordValue -Record $_ -Name 'roadmap_path'
            maturityLevel = [string](_AppDbRecordValue -Record $_ -Name 'maturity_level')
            maturityScore = _AppDbRecordValue -Record $_ -Name 'maturity_score'
            pendingCount  = _AppDbRecordValue -Record $_ -Name 'pending_count'
            capturedAt    = [string](_AppDbRecordValue -Record $_ -Name 'captured_at')
        }
    })

    return [pscustomobject]@{ available = $true; entries = $entries }
}

# ---------------------------------------------------------------------------
# Phase 3 migration — agent-run metrics and quota-burn history
# ---------------------------------------------------------------------------

function _AppDbIsoTimestamp {
    # Normalizes a timestamp to a sortable ISO-8601 UTC string. Values arrive
    # either as ISO strings (fresh records) or [datetime] objects (records
    # re-read via ConvertFrom-Json); a plain [string] cast of a [datetime]
    # yields a locale format that breaks lexicographic ordering.
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o') }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return ([datetime]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime().ToString('o')
    } catch {
        return $text
    }
}

function _AppDbNullableDouble {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $number = 0.0
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return [double]$number
    }
    return $null
}

function _AppDbNullableLong {
    param([object]$Value)

    $number = _AppDbNullableDouble -Value $Value
    if ($null -eq $number) { return $null }
    return [long]$number
}

function _AppDbNullableText {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

<#
.SYNOPSIS
    Mirrors one agent-run ledger record — including its timing/token/cost
    work-unit metrics — into the agent_runs table. No-ops with a reason while
    the persistence boundary is disabled and never throws: a mirror failure
    must never break the run it describes. The JSON runs directory remains
    authoritative during the Release 2.1 rollout.
#>
function Write-AppDbAgentRun {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][object]$RunRecord
    )

    $out = @{ success = $false; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        $runId = [string](_AppDbFirstRecordValue -Record $RunRecord -Names @('runId', 'run_id') -Default '')
        if ([string]::IsNullOrWhiteSpace($runId)) {
            $out.reason = 'missing-run-id'
            return [pscustomobject]$out
        }

        $metrics = _AppDbFirstRecordValue -Record $RunRecord -Names @('metrics') -Default $null

        $dispatchedAt = _AppDbIsoTimestamp -Value (_AppDbFirstRecordValue -Record $metrics -Names @('dispatchedAt', 'dispatched_at') -Default (_AppDbFirstRecordValue -Record $RunRecord -Names @('createdAt', 'created_at') -Default $null))
        $updatedAt = _AppDbIsoTimestamp -Value (_AppDbFirstRecordValue -Record $RunRecord -Names @('updatedAt', 'updated_at') -Default $null)
        if ($null -eq $updatedAt) { $updatedAt = (Get-Date).ToUniversalTime().ToString('o') }

        $null = Invoke-AppDbNonQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
INSERT OR REPLACE INTO agent_runs
  (run_id, repo_name, status, dispatched_at, started_at, completed_at,
   time_to_deliver_seconds, prompt_count, retry_count, tokens_reported,
   direct_cost_usd, work_units_estimated, work_units_actual,
   release_name, phase_name, section_name, record_json, updated_at)
VALUES
  (@run_id, @repo_name, @status, @dispatched_at, @started_at, @completed_at,
   @time_to_deliver_seconds, @prompt_count, @retry_count, @tokens_reported,
   @direct_cost_usd, @work_units_estimated, @work_units_actual,
   @release_name, @phase_name, @section_name, @record_json, @updated_at)
'@ -Parameters @{
            run_id                  = $runId
            repo_name               = _AppDbNullableText (_AppDbFirstRecordValue -Record $RunRecord -Names @('repoName', 'repo_name') -Default '')
            status                  = _AppDbNullableText (_AppDbFirstRecordValue -Record $RunRecord -Names @('status') -Default '')
            dispatched_at           = $dispatchedAt
            started_at              = _AppDbIsoTimestamp -Value (_AppDbFirstRecordValue -Record $metrics -Names @('agentStartedAt', 'agent_started_at') -Default $null)
            completed_at            = _AppDbIsoTimestamp -Value (_AppDbFirstRecordValue -Record $metrics -Names @('agentCompletedAt', 'agent_completed_at') -Default $null)
            time_to_deliver_seconds = _AppDbNullableDouble (_AppDbFirstRecordValue -Record $metrics -Names @('timeToDeliverSeconds', 'time_to_deliver_seconds') -Default $null)
            prompt_count            = _AppDbNullableLong (_AppDbFirstRecordValue -Record $metrics -Names @('promptCount', 'prompt_count') -Default $null)
            retry_count             = _AppDbNullableLong (_AppDbFirstRecordValue -Record $metrics -Names @('retries', 'retryCount', 'retry_count') -Default $null)
            tokens_reported         = _AppDbNullableLong (_AppDbFirstRecordValue -Record $metrics -Names @('tokenUsage', 'tokensReported', 'tokens_reported') -Default $null)
            direct_cost_usd         = _AppDbNullableDouble (_AppDbFirstRecordValue -Record $metrics -Names @('apiSpendUsd', 'directCostUsd', 'direct_cost_usd') -Default $null)
            work_units_estimated    = _AppDbNullableDouble (_AppDbFirstRecordValue -Record $metrics -Names @('workUnitsEstimated', 'work_units_estimated') -Default $null)
            work_units_actual       = _AppDbNullableDouble (_AppDbFirstRecordValue -Record $metrics -Names @('workUnitsActual', 'work_units_actual') -Default $null)
            release_name            = _AppDbNullableText (_AppDbFirstRecordValue -Record $RunRecord -Names @('plannedReleaseName', 'planned_release_name', 'releaseName') -Default $null)
            phase_name              = _AppDbNullableText (_AppDbFirstRecordValue -Record $RunRecord -Names @('plannedPhaseName', 'planned_phase_name', 'phaseName') -Default $null)
            section_name            = _AppDbNullableText (_AppDbFirstRecordValue -Record $RunRecord -Names @('selectedTaskSection', 'selected_task_section', 'sectionName') -Default $null)
            record_json             = (ConvertTo-Json -InputObject $RunRecord -Compress -Depth 8)
            updated_at              = $updatedAt
        }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Captures one dispatch quota evaluation (from Test-AgentDispatchQuota)
    into the quota_burn_snapshots table so quota burn-down is queryable over
    time. Best-effort: no-ops with a reason while the persistence boundary is
    disabled and never throws — the JSONL quota.* events remain the raw
    debugging artifact.
#>
function Write-AppDbQuotaBurnSnapshot {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][object]$Evaluation
    )

    $out = @{ success = $false; reason = '' }
    if (-not $script:AppDbState.enabled) {
        $out.reason = 'app-db-not-initialized'
        return [pscustomobject]$out
    }

    try {
        $usage = _AppDbFirstRecordValue -Record $Evaluation -Names @('usage') -Default $null
        $allowed = [bool](_AppDbFirstRecordValue -Record $Evaluation -Names @('allowed') -Default $false)

        $null = Invoke-AppDbNonQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
INSERT INTO quota_burn_snapshots
  (repo_name, budget_period, evaluated_at, estimated_work_units,
   units_consumed, remaining_before, remaining_after, allowed, blocked_code,
   planned_release, planned_phase, snapshot_json)
VALUES
  (@repo_name, @budget_period, @evaluated_at, @estimated_work_units,
   @units_consumed, @remaining_before, @remaining_after, @allowed,
   @blocked_code, @planned_release, @planned_phase, @snapshot_json)
'@ -Parameters @{
            repo_name            = $RepoName
            budget_period        = _AppDbNullableText (_AppDbFirstRecordValue -Record $Evaluation -Names @('period', 'budgetPeriod') -Default $null)
            evaluated_at         = (Get-Date).ToUniversalTime().ToString('o')
            estimated_work_units = _AppDbNullableDouble (_AppDbFirstRecordValue -Record $Evaluation -Names @('estimatedWorkUnits', 'estimated_work_units') -Default $null)
            units_consumed       = _AppDbNullableDouble (_AppDbFirstRecordValue -Record $usage -Names @('unitsConsumed', 'units_consumed') -Default $null)
            remaining_before     = _AppDbNullableDouble (_AppDbFirstRecordValue -Record $usage -Names @('remainingBefore', 'remaining_before') -Default $null)
            remaining_after      = _AppDbNullableDouble (_AppDbFirstRecordValue -Record $usage -Names @('remainingAfter', 'remaining_after') -Default $null)
            allowed              = if ($allowed) { 1L } else { 0L }
            blocked_code         = _AppDbNullableText (_AppDbFirstRecordValue -Record $Evaluation -Names @('blockedCode', 'blocked_code') -Default $null)
            planned_release      = _AppDbNullableText (_AppDbFirstRecordValue -Record $Evaluation -Names @('plannedReleaseName', 'planned_release') -Default $null)
            planned_phase        = _AppDbNullableText (_AppDbFirstRecordValue -Record $Evaluation -Names @('plannedPhaseName', 'planned_phase') -Default $null)
            snapshot_json        = (ConvertTo-Json -InputObject $Evaluation -Compress -Depth 8)
        }
        $out.success = $true
    } catch {
        $out.reason = $_.Exception.Message
    }

    return [pscustomobject]$out
}

<#
.SYNOPSIS
    Reads agent-run metrics history (timing/token/cost/work units per run)
    for one repo or all repos in a time range, ordered oldest-first. When
    -SeedFromRunsDirectory is provided and the agent_runs table is empty, the
    first read seeds it from the legacy JSON runs directory — mirroring the
    execution-ledger first-run migration.
#>
function Get-AppDbAgentRunMetricsHistory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][string]$RepoName = '',
        [Parameter()][int]$Days = 30,
        [Parameter()][string]$SeedFromRunsDirectory = ''
    )

    if (-not $script:AppDbState.enabled) {
        return [pscustomobject]@{ available = $false; entries = @() }
    }

    if ($Days -lt 1) { $Days = 1 }
    $dbPath = [string]$script:AppDbState.databasePath

    if (-not [string]::IsNullOrWhiteSpace($SeedFromRunsDirectory) -and
        (Test-Path -LiteralPath $SeedFromRunsDirectory -PathType Container)) {
        $runCount = [long](Invoke-AppDbQuery -DatabasePath $dbPath -Sql 'SELECT COUNT(*) AS n FROM agent_runs')[0].n
        if ($runCount -eq 0) {
            foreach ($runFile in @(Get-ChildItem -LiteralPath $SeedFromRunsDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                try {
                    $legacyRun = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $runFile.FullName -Raw -Encoding UTF8)
                    $null = Write-AppDbAgentRun -RunRecord $legacyRun
                } catch {
                    Write-Warning "Persistence.Store: agent-run file '$($runFile.FullName)' could not be parsed for seeding: $_"
                }
            }
        }
    }

    $sinceIso = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('o')
    $rows = @(Invoke-AppDbQuery -DatabasePath $dbPath -Sql @'
SELECT run_id, repo_name, status, dispatched_at, started_at, completed_at,
       time_to_deliver_seconds, prompt_count, retry_count, tokens_reported,
       direct_cost_usd, work_units_estimated, work_units_actual,
       release_name, phase_name, section_name, updated_at
FROM agent_runs
WHERE (@repo_name = '' OR repo_name = @repo_name)
  AND COALESCE(dispatched_at, updated_at) >= @since
ORDER BY COALESCE(dispatched_at, updated_at) ASC, run_id ASC
'@ -Parameters @{
        repo_name = [string]$RepoName
        since     = $sinceIso
    })

    $entries = @($rows | ForEach-Object {
        [pscustomobject]@{
            runId                = [string](_AppDbRecordValue -Record $_ -Name 'run_id')
            repoName             = [string](_AppDbRecordValue -Record $_ -Name 'repo_name')
            status               = [string](_AppDbRecordValue -Record $_ -Name 'status')
            dispatchedAt         = _AppDbRecordValue -Record $_ -Name 'dispatched_at'
            startedAt            = _AppDbRecordValue -Record $_ -Name 'started_at'
            completedAt          = _AppDbRecordValue -Record $_ -Name 'completed_at'
            timeToDeliverSeconds = _AppDbRecordValue -Record $_ -Name 'time_to_deliver_seconds'
            promptCount          = _AppDbRecordValue -Record $_ -Name 'prompt_count'
            retryCount           = _AppDbRecordValue -Record $_ -Name 'retry_count'
            tokensReported       = _AppDbRecordValue -Record $_ -Name 'tokens_reported'
            directCostUsd        = _AppDbRecordValue -Record $_ -Name 'direct_cost_usd'
            workUnitsEstimated   = _AppDbRecordValue -Record $_ -Name 'work_units_estimated'
            workUnitsActual      = _AppDbRecordValue -Record $_ -Name 'work_units_actual'
            releaseName          = _AppDbRecordValue -Record $_ -Name 'release_name'
            phaseName            = _AppDbRecordValue -Record $_ -Name 'phase_name'
            sectionName          = _AppDbRecordValue -Record $_ -Name 'section_name'
            updatedAt            = _AppDbRecordValue -Record $_ -Name 'updated_at'
        }
    })

    return [pscustomobject]@{ available = $true; entries = $entries }
}

<#
.SYNOPSIS
    Reads quota burn-down history (one row per dispatch quota evaluation)
    for one repo or all repos in a time range, ordered oldest-first.
#>
function Get-AppDbQuotaBurnHistory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][string]$RepoName = '',
        [Parameter()][int]$Days = 30
    )

    if (-not $script:AppDbState.enabled) {
        return [pscustomobject]@{ available = $false; entries = @() }
    }

    if ($Days -lt 1) { $Days = 1 }
    $sinceIso = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('o')
    $rows = @(Invoke-AppDbQuery -DatabasePath ([string]$script:AppDbState.databasePath) -Sql @'
SELECT snapshot_id, repo_name, budget_period, evaluated_at,
       estimated_work_units, units_consumed, remaining_before,
       remaining_after, allowed, blocked_code, planned_release, planned_phase
FROM quota_burn_snapshots
WHERE (@repo_name = '' OR repo_name = @repo_name)
  AND evaluated_at >= @since
ORDER BY evaluated_at ASC, snapshot_id ASC
'@ -Parameters @{
        repo_name = [string]$RepoName
        since     = $sinceIso
    })

    $entries = @($rows | ForEach-Object {
        $allowedRaw = _AppDbRecordValue -Record $_ -Name 'allowed'
        [pscustomobject]@{
            repoName           = [string](_AppDbRecordValue -Record $_ -Name 'repo_name')
            budgetPeriod       = _AppDbRecordValue -Record $_ -Name 'budget_period'
            evaluatedAt        = [string](_AppDbRecordValue -Record $_ -Name 'evaluated_at')
            estimatedWorkUnits = _AppDbRecordValue -Record $_ -Name 'estimated_work_units'
            unitsConsumed      = _AppDbRecordValue -Record $_ -Name 'units_consumed'
            remainingBefore    = _AppDbRecordValue -Record $_ -Name 'remaining_before'
            remainingAfter     = _AppDbRecordValue -Record $_ -Name 'remaining_after'
            allowed            = ($null -ne $allowedRaw -and [long]$allowedRaw -ne 0)
            blockedCode        = _AppDbRecordValue -Record $_ -Name 'blocked_code'
            plannedRelease     = _AppDbRecordValue -Record $_ -Name 'planned_release'
            plannedPhase       = _AppDbRecordValue -Record $_ -Name 'planned_phase'
        }
    })

    return [pscustomobject]@{ available = $true; entries = $entries }
}
