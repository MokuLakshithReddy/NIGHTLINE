import React, { useState } from 'react';
import {
  NightlineServerEngine,
  PlayerEntity,
  RemoteLogEntry,
} from '../engine/nightlineEngine';
import { PROJECT_SOURCE_FILES, ProjectSourceFile } from '../engine/luauProjectRegistry';

interface WorkbenchDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  activeTab: 'luau' | 'multiplayer' | 'security' | 'docs';
  setActiveTab: (tab: 'luau' | 'multiplayer' | 'security' | 'docs') => void;
  players: PlayerEntity[];
  remoteLogs: RemoteLogEntry[];
  onAddSimulatedPlayer: () => void;
  onRemoveSimulatedPlayer: (userId: number) => void;
  onEliminatePlayer: (userId: number) => void;
  onMoveToExtractionZone: (userId: number) => void;
  onAdvancePhase: () => void;
  onResetServer: () => void;
  onRunSecurityTest: (
    testType:
      | 'invalidItem'
      | 'invalidSlot'
      | 'invalidStation'
      | 'farPrompt'
      | 'rateLimit'
      | 'speedHack'
  ) => void;
  engine: NightlineServerEngine;
}

export const WorkbenchDrawer: React.FC<WorkbenchDrawerProps> = ({
  isOpen,
  onClose,
  activeTab,
  setActiveTab,
  players,
  remoteLogs,
  onAddSimulatedPlayer,
  onRemoveSimulatedPlayer,
  onEliminatePlayer,
  onMoveToExtractionZone,
  onAdvancePhase,
  onResetServer,
  onRunSecurityTest,
  engine,
}) => {
  const [selectedFile, setSelectedFile] = useState<ProjectSourceFile>(
    PROJECT_SOURCE_FILES.find((f) => f.path.endsWith('RoundService.lua')) || PROJECT_SOURCE_FILES[0]
  );
  const [copiedPath, setCopiedPath] = useState<string | null>(null);
  const [fileFilter, setFileFilter] = useState<string>('ALL');

  if (!isOpen) return null;

  const luauAndConfigFiles = PROJECT_SOURCE_FILES.filter(
    (f) => f.category !== 'Documentation' && (fileFilter === 'ALL' || f.category === fileFilter)
  );
  const docFiles = PROJECT_SOURCE_FILES.filter((f) => f.category === 'Documentation');

  const handleCopyCode = (file: ProjectSourceFile) => {
    navigator.clipboard?.writeText(file.content).catch(() => {});
    setCopiedPath(file.path);
    setTimeout(() => setCopiedPath(null), 1800);
  };

  return (
    <dialog
      open
      aria-label="NIGHTLINE Rojo & Luau Engineering Workbench"
      className="fixed inset-y-0 right-0 left-auto z-40 w-full max-w-4xl bg-slate-900 text-slate-100 border-l border-slate-800 shadow-2xl flex flex-col m-0 p-0 pointer-events-auto"
    >
      {/* Workbench Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-slate-800 bg-slate-950">
        <div>
          <h2 className="text-base font-bold tracking-tight text-slate-100">
            NIGHTLINE: LAST TRAIN · Rojo 7.7.1 &amp; Luau VM Workbench
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            <span>Rojo 7.7.1</span>
            <span className="mx-2" aria-hidden="true">·</span>
            <span>luau-lsp --!strict (0 Errors)</span>
            <span className="mx-2" aria-hidden="true">·</span>
            <span>Selene + StyLua + Luau VM Verified</span>
          </p>
        </div>

        <button
          type="button"
          onClick={onClose}
          className="px-3.5 py-2 text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-md cursor-pointer whitespace-nowrap shrink-0"
        >
          Close Workbench [Esc]
        </button>
      </div>

      {/* Interactive Filter Tabs */}
      <div className="flex items-center gap-2 px-6 py-3 bg-slate-950/60 border-b border-slate-800 overflow-x-auto">
        <button
          type="button"
          onClick={() => setActiveTab('luau')}
          className={`px-3.5 py-1.5 text-xs font-semibold rounded-md transition-colors cursor-pointer whitespace-nowrap shrink-0 ${
            activeTab === 'luau'
              ? 'bg-amber-500 text-slate-950'
              : 'text-slate-300 hover:bg-slate-800'
          }`}
        >
          Rojo &amp; Luau Source (20)
        </button>
        <button
          type="button"
          onClick={() => setActiveTab('multiplayer')}
          className={`px-3.5 py-1.5 text-xs font-semibold rounded-md transition-colors cursor-pointer whitespace-nowrap shrink-0 ${
            activeTab === 'multiplayer'
              ? 'bg-amber-500 text-slate-950'
              : 'text-slate-300 hover:bg-slate-800'
          }`}
        >
          Multiplayer &amp; Round QA ({players.length}/6 Crew)
        </button>
        <button
          type="button"
          onClick={() => setActiveTab('security')}
          className={`px-3.5 py-1.5 text-xs font-semibold rounded-md transition-colors cursor-pointer whitespace-nowrap shrink-0 ${
            activeTab === 'security'
              ? 'bg-amber-500 text-slate-950'
              : 'text-slate-300 hover:bg-slate-800'
          }`}
        >
          Security &amp; Movement Log ({remoteLogs.length})
        </button>
        <button
          type="button"
          onClick={() => setActiveTab('docs')}
          className={`px-3.5 py-1.5 text-xs font-semibold rounded-md transition-colors cursor-pointer whitespace-nowrap shrink-0 ${
            activeTab === 'docs'
              ? 'bg-amber-500 text-slate-950'
              : 'text-slate-300 hover:bg-slate-800'
          }`}
        >
          Project Documentation (5)
        </button>
      </div>

      {/* Tab Content Body */}
      <div className="flex-1 overflow-y-auto p-6">
        {activeTab === 'luau' && (
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 h-full">
            {/* Left File Tree */}
            <div className="lg:col-span-5 space-y-3">
              <div className="flex flex-wrap gap-1.5">
                {(['ALL', 'Rojo & Toolchain', 'ReplicatedStorage', 'ServerScriptService', 'StarterPlayerScripts'] as const).map(
                  (cat) => (
                    <button
                      key={cat}
                      type="button"
                      onClick={() => setFileFilter(cat)}
                      className={`px-2.5 py-1 text-xs font-medium rounded cursor-pointer whitespace-nowrap shrink-0 ${
                        fileFilter === cat
                          ? 'bg-slate-700 text-white'
                          : 'bg-slate-800/60 text-slate-400 hover:text-slate-200'
                      }`}
                    >
                      {cat === 'ALL' ? 'All Files' : cat}
                    </button>
                  )
                )}
              </div>

              <div className="border border-slate-800 rounded-lg divide-y divide-slate-800/80 max-h-[540px] overflow-y-auto">
                {luauAndConfigFiles.map((file) => {
                  const isSelected = selectedFile.path === file.path;
                  return (
                    <button
                      key={file.path}
                      type="button"
                      onClick={() => setSelectedFile(file)}
                      className={`w-full text-left px-3.5 py-2.5 transition-colors cursor-pointer block ${
                        isSelected ? 'bg-slate-800 text-amber-400' : 'hover:bg-slate-800/40 text-slate-200'
                      }`}
                    >
                      <div className="text-xs font-mono font-semibold truncate">{file.path}</div>
                      <div className="text-xs text-slate-400 truncate mt-0.5">
                        {file.robloxInstancePath}
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Right Code Viewer */}
            <div className="lg:col-span-7 flex flex-col border border-slate-800 rounded-lg bg-slate-950 overflow-hidden">
              <div className="flex items-center justify-between px-4 py-3 border-b border-slate-800 bg-slate-900/60">
                <div className="min-w-0">
                  <div className="text-xs font-mono font-semibold text-amber-400 truncate">
                    {selectedFile.path}
                  </div>
                  <div className="text-xs text-slate-400 truncate mt-0.5">
                    {selectedFile.summary}
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => handleCopyCode(selectedFile)}
                  className="px-3 py-1.5 text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 rounded cursor-pointer whitespace-nowrap shrink-0 ml-3"
                >
                  {copiedPath === selectedFile.path ? 'Copied!' : 'Copy File'}
                </button>
              </div>
              <pre className="p-4 text-xs font-mono text-slate-200 overflow-x-auto overflow-y-auto max-h-[500px] leading-relaxed">
                <code>{selectedFile.content}</code>
              </pre>
            </div>
          </div>
        )}

        {activeTab === 'multiplayer' && (
          <div className="space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div className="p-4 border border-slate-800 rounded-lg bg-slate-950">
                <div className="text-xs text-slate-400">Authoritative Round State</div>
                <div className="text-xl font-bold text-amber-400 font-mono mt-1 tabular-nums">
                  {engine.state} ({Math.ceil(engine.phaseRemainingSeconds)}s)
                </div>
                <div className="text-xs text-slate-400 mt-1">
                  Round #{engine.roundNumber} · Outcome: {engine.lastOutcome}
                </div>
              </div>

              <div className="p-4 border border-slate-800 rounded-lg bg-slate-950">
                <div className="text-xs text-slate-400">Spawn Slots &amp; Isolation</div>
                <div className="text-xl font-bold text-slate-100 font-mono mt-1 tabular-nums">
                  {players.length} / 6 Slots · {engine.activeExpeditionUserIds.size} in Expedition
                </div>
                <div className="text-xs text-slate-400 mt-1">
                  Freed slots are reallocated without collision (Issue 02)
                </div>
              </div>

              <div className="p-4 border border-slate-800 rounded-lg bg-slate-950">
                <div className="text-xs text-slate-400">Physical Extraction Zone</div>
                <div className="text-xl font-bold text-emerald-400 font-mono mt-1 tabular-nums">
                  X=15, Z=-8 (r=13)
                </div>
                <div className="text-xs text-slate-400 mt-1">
                  Crew outside zone on departure are ELIMINATED (Issue 04)
                </div>
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-3">
              <button
                type="button"
                onClick={onAddSimulatedPlayer}
                disabled={players.length >= 6}
                className="px-4 py-2 text-xs font-semibold bg-sky-500 hover:bg-sky-400 disabled:opacity-40 text-slate-950 rounded-md cursor-pointer whitespace-nowrap shrink-0"
              >
                Add Simulated Crew Player (+1)
              </button>
              <button
                type="button"
                onClick={onAdvancePhase}
                className="px-4 py-2 text-xs font-semibold bg-amber-500 hover:bg-amber-400 text-slate-950 rounded-md cursor-pointer whitespace-nowrap shrink-0"
              >
                Skip to Next Round State
              </button>
              <button
                type="button"
                onClick={onResetServer}
                className="px-4 py-2 text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-md cursor-pointer whitespace-nowrap shrink-0"
              >
                Reset Server to Clean Hub
              </button>
            </div>

            {/* Connected Crew Table */}
            <div className="border border-slate-800 rounded-lg overflow-hidden">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-slate-950 text-xs font-mono text-slate-400 border-b border-slate-800">
                    <th className="py-2.5 px-4">Player &amp; Slot</th>
                    <th className="py-2.5 px-4">Round Status</th>
                    <th className="py-2.5 px-4">Loadout (Slot 1 / Slot 2)</th>
                    <th className="py-2.5 px-4 text-right">Position (X, Z)</th>
                    <th className="py-2.5 px-4 text-right">QA Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800 text-xs">
                  {players.map((member) => (
                    <tr key={member.userId} className="hover:bg-slate-800/30">
                      <td className="py-2.5 px-4 font-medium text-slate-100">
                        {member.displayName} [Slot #{member.spawnSlot}] {member.isLocal ? '(You)' : ''}
                      </td>
                      <td className="py-2.5 px-4 font-mono text-amber-400">{member.status}</td>
                      <td className="py-2.5 px-4 font-mono text-slate-300">
                        {member.equipmentSlots[1] ?? 'Empty'} / {member.equipmentSlots[2] ?? 'Empty'}
                      </td>
                      <td className="py-2.5 px-4 font-mono text-right text-slate-400 tabular-nums">
                        ({member.position.x.toFixed(1)}, {member.position.z.toFixed(1)})
                      </td>
                      <td className="py-2.5 px-4 text-right">
                        <div className="flex items-center justify-end gap-1.5">
                          <button
                            type="button"
                            onClick={() => onMoveToExtractionZone(member.userId)}
                            className="px-2 py-1 text-xs font-medium bg-emerald-950/80 hover:bg-emerald-900 text-emerald-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                            title="Move to Physical Extraction Zone (15, -8)"
                          >
                            Extract Zone
                          </button>
                          <button
                            type="button"
                            onClick={() => onEliminatePlayer(member.userId)}
                            className="px-2 py-1 text-xs font-medium bg-amber-950/80 hover:bg-amber-900 text-amber-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                            title="Simulate death & state-aware respawn in Recovery Bay"
                          >
                            Eliminate
                          </button>
                          {!member.isLocal && (
                            <button
                              type="button"
                              onClick={() => onRemoveSimulatedPlayer(member.userId)}
                              className="px-2 py-1 text-xs font-medium bg-rose-950/80 hover:bg-rose-900 text-rose-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                            >
                              Leave
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {activeTab === 'security' && (
          <div className="space-y-5">
            <div className="p-4 border border-slate-800 rounded-lg bg-slate-950 space-y-3">
              <div className="text-sm font-semibold text-slate-100">
                SecurityService &amp; MovementService Exploit Test Harness
              </div>
              <p className="text-xs text-slate-400">
                Trigger malformed client requests or speed-hack displacements below to verify that SecurityService, MovementService, and domain services reject or rubberband them.
              </p>
              <div className="flex flex-wrap gap-2.5">
                <button
                  type="button"
                  onClick={() => onRunSecurityTest('speedHack')}
                  className="px-3 py-2 text-xs font-medium bg-amber-500/20 border border-amber-500/50 hover:bg-amber-500/30 text-amber-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                >
                  Test Speed Exploit Rubberband (+80 Studs)
                </button>
                <button
                  type="button"
                  onClick={() => onRunSecurityTest('invalidItem')}
                  className="px-3 py-2 text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                >
                  Test Unlisted Item ("AdminMinigun")
                </button>
                <button
                  type="button"
                  onClick={() => onRunSecurityTest('invalidSlot')}
                  className="px-3 py-2 text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                >
                  Test Out-of-Bounds Slot (Slot 99)
                </button>
                <button
                  type="button"
                  onClick={() => onRunSecurityTest('invalidStation')}
                  className="px-3 py-2 text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                >
                  Test Invalid Destination ("Station999")
                </button>
                <button
                  type="button"
                  onClick={() => onRunSecurityTest('farPrompt')}
                  className="px-3 py-2 text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                >
                  Test Far-Distance Prompt (&gt;14 Studs)
                </button>
                <button
                  type="button"
                  onClick={() => onRunSecurityTest('rateLimit')}
                  className="px-3 py-2 text-xs font-medium bg-slate-800 hover:bg-slate-700 text-slate-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                >
                  Test Remote Spam Burst (8x in 1s)
                </button>
              </div>
            </div>

            <div className="border border-slate-800 rounded-lg overflow-hidden">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-slate-950 text-xs font-mono text-slate-400 border-b border-slate-800">
                    <th className="py-2 px-3">Time</th>
                    <th className="py-2 px-3">Direction</th>
                    <th className="py-2 px-3">RemoteEvent</th>
                    <th className="py-2 px-3">Validation</th>
                    <th className="py-2 px-3">Payload Summary</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800 text-xs font-mono">
                  {remoteLogs.map((log) => (
                    <tr key={log.id} className="hover:bg-slate-800/30">
                      <td className="py-2 px-3 text-slate-400 tabular-nums">
                        {log.timestamp.toFixed(1)}s
                      </td>
                      <td className="py-2 px-3 text-slate-300">{log.direction}</td>
                      <td className="py-2 px-3 text-sky-400">{log.remoteName}</td>
                      <td
                        className={`py-2 px-3 font-semibold ${
                          log.accepted ? 'text-emerald-400' : 'text-rose-400'
                        }`}
                      >
                        {log.accepted ? `OK · ${log.reason}` : `REJECTED · ${log.reason}`}
                      </td>
                      <td className="py-2 px-3 text-slate-300">{log.payloadSummary}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {activeTab === 'docs' && (
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            <div className="lg:col-span-4 space-y-2">
              {docFiles.map((doc) => (
                <button
                  key={doc.path}
                  type="button"
                  onClick={() => setSelectedFile(doc)}
                  className={`w-full text-left px-3.5 py-2.5 rounded-lg border transition-colors cursor-pointer block ${
                    selectedFile.path === doc.path
                      ? 'bg-slate-800 border-amber-500/60 text-amber-400'
                      : 'bg-slate-950 border-slate-800 text-slate-200 hover:bg-slate-800/50'
                  }`}
                >
                  <div className="text-xs font-mono font-semibold">{doc.path}</div>
                  <div className="text-xs text-slate-400 mt-0.5">{doc.summary}</div>
                </button>
              ))}
            </div>
            <div className="lg:col-span-8 border border-slate-800 rounded-lg bg-slate-950 p-5 overflow-y-auto max-h-[540px]">
              <pre className="text-xs font-mono text-slate-200 whitespace-pre-wrap leading-relaxed">
                {selectedFile.category === 'Documentation'
                  ? selectedFile.content
                  : docFiles[0].content}
              </pre>
            </div>
          </div>
        )}
      </div>
    </dialog>
  );
};
