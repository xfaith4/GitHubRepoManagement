<#
.SYNOPSIS
    Notification hub — webhook registry and event dispatcher for Release 1.1.
.DESCRIPTION
    Provides five exported functions:

      Register-NotificationWebhook
        Registers a new webhook URL with one or more event subscriptions.

      Get-NotificationWebhooks
        Returns the full list of registered webhooks.

      Remove-NotificationWebhook
        Removes a webhook by its generated ID.

      Send-NotificationEvent
        Dispatches an event to all webhooks subscribed to it via HTTP POST.

    Supported event names:
      scan.completed  | repair.applied  | execution.failed  | drift.detected

    Webhook registry is stored at: output/notification-webhooks.json
    All functions are safe to call when the config file does not yet exist.

.NOTES
    Dot-source this file to load all functions:
        . (Join-Path $moduleRoot 'NotificationHub.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:WebhooksFile       = 'output/notification-webhooks.json'
$script:SupportedEvents    = @('scan.completed', 'repair.applied', 'execution.failed', 'drift.detected')

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _GetWebhooksPath {
    param([string]$WorkspaceRoot)
    return Join-Path $WorkspaceRoot $script:WebhooksFile
}

function _EnsureOutputDir {
    param([string]$WorkspaceRoot)
    $dir = Join-Path $WorkspaceRoot 'output'
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
}

function _ReadWebhooksStore {
    param([string]$WorkspaceRoot)
    $path  = _GetWebhooksPath -WorkspaceRoot $WorkspaceRoot
    $empty = @{ webhooks = @() }
    if (-not (Test-Path -LiteralPath $path)) { return $empty }
    try {
        $raw    = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $parsed = ConvertFrom-Json -InputObject $raw
        return @{
            webhooks = @($parsed.webhooks ?? @())
        }
    } catch {
        return $empty
    }
}

function _WriteWebhooksStore {
    param([string]$WorkspaceRoot, [hashtable]$Store)
    _EnsureOutputDir -WorkspaceRoot $WorkspaceRoot
    $path = _GetWebhooksPath -WorkspaceRoot $WorkspaceRoot
    $json = $Store | ConvertTo-Json -Depth 10 -Compress
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8 -NoNewline
}

# ---------------------------------------------------------------------------
# Register-NotificationWebhook
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Register a new webhook URL for one or more event types.
.PARAMETER WorkspaceRoot
    Path to the workspace root (where output/ lives).
.PARAMETER WebhookUrl
    The HTTP(S) URL that will receive POST payloads.
.PARAMETER Events
    Array of event names to subscribe to.
.PARAMETER Label
    Optional friendly label for this webhook.
.OUTPUTS
    [pscustomobject] with id, url, label, events, registeredAt.
#>
function Register-NotificationWebhook {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory = $true)]
        [string]$WebhookUrl,

        [Parameter(Mandatory = $true)]
        [string[]]$Events,

        [Parameter()]
        [string]$Label = ''
    )

    # Validate URL scheme — only allow HTTP(S) to prevent SSRF via file://, ftp://, etc.
    if ($WebhookUrl -notmatch '^https?://') {
        throw "Invalid webhook URL '$WebhookUrl': only http:// and https:// URLs are accepted."
    }

    # Validate that at least one recognised event is specified
    $invalid = @($Events | Where-Object { $_ -notin $script:SupportedEvents })
    if ($invalid.Count -gt 0) {
        throw "Unknown event name(s): $($invalid -join ', '). Supported events: $($script:SupportedEvents -join ', ')."
    }

    $now   = (Get-Date).ToUniversalTime().ToString('o')
    $id    = [guid]::NewGuid().ToString('n')
    $store = _ReadWebhooksStore -WorkspaceRoot $WorkspaceRoot

    $newEntry = [pscustomobject]@{
        id             = $id
        url            = $WebhookUrl
        label          = $Label
        events         = @($Events)
        registeredAt   = $now
        enabled        = $true
        lastFiredAt    = $null
        lastFireResult = $null
    }

    $store.webhooks = @($store.webhooks) + @($newEntry)

    try {
        _WriteWebhooksStore -WorkspaceRoot $WorkspaceRoot -Store $store
    } catch {
        Write-Warning "NotificationHub: webhook '$id' registered in-memory but could not be persisted: $_"
    }

    return [pscustomobject]@{
        id           = $id
        url          = $WebhookUrl
        label        = $Label
        events       = @($Events)
        registeredAt = $now
    }
}

# ---------------------------------------------------------------------------
# Get-NotificationWebhooks
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Return all registered notification webhooks.
.PARAMETER WorkspaceRoot
    Path to the workspace root.
.OUTPUTS
    Array of webhook objects.
#>
function Get-NotificationWebhooks {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    $store = _ReadWebhooksStore -WorkspaceRoot $WorkspaceRoot
    return @($store.webhooks)
}

# ---------------------------------------------------------------------------
# Remove-NotificationWebhook
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Remove a registered webhook by its ID.
.PARAMETER WorkspaceRoot
    Path to the workspace root.
.PARAMETER WebhookId
    The ID of the webhook to remove.
.OUTPUTS
    [pscustomobject] with success.
#>
function Remove-NotificationWebhook {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory = $true)]
        [string]$WebhookId
    )

    $store   = _ReadWebhooksStore -WorkspaceRoot $WorkspaceRoot
    $before  = $store.webhooks.Count
    $store.webhooks = @($store.webhooks | Where-Object { $_.id -ne $WebhookId })

    if ($store.webhooks.Count -eq $before) {
        return [pscustomobject]@{
            success = $false
            error   = "Webhook '$WebhookId' not found."
        }
    }

    try {
        _WriteWebhooksStore -WorkspaceRoot $WorkspaceRoot -Store $store
    } catch {
        return [pscustomobject]@{
            success = $false
            error   = "Failed to persist removal: $_"
        }
    }

    return [pscustomobject]@{ success = $true }
}

# ---------------------------------------------------------------------------
# Send-NotificationEvent
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Fire an event to all webhooks subscribed to it.
.PARAMETER WorkspaceRoot
    Path to the workspace root.
.PARAMETER EventName
    The event name (e.g. 'scan.completed').
.PARAMETER EventPayload
    Hashtable of event-specific data to include in the POST body.
.NOTES
    Dispatch is synchronous: webhooks are called sequentially, each with a
    10-second timeout. Total blocking time scales linearly with the number of
    subscribed webhooks. Individual webhook failures are caught and do not
    propagate to the caller.
.OUTPUTS
    [pscustomobject] with fired (array of {webhookId, success, error}),
    eventName, sentAt.
#>
function Send-NotificationEvent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory = $true)]
        [string]$EventName,

        [Parameter(Mandatory = $true)]
        [hashtable]$EventPayload
    )

    $now    = (Get-Date).ToUniversalTime().ToString('o')
    $store  = _ReadWebhooksStore -WorkspaceRoot $WorkspaceRoot
    $fired  = [System.Collections.Generic.List[pscustomobject]]::new()
    $dirty  = $false

    $body = @{
        event   = $EventName
        payload = $EventPayload
        sentAt  = $now
    } | ConvertTo-Json -Depth 10 -Compress

    foreach ($webhook in $store.webhooks) {
        # Only dispatch to enabled webhooks subscribed to this event
        if (-not $webhook.enabled) { continue }
        $webhookEvents = if ($null -ne $webhook.events -and $webhook.events -is [array]) { $webhook.events } else { @() }
        $subscribed = @($webhookEvents | Where-Object { $_ -eq $EventName })
        if (-not $subscribed) { continue }

        $result = [pscustomobject]@{ webhookId = $webhook.id; success = $false; error = $null }

        try {
            $response = Invoke-RestMethod `
                -Uri         $webhook.url `
                -Method      Post `
                -Body        $body `
                -ContentType 'application/json' `
                -TimeoutSec  10 `
                -ErrorAction Stop

            $result.success = $true

            # Update webhook metadata
            $idx = [array]::IndexOf($store.webhooks, $webhook)
            if ($idx -ge 0) {
                $store.webhooks[$idx] = [pscustomobject]@{
                    id             = $webhook.id
                    url            = $webhook.url
                    label          = $webhook.label
                    events         = $webhook.events
                    registeredAt   = $webhook.registeredAt
                    enabled        = $webhook.enabled
                    lastFiredAt    = $now
                    lastFireResult = 'success'
                }
                $dirty = $true
            }
        } catch {
            $errorMsg      = $_.ToString()
            $result.error  = $errorMsg

            $idx = [array]::IndexOf($store.webhooks, $webhook)
            if ($idx -ge 0) {
                $store.webhooks[$idx] = [pscustomobject]@{
                    id             = $webhook.id
                    url            = $webhook.url
                    label          = $webhook.label
                    events         = $webhook.events
                    registeredAt   = $webhook.registeredAt
                    enabled        = $webhook.enabled
                    lastFiredAt    = $now
                    lastFireResult = "error: $errorMsg"
                }
                $dirty = $true
            }
        }

        $fired.Add($result)
    }

    # Persist updated lastFiredAt / lastFireResult
    if ($dirty) {
        try {
            _WriteWebhooksStore -WorkspaceRoot $WorkspaceRoot -Store $store
        } catch {
            Write-Warning "NotificationHub: webhook metadata (lastFiredAt/lastFireResult) could not be persisted: $_"
        }
    }

    return [pscustomobject]@{
        fired     = $fired.ToArray()
        eventName = $EventName
        sentAt    = $now
    }
}

