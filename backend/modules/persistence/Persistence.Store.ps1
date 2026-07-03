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
      - The first migration seam: Write-AppDbAgentRunEvent mirrors
        agent-run lifecycle events into the database. During rollout the
        JSON/JSONL stores remain authoritative; the database is additive.

    Rollout contract (Release 2.1): JSON-backed artifacts keep working and
    keep being written. Nothing in this module may throw for the mere
    absence of SQLite; only explicit query helpers throw on real SQL errors.

.NOTES
    Dot-source this file to load the public functions:
        . (Join-Path $persistenceModuleRoot 'Persistence.Store.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants and module state
# ---------------------------------------------------------------------------

$script:AppDbSchemaVersion = 1
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

        public static long ExecuteNonQuery(string dbPath, string sql, string[] names, object[] values)
        {
            IntPtr db = OpenDb(dbPath);
            try
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
            finally { _closeV2(db); }
        }

        public static List<Dictionary<string, object>> Query(string dbPath, string sql, string[] names, object[] values)
        {
            List<Dictionary<string, object>> rows = new List<Dictionary<string, object>>();
            IntPtr db = OpenDb(dbPath);
            try
            {
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
            }
            finally { _closeV2(db); }
            return rows;
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
                  [object]'Release 2.1 Phase 1 - initial persistence schema',
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
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $obj = [ordered]@{}
        foreach ($kv in $row.GetEnumerator()) {
            $obj[$kv.Key] = $kv.Value
        }
        $out.Add([pscustomobject]$obj)
    }
    return $out.ToArray()
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
