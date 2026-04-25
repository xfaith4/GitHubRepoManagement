import React from 'react';
import { InitIcon, UpdateIcon, SyncIcon, ExportIcon, ArchiveIcon, RefreshIcon, SettingsIcon, SpinnerIcon, DocReviewIcon, RoadmapIcon, ApiDocsIcon, HelpIcon } from './icons';
import { type OperationType, type AppSettings } from '../types';

interface ActionBarProps {
  onAction: (operation: OperationType, repoNames?: string[]) => void;
  onExport: () => void;
  onRefresh: () => void;
  onSettingsClick: () => void;
  onInitClick: () => void;
  onDocReviewClick: () => void;
  onApiDocsClick: () => void;
  onHelpClick: () => void;
  isActionRunning: boolean;
  currentOperation: OperationType | null;
  settings: AppSettings | null;
  selectedRepos: Set<string>;
}

interface ActionButtonProps {
    onClick: () => void;
    disabled: boolean;
    isLoading?: boolean;
    title: string;
    icon: React.ReactNode;
    children?: React.ReactNode;
}

const ActionButton: React.FC<ActionButtonProps> = ({ onClick, disabled, isLoading, title, icon, children }) => (
    <button
        onClick={onClick}
        disabled={disabled || !!isLoading}
        title={title}
        className="flex items-center justify-center sm:justify-start gap-2 px-4 py-2 text-sm font-medium rounded-md transition-colors bg-gray-700 text-gray-200 hover:bg-gray-600 disabled:opacity-50 disabled:cursor-not-allowed"
    >
        <div className="w-4 h-4 flex-shrink-0">{isLoading ? <SpinnerIcon className="w-4 h-4" /> : icon}</div>
        {children}
    </button>
);


const ActionBar: React.FC<ActionBarProps> = ({ onAction, onExport, onRefresh, onSettingsClick, onInitClick, onDocReviewClick, onApiDocsClick, onHelpClick, isActionRunning, currentOperation, settings, selectedRepos }) => {
    
    const selection = selectedRepos.size > 0 ? Array.from(selectedRepos) : undefined;
    const selectionCount = selectedRepos.size;
    const cloneImplemented = false;
    const archiveImplemented = false;

    const getButtonText = (baseText: string) => {
        if (selectionCount > 0) {
            return `${baseText} (${selectionCount})`;
        }
        return <span className="hidden sm:inline">{baseText}</span>;
    };
    
    const handleUpdate = () => onAction('update', selection);
    const handleSync = () => onAction('sync', selection);
    
    const handleArchive = () => {
        if (!archiveImplemented) return;
        const repoList = selectionCount > 0 ? `${selectionCount} selected repos` : 'all inactive repos';
        if (settings && window.confirm(`This will archive ${repoList} inactive for over ${settings.daysInactive} days (local operation). Are you sure?`)) {
            onAction('archive', selection);
        }
    };

    return (
        <div className="p-4 border-b border-gray-700 flex flex-wrap items-center gap-3">
            <div className="flex flex-wrap gap-3 flex-grow">
                 <ActionButton onClick={onInitClick} disabled={isActionRunning || !cloneImplemented} isLoading={currentOperation === 'init'} title={cloneImplemented ? "Clone repositories from GitHub into a local workspace (git clone via local backend)." : "Planned: clone repositories from GitHub into a local workspace (not implemented in this build)."} icon={<InitIcon className="w-4 h-4" />}>
                    <span className="hidden sm:inline">{cloneImplemented ? 'Clone' : 'Clone (Planned)'}</span>
                </ActionButton>
                <ActionButton onClick={handleUpdate} disabled={isActionRunning} isLoading={currentOperation === 'update'} title={`Run 'git pull' on ${selectionCount > 0 ? selectionCount + ' selected' : 'all active'} repositories.`} icon={<UpdateIcon className="w-4 h-4" />}>
                    {getButtonText('Pull')}
                </ActionButton>
                <ActionButton onClick={handleSync} disabled={isActionRunning} isLoading={currentOperation === 'sync'} title={`Run 'git fetch --all --prune' on ${selectionCount > 0 ? selectionCount + ' selected' : 'all'} repositories.`} icon={<SyncIcon className="w-4 h-4" />}>
                    {getButtonText('Fetch')}
                </ActionButton>
                <ActionButton onClick={onExport} disabled={isActionRunning} isLoading={currentOperation === 'export'} title={`Generate timestamped report files in the repo-local reports folder and open the HTML report in a new tab for ${selectionCount > 0 ? selectionCount + ' selected' : 'all'} repositories.`} icon={<ExportIcon className="w-4 h-4" />}>
                    {getButtonText('Report')}
                </ActionButton>
                <ActionButton onClick={onDocReviewClick} disabled={isActionRunning} isLoading={currentOperation === 'docreview'} title="Run Doc Review Inventory, queue planning, and optional repo batch plan generation." icon={<DocReviewIcon className="w-4 h-4" />}>
                    <span className="hidden sm:inline">Doc Review</span>
                </ActionButton>
                <ActionButton onClick={() => onAction('roadmap-scan')} disabled={isActionRunning} isLoading={currentOperation === 'roadmap-scan'} title="Scan all repositories for ROADMAP files and update the index." icon={<RoadmapIcon className="w-4 h-4" />}>
                    <span className="hidden sm:inline">Roadmap Scan</span>
                </ActionButton>
                 <ActionButton onClick={handleArchive} disabled={isActionRunning || !settings || !archiveImplemented} isLoading={currentOperation === 'archive'} title={archiveImplemented ? `Archive ${selectionCount > 0 ? selectionCount + ' selected' : 'all'} repositories inactive for over ${settings?.daysInactive ?? 'N/A'} days (local).` : 'Planned: archive inactive repositories (not implemented in this build).'} icon={<ArchiveIcon className="w-4 h-4" />}>
                    {getButtonText(archiveImplemented ? 'Archive' : 'Archive (Planned)')}
                </ActionButton>
            </div>
            <div className="flex gap-3">
                 <ActionButton onClick={onHelpClick} disabled={false} title="Open the end-to-end user guide for this application." icon={<HelpIcon className="w-4 h-4" />}>
                    <span className="hidden sm:inline">Help</span>
                 </ActionButton>
                 <ActionButton onClick={onApiDocsClick} disabled={false} title="View API reference documentation for all backend endpoints." icon={<ApiDocsIcon className="w-4 h-4" />} />
                 <ActionButton onClick={onRefresh} disabled={isActionRunning} title="Refresh the current view." icon={<RefreshIcon className="w-4 h-4" />} />
                 <ActionButton onClick={onSettingsClick} disabled={isActionRunning} title="Configure local workspace settings (path, scan depth, thresholds)." icon={<SettingsIcon className="w-4 h-4" />} />
            </div>
        </div>
    );
};

export default ActionBar;
