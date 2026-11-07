import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  NightlineServerEngine,
  MISSION_TEMPLATES,
  HubInteractable,
  HUB_INTERACTABLES,
  PlayerEntity,
  NotificationEntry,
  RemoteLogEntry,
  RoundState,
} from './engine/nightlineEngine';
import { TitleScreenOverlay } from './components/TitleScreenOverlay';
import { TrainHubCanvas } from './components/TrainHubCanvas';
import { WorkbenchDrawer } from './components/WorkbenchDrawer';

const LOCAL_USER_ID = 101;
const CREW_CALLSIGNS = ['Avery', 'Morgan', 'Vance', 'Sloane', 'Kael', 'Reyes'];

function playProceduralCue(
  audioCtxRef: React.MutableRefObject<AudioContext | null>,
  isMuted: boolean,
  type: 'click' | 'equip' | 'board' | 'horn' | 'reject'
) {
  if (isMuted || typeof window === 'undefined') return;
  try {
    const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (!AudioCtx) return;
    if (!audioCtxRef.current) {
      audioCtxRef.current = new AudioCtx();
    }
    const ctx = audioCtxRef.current;
    if (ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }

    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);

    const now = ctx.currentTime;
    if (type === 'equip') {
      osc.type = 'triangle';
      osc.frequency.setValueAtTime(520, now);
      osc.frequency.exponentialRampToValueAtTime(760, now + 0.09);
      gain.gain.setValueAtTime(0.08, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.1);
      osc.start(now);
      osc.stop(now + 0.1);
    } else if (type === 'board') {
      osc.type = 'sine';
      osc.frequency.setValueAtTime(440, now);
      osc.frequency.exponentialRampToValueAtTime(660, now + 0.14);
      gain.gain.setValueAtTime(0.1, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.15);
      osc.start(now);
      osc.stop(now + 0.15);
    } else if (type === 'horn') {
      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(146, now);
      osc.frequency.setValueAtTime(196, now + 0.12);
      gain.gain.setValueAtTime(0.09, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);
      osc.start(now);
      osc.stop(now + 0.35);
    } else if (type === 'reject') {
      osc.type = 'square';
      osc.frequency.setValueAtTime(180, now);
      osc.frequency.exponentialRampToValueAtTime(120, now + 0.12);
      gain.gain.setValueAtTime(0.07, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.12);
      osc.start(now);
      osc.stop(now + 0.12);
    } else {
      osc.type = 'sine';
      osc.frequency.setValueAtTime(600, now);
      gain.gain.setValueAtTime(0.05, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);
      osc.start(now);
      osc.stop(now + 0.05);
    }
  } catch {
    // Ignore audio context restrictions in headless environments
  }
}

export default function App() {
  const initialAutostart =
    typeof window !== 'undefined' &&
    new URLSearchParams(window.location.search).get('autostart') === '1';

  const [shellState, setShellState] = useState<'title' | 'playing' | 'paused' | 'gameover'>(
    initialAutostart ? 'playing' : 'title'
  );
  const [simSpeed, setSimSpeed] = useState<number>(1);
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [isWorkbenchOpen, setIsWorkbenchOpen] = useState<boolean>(false);
  const [workbenchTab, setWorkbenchTab] = useState<'luau' | 'multiplayer' | 'security' | 'docs'>(
    'luau'
  );

  const engineRef = useRef<NightlineServerEngine | null>(null);
  if (!engineRef.current) {
    const server = new NightlineServerEngine();
    server.addPlayer(LOCAL_USER_ID, CREW_CALLSIGNS[0], true);
    engineRef.current = server;
  }

  const simSpeedRef = useRef<number>(1);
  const isPausedRef = useRef<boolean>(!initialAutostart);
  const audioCtxRef = useRef<AudioContext | null>(null);
  const nextBotIndexRef = useRef<number>(1);

  const [hudSnapshot, setHudSnapshot] = useState<{
    state: RoundState;
    roundNumber: number;
    remainingSeconds: number;
    missionId: keyof typeof MISSION_TEMPLATES;
    players: PlayerEntity[];
    latestNotification: NotificationEntry | null;
    remoteLogs: RemoteLogEntry[];
  }>(() => {
    const srv = engineRef.current!;
    return {
      state: srv.state,
      roundNumber: srv.roundNumber,
      remainingSeconds: srv.phaseRemainingSeconds,
      missionId: srv.selectedMissionId,
      players: Array.from(srv.players.values()).map((p) => ({
        ...p,
        equipmentSlots: { ...p.equipmentSlots },
      })),
      latestNotification: srv.notifications[0] ?? null,
      remoteLogs: [...srv.remoteLogs],
    };
  });

  const [nearestPrompt, setNearestPrompt] = useState<{
    prompt: HubInteractable | null;
    distance: number;
  }>({ prompt: null, distance: 99 });

  const syncHudFromEngine = useCallback(() => {
    const srv = engineRef.current;
    if (!srv) return;
    setHudSnapshot({
      state: srv.state,
      roundNumber: srv.roundNumber,
      remainingSeconds: srv.phaseRemainingSeconds,
      missionId: srv.selectedMissionId,
      players: Array.from(srv.players.values()).map((p) => ({
        ...p,
        position: { ...p.position },
        equipmentSlots: { ...p.equipmentSlots },
      })),
      latestNotification: srv.notifications[0] ?? null,
      remoteLogs: [...srv.remoteLogs],
    });
  }, []);

  useEffect(() => {
    document.body.dataset.state = shellState;
    isPausedRef.current = shellState !== 'playing';
  }, [shellState]);

  useEffect(() => {
    simSpeedRef.current = simSpeed;
  }, [simSpeed]);

  const handleStartGame = useCallback(() => {
    setShellState('playing');
    isPausedRef.current = false;
    playProceduralCue(audioCtxRef, isMuted, 'board');
    syncHudFromEngine();
  }, [isMuted, syncHudFromEngine]);

  const handleEquipSlot = useCallback(
    (slotIndex: 1 | 2, itemId: 'Flashlight' | 'Flare') => {
      const srv = engineRef.current;
      if (!srv) return;
      const res = srv.handleEquipmentRequest(LOCAL_USER_ID, slotIndex, itemId);
      playProceduralCue(audioCtxRef, isMuted, res.ok ? 'equip' : 'reject');
      syncHudFromEngine();
    },
    [isMuted, syncHudFromEngine]
  );

  const handleConfirmDestination = useCallback(() => {
    const srv = engineRef.current;
    if (!srv) return;
    const res = srv.handleDestinationVote(LOCAL_USER_ID, 'Station001');
    playProceduralCue(audioCtxRef, isMuted, res.ok ? 'click' : 'reject');
    syncHudFromEngine();
  }, [isMuted, syncHudFromEngine]);

  const handleToggleReady = useCallback(() => {
    const srv = engineRef.current;
    if (!srv) return;
    const res = srv.togglePlayerBoardingReady(LOCAL_USER_ID);
    playProceduralCue(audioCtxRef, isMuted, res.ok ? 'board' : 'reject');
    syncHudFromEngine();
  }, [isMuted, syncHudFromEngine]);

  const handleTriggerPrompt = useCallback(
    (interactableId: string) => {
      const srv = engineRef.current;
      if (!srv) return;
      const res = srv.handleProximityPromptTriggered(LOCAL_USER_ID, interactableId);
      playProceduralCue(audioCtxRef, isMuted, res.ok ? 'equip' : 'reject');
      syncHudFromEngine();
    },
    [isMuted, syncHudFromEngine]
  );

  const handleWalkToStationTerminal = useCallback(
    (interactableId: string) => {
      const srv = engineRef.current;
      if (!srv) return;
      const localPlayer = srv.players.get(LOCAL_USER_ID);
      const target = HUB_INTERACTABLES.find((i) => i.id === interactableId);
      if (!localPlayer || !target) return;

      // Move character inside valid range of the terminal inside the Train Hub and trigger the server prompt
      localPlayer.position = {
        x: Math.max(-7.2, Math.min(7.2, target.position.x)),
        z: target.position.z + (target.position.z < -30 ? 3.5 : 0),
      };
      srv.stepSimulation(0.6);
      const res = srv.handleProximityPromptTriggered(LOCAL_USER_ID, interactableId);
      playProceduralCue(audioCtxRef, isMuted, res.ok ? 'equip' : 'reject');
      syncHudFromEngine();
    },
    [isMuted, syncHudFromEngine]
  );

  const handleAddSimulatedPlayer = useCallback(() => {
    const srv = engineRef.current;
    if (!srv) return;
    const idx = nextBotIndexRef.current;
    nextBotIndexRef.current += 1;
    const callsign = CREW_CALLSIGNS[idx % CREW_CALLSIGNS.length];
    const newId = 100 + idx + 1;
    srv.addPlayer(newId, `${callsign}-${idx}`);
    playProceduralCue(audioCtxRef, isMuted, 'board');
    syncHudFromEngine();
  }, [isMuted, syncHudFromEngine]);

  const handleRemoveSimulatedPlayer = useCallback(
    (userId: number) => {
      const srv = engineRef.current;
      if (!srv) return;
      srv.removePlayer(userId);
      playProceduralCue(audioCtxRef, isMuted, 'click');
      syncHudFromEngine();
    },
    [isMuted, syncHudFromEngine]
  );

  const handleEliminatePlayer = useCallback(
    (userId: number) => {
      const srv = engineRef.current;
      if (!srv) return;
      const res = srv.eliminatePlayer(userId, 'HollowStrike');
      playProceduralCue(audioCtxRef, isMuted, res.ok ? 'reject' : 'click');
      syncHudFromEngine();
    },
    [isMuted, syncHudFromEngine]
  );

  const handleMoveToExtractionZone = useCallback(
    (userId: number) => {
      const srv = engineRef.current;
      if (!srv) return;
      const res = srv.movePlayerToExtractionZone(userId);
      playProceduralCue(audioCtxRef, isMuted, res.ok ? 'board' : 'reject');
      syncHudFromEngine();
    },
    [isMuted, syncHudFromEngine]
  );

  const handleAdvancePhase = useCallback(() => {
    const srv = engineRef.current;
    if (!srv) return;
    srv.advanceToNextPhase();
    playProceduralCue(audioCtxRef, isMuted, 'horn');
    syncHudFromEngine();
  }, [isMuted, syncHudFromEngine]);

  const handleResetServer = useCallback(() => {
    const srv = engineRef.current;
    if (!srv) return;
    srv.resetServer();
    srv.addPlayer(LOCAL_USER_ID, CREW_CALLSIGNS[0], true);
    setShellState('playing');
    playProceduralCue(audioCtxRef, isMuted, 'click');
    syncHudFromEngine();
  }, [isMuted, syncHudFromEngine]);

  const handleRunSecurityTest = useCallback(
    (
      testType:
        | 'invalidItem'
        | 'invalidSlot'
        | 'invalidStation'
        | 'farPrompt'
        | 'rateLimit'
        | 'speedHack'
    ) => {
      const srv = engineRef.current;
      if (!srv) return;
      srv.stepSimulation(1.0);

      if (testType === 'speedHack') {
        const p = srv.players.get(LOCAL_USER_ID);
        if (p) {
          srv.validatePlayerMovement(
            LOCAL_USER_ID,
            { x: p.position.x, z: p.position.z - 80 },
            0.25
          );
        }
      } else if (testType === 'invalidItem') {
        srv.handleEquipmentRequest(LOCAL_USER_ID, 1, 'AdminMinigun');
      } else if (testType === 'invalidSlot') {
        srv.handleEquipmentRequest(LOCAL_USER_ID, 99, 'Flashlight');
      } else if (testType === 'invalidStation') {
        srv.handleDestinationVote(LOCAL_USER_ID, 'Station999');
      } else if (testType === 'farPrompt') {
        const p = srv.players.get(LOCAL_USER_ID);
        if (p) {
          p.position = { x: 0, z: 32 }; // 66 studs away from DestinationConsole at z=-34
        }
        srv.handleProximityPromptTriggered(LOCAL_USER_ID, 'DestinationConsole');
      } else if (testType === 'rateLimit') {
        for (let i = 0; i < 8; i++) {
          srv.handleDestinationVote(LOCAL_USER_ID, 'Station001');
        }
      }

      playProceduralCue(audioCtxRef, isMuted, 'reject');
      syncHudFromEngine();
    },
    [isMuted, syncHudFromEngine]
  );

  // Global keyboard bindings for Title handshake, Pause, Slots 1/2, Mute, Reset
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (
        document.activeElement &&
        (document.activeElement.tagName === 'INPUT' ||
          document.activeElement.tagName === 'TEXTAREA')
      ) {
        return;
      }

      if (shellState === 'title') {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          handleStartGame();
        }
        return;
      }

      if (e.key === 'Escape') {
        if (isWorkbenchOpen) {
          setIsWorkbenchOpen(false);
          return;
        }
        setShellState((prev) => (prev === 'playing' ? 'paused' : 'playing'));
        return;
      }

      const lower = e.key.toLowerCase();
      if (lower === 'p') {
        setShellState((prev) => (prev === 'playing' ? 'paused' : 'playing'));
      } else if (lower === 'm') {
        setIsMuted((prev) => !prev);
      } else if (lower === 'r' && shellState === 'playing') {
        handleResetServer();
      } else if (e.key === '1' && shellState === 'playing') {
        handleEquipSlot(1, 'Flashlight');
      } else if (e.key === '2' && shellState === 'playing') {
        handleEquipSlot(2, 'Flare');
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [
    handleEquipSlot,
    handleResetServer,
    handleStartGame,
    isWorkbenchOpen,
    shellState,
  ]);

  const localPlayer =
    hudSnapshot.players.find((p) => p.userId === LOCAL_USER_ID) ?? hudSnapshot.players[0];
  const missionDef = MISSION_TEMPLATES[hudSnapshot.missionId];
  const minutes = Math.floor(Math.ceil(hudSnapshot.remainingSeconds) / 60);
  const seconds = Math.ceil(hudSnapshot.remainingSeconds) % 60;
  const formattedTimer = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;

  return (
    <main className="relative w-screen h-screen overflow-hidden bg-slate-950 select-none">
      {/* Isolated 60 FPS Train Hub Simulation Canvas */}
      <TrainHubCanvas
        engineRef={engineRef as React.MutableRefObject<NightlineServerEngine>}
        localUserId={LOCAL_USER_ID}
        simSpeedRef={simSpeedRef}
        isPausedRef={isPausedRef}
        onNearestPromptChange={(prompt, distance) => setNearestPrompt({ prompt, distance })}
        onEngineTickUI={syncHudFromEngine}
        onTriggerPrompt={handleTriggerPrompt}
      />

      {/* Title Screen Overlay */}
      {shellState === 'title' && (
        <TitleScreenOverlay
          onStartGame={handleStartGame}
          onOpenCodeInspector={() => {
            handleStartGame();
            setWorkbenchTab('luau');
            setIsWorkbenchOpen(true);
          }}
        />
      )}

      {/* World-Matched HUD (Pointer Pass-Through Wrapper) */}
      {shellState !== 'title' && (
        <div className="fixed inset-0 z-20 pointer-events-none flex flex-col justify-between p-4 md:p-6">
          {/* Top Perimeter Row: Left Round & Mission Status + Right Crew Roster & Utility Controls */}
          <div className="flex flex-wrap items-start justify-between gap-3 w-full">
            {/* Top-Left Cluster: Round State, Countdown Timer, Destination & Mission */}
            <div className="pointer-events-auto bg-slate-950/90 border border-slate-800 rounded-lg px-3.5 py-2.5 shadow-xl w-full sm:w-auto sm:max-w-xl min-w-0">
              <div className="flex items-baseline justify-between gap-4">
                <div className="min-w-0">
                  <div className="text-[11px] font-mono uppercase tracking-wider text-slate-400 truncate">
                    ROUND #{hudSnapshot.roundNumber} · STN-001 DISPATCH
                  </div>
                  <div
                    className="text-lg md:text-2xl font-bold font-display tracking-wide text-amber-400 mt-0.5 truncate"
                    data-testid="round-state-readout"
                  >
                    {hudSnapshot.state}
                  </div>
                </div>

                <div className="text-right shrink-0">
                  <div className="text-[11px] font-mono uppercase tracking-wider text-slate-400">
                    PHASE TIMER
                  </div>
                  <div
                    className="text-xl md:text-3xl font-mono font-bold text-slate-100 tabular-nums"
                    data-testid="phase-timer-readout"
                  >
                    {formattedTimer}
                  </div>
                </div>
              </div>

              <div className="mt-1.5 pt-1.5 border-t border-slate-800/80 text-xs text-slate-300 flex flex-wrap items-center gap-x-2 gap-y-0.5">
                <span className="font-semibold text-sky-400">Station 001: The Forgotten Terminal</span>
                <span aria-hidden="true">·</span>
                <span>Mission: {missionDef.title}</span>
              </div>

              {hudSnapshot.latestNotification && (
                <div
                  className="mt-1.5 text-xs font-mono text-slate-300 truncate"
                  data-testid="hud-notification-banner"
                >
                  {hudSnapshot.latestNotification.severity.toUpperCase()} ·{' '}
                  {hudSnapshot.latestNotification.messageText}
                </div>
              )}
            </div>

            {/* Top-Right Cluster: Crew Status Summary + Speed / Workbench / Utility Controls */}
            <div className="pointer-events-auto flex flex-col items-stretch sm:items-end gap-2 w-full sm:w-auto max-w-full">
              <div className="flex flex-wrap items-center justify-between sm:justify-end gap-1.5 bg-slate-950/90 border border-slate-800 rounded-lg p-1.5 shadow-xl">
                <button
                  type="button"
                  onClick={(e) => {
                    e.currentTarget.blur();
                    setWorkbenchTab('luau');
                    setIsWorkbenchOpen((prev) => !prev);
                  }}
                  className="px-3 py-1.5 text-xs font-semibold bg-amber-500 hover:bg-amber-400 text-slate-950 rounded cursor-pointer whitespace-nowrap shrink-0"
                >
                  Rojo &amp; QA Workbench
                </button>

                <button
                  type="button"
                  onClick={(e) => {
                    e.currentTarget.blur();
                    handleAdvancePhase();
                  }}
                  className="px-2.5 py-1.5 text-xs font-mono font-semibold bg-slate-800 hover:bg-slate-700 text-slate-200 rounded cursor-pointer whitespace-nowrap shrink-0"
                  title="Advance to next RoundService state"
                >
                  Next State &rarr;
                </button>

                <button
                  type="button"
                  onClick={(e) => {
                    e.currentTarget.blur();
                    setSimSpeed((s) => (s === 1 ? 5 : s === 5 ? 10 : 1));
                  }}
                  className="px-2.5 py-1.5 text-xs font-mono font-semibold bg-slate-800 hover:bg-slate-700 text-amber-400 rounded cursor-pointer whitespace-nowrap shrink-0 tabular-nums"
                  aria-label="Toggle Timer Speed"
                >
                  {simSpeed}x
                </button>

                {/* Utility Square SVG Buttons: Mute [M], Pause [P], Restart [R] */}
                <button
                  type="button"
                  tabIndex={-1}
                  aria-label={isMuted ? 'Unmute Audio [M]' : 'Mute Audio [M]'}
                  onClick={(e) => {
                    e.currentTarget.blur();
                    setIsMuted((m) => !m);
                  }}
                  className="w-8 h-8 flex items-center justify-center bg-slate-900 hover:bg-slate-800 text-slate-200 border border-slate-700 rounded cursor-pointer shrink-0"
                >
                  <svg viewBox="0 0 24 24" className="w-4 h-4 fill-current">
                    {isMuted ? (
                      <path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z" />
                    ) : (
                      <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z" />
                    )}
                  </svg>
                </button>

                <button
                  type="button"
                  tabIndex={-1}
                  aria-label="Pause Simulation [P]"
                  onClick={(e) => {
                    e.currentTarget.blur();
                    setShellState((prev) => (prev === 'playing' ? 'paused' : 'playing'));
                  }}
                  className="w-8 h-8 flex items-center justify-center bg-slate-900 hover:bg-slate-800 text-slate-200 border border-slate-700 rounded cursor-pointer shrink-0"
                >
                  <svg viewBox="0 0 24 24" className="w-4 h-4 fill-current">
                    <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
                  </svg>
                </button>

                <button
                  type="button"
                  tabIndex={-1}
                  aria-label="Reset Server [R]"
                  onClick={(e) => {
                    e.currentTarget.blur();
                    handleResetServer();
                  }}
                  className="w-8 h-8 flex items-center justify-center bg-slate-900 hover:bg-slate-800 text-slate-200 border border-slate-700 rounded cursor-pointer shrink-0"
                >
                  <svg viewBox="0 0 24 24" className="w-4 h-4 fill-current">
                    <path d="M17.65 6.35A7.958 7.958 0 0012 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0112 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z" />
                  </svg>
                </button>
              </div>

              {/* Compact Crew Roster Summary Card */}
              <div className="bg-slate-950/90 border border-slate-800 rounded-lg px-3.5 py-2.5 shadow-xl min-w-[240px]">
                <div className="flex items-center justify-between text-[11px] font-mono text-slate-400 mb-1.5">
                  <span>CREW ROSTER ({hudSnapshot.players.length}/6)</span>
                  <button
                    type="button"
                    onClick={(e) => {
                      e.currentTarget.blur();
                      handleAddSimulatedPlayer();
                    }}
                    disabled={hudSnapshot.players.length >= 6}
                    className="text-sky-400 hover:text-sky-300 disabled:opacity-40 font-semibold cursor-pointer"
                  >
                    + Add Crew
                  </button>
                </div>
                <div className="space-y-1">
                  {hudSnapshot.players.map((member) => (
                    <div
                      key={member.userId}
                      className="flex items-center justify-between text-xs font-mono"
                    >
                      <span className="text-slate-200 truncate max-w-[110px]">
                        {member.displayName}
                      </span>
                      <span className="text-amber-400 tabular-nums">
                        {member.status} · {member.health} HP
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Contextual ProximityPrompt Indicator when in range of a Train Hub Terminal */}
          {nearestPrompt.prompt && (
            <div className="mx-auto pointer-events-auto bg-slate-950/95 border border-amber-500/80 rounded-lg px-4 py-2.5 shadow-2xl flex items-center gap-3">
              <span className="px-2 py-1 text-xs font-mono font-bold bg-amber-500 text-slate-950 rounded">
                [E]
              </span>
              <div className="text-xs">
                <div className="font-semibold text-slate-100">
                  {nearestPrompt.prompt.actionText}
                </div>
                <div className="text-slate-400 font-mono">
                  {nearestPrompt.prompt.objectText} · {nearestPrompt.distance.toFixed(1)} studs
                </div>
              </div>
              <button
                type="button"
                onClick={(e) => {
                  e.currentTarget.blur();
                  handleTriggerPrompt(nearestPrompt.prompt!.id);
                }}
                className="px-3 py-1.5 text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-amber-400 rounded cursor-pointer whitespace-nowrap shrink-0"
              >
                Activate Prompt
              </button>
            </div>
          )}

          {/* Bottom Unified Dock: 2-Slot Equipment Loadout + Hub Terminal Actions */}
          <div className="mx-auto pointer-events-auto bg-slate-950/95 border border-slate-800 rounded-xl p-2.5 shadow-2xl flex flex-wrap items-center justify-center gap-2.5 max-w-4xl">
            {/* Slot 1: Service Flashlight */}
            <button
              type="button"
              onClick={(e) => {
                e.currentTarget.blur();
                handleEquipSlot(1, 'Flashlight');
              }}
              className={`flex items-center gap-2.5 px-3.5 py-2 rounded-lg border text-left transition-colors cursor-pointer whitespace-nowrap shrink-0 ${
                localPlayer?.equipmentSlots[1] === 'Flashlight'
                  ? 'bg-slate-900 border-sky-500/80 text-slate-100'
                  : 'bg-slate-900/50 border-slate-800 text-slate-400 hover:text-slate-200'
              }`}
            >
              <svg viewBox="0 0 24 24" className="w-5 h-5 text-amber-400 shrink-0 fill-current">
                <path d="M6 2h12v3l-2 3v14H8V8L6 5V2zm2 2v.5l1.5 2.25h5L16 4.5V4H8zm4 7a2 2 0 100 4 2 2 0 000-4z" />
              </svg>
              <div>
                <div className="text-xs font-semibold">
                  [1] {localPlayer?.equipmentSlots[1] === 'Flashlight' ? 'Service Flashlight' : 'Slot 1 Empty'}
                </div>
                <div className="text-[11px] font-mono text-slate-400">
                  Equipment · Local Illumination
                </div>
              </div>
            </button>

            {/* Slot 2: Acoustic Signal Flare */}
            <button
              type="button"
              onClick={(e) => {
                e.currentTarget.blur();
                handleEquipSlot(2, 'Flare');
              }}
              className={`flex items-center gap-2.5 px-3.5 py-2 rounded-lg border text-left transition-colors cursor-pointer whitespace-nowrap shrink-0 ${
                localPlayer?.equipmentSlots[2] === 'Flare'
                  ? 'bg-slate-900 border-amber-500/80 text-slate-100'
                  : 'bg-slate-900/50 border-slate-800 text-slate-400 hover:text-slate-200'
              }`}
            >
              <svg viewBox="0 0 24 24" className="w-5 h-5 text-rose-400 shrink-0 fill-current">
                <path d="M12 2l2.4 4.8L20 7.6l-4 3.9.9 5.5-4.9-2.6L7.1 17l.9-5.5-4-3.9 5.6-.8L12 2zm-2 16h4v4h-4v-4z" />
              </svg>
              <div>
                <div className="text-xs font-semibold">
                  [2] {localPlayer?.equipmentSlots[2] === 'Flare' ? 'Acoustic Signal Flare' : 'Slot 2 Empty (Tap to Equip)'}
                </div>
                <div className="text-[11px] font-mono text-slate-400">
                  Consumable · Acoustic Lure
                </div>
              </div>
            </button>

            {/* Hub Dispatch & Boarding Quick Actions */}
            <div className="h-8 w-px bg-slate-800 hidden sm:block" />

            <button
              type="button"
              onClick={(e) => {
                e.currentTarget.blur();
                handleConfirmDestination();
              }}
              className="px-3.5 py-2 text-xs font-semibold bg-slate-800 hover:bg-slate-700 text-sky-300 border border-slate-700 rounded-lg cursor-pointer whitespace-nowrap shrink-0"
            >
              Vote Route: Station 001
            </button>

            <button
              type="button"
              onClick={(e) => {
                e.currentTarget.blur();
                handleToggleReady();
              }}
              className={`px-3.5 py-2 text-xs font-semibold rounded-lg border cursor-pointer whitespace-nowrap shrink-0 ${
                localPlayer?.isReady
                  ? 'bg-emerald-500/20 border-emerald-500 text-emerald-300'
                  : 'bg-amber-500 hover:bg-amber-400 border-amber-400 text-slate-950'
              }`}
            >
              {localPlayer?.isReady ? 'Boarded & Ready' : 'Board Train'}
            </button>

            <button
              type="button"
              onClick={(e) => {
                e.currentTarget.blur();
                handleWalkToStationTerminal('DestinationConsole');
              }}
              className="px-3 py-2 text-xs font-mono text-slate-300 hover:text-white bg-slate-900 hover:bg-slate-800 border border-slate-800 rounded-lg cursor-pointer whitespace-nowrap shrink-0"
            >
              Walk to Console
            </button>

            <button
              type="button"
              onClick={(e) => {
                e.currentTarget.blur();
                handleMoveToExtractionZone(LOCAL_USER_ID);
              }}
              className="px-3 py-2 text-xs font-mono text-emerald-300 hover:text-white bg-emerald-950/60 hover:bg-emerald-900/70 border border-emerald-700/60 rounded-lg cursor-pointer whitespace-nowrap shrink-0"
            >
              Extract Zone
            </button>
          </div>
        </div>
      )}

      {/* Pause Modal (`document.body.dataset.state === 'paused'`) */}
      {shellState === 'paused' && (
        <div className="fixed inset-0 z-40 bg-slate-950/85 flex items-center justify-center p-4 pointer-events-auto">
          <div className="w-full max-w-md bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-2xl space-y-5">
            <div>
              <div className="text-xs font-mono text-amber-400 uppercase tracking-wider">
                SIMULATION PAUSED
              </div>
              <h2 className="text-2xl font-bold font-display text-slate-100 mt-1">
                NIGHTLINE: LAST TRAIN
              </h2>
            </div>

            <div className="grid grid-cols-3 gap-3 text-center">
              <div className="p-3 bg-slate-950 border border-slate-800 rounded-lg">
                <div className="text-[11px] font-mono text-slate-400">ROUND</div>
                <div className="text-lg font-mono font-bold text-slate-100 tabular-nums mt-0.5">
                  #{hudSnapshot.roundNumber}
                </div>
              </div>
              <div className="p-3 bg-slate-950 border border-slate-800 rounded-lg">
                <div className="text-[11px] font-mono text-slate-400">STATE</div>
                <div className="text-sm font-mono font-bold text-amber-400 mt-1">
                  {hudSnapshot.state}
                </div>
              </div>
              <div className="p-3 bg-slate-950 border border-slate-800 rounded-lg">
                <div className="text-[11px] font-mono text-slate-400">CREW</div>
                <div className="text-lg font-mono font-bold text-sky-400 tabular-nums mt-0.5">
                  {hudSnapshot.players.length}/6
                </div>
              </div>
            </div>

            <div className="flex flex-col gap-2.5">
              <button
                type="button"
                onClick={() => setShellState('playing')}
                className="w-full py-2.5 bg-amber-500 hover:bg-amber-400 text-slate-950 font-semibold text-sm rounded-lg cursor-pointer"
              >
                Resume Simulation [P]
              </button>
              <button
                type="button"
                onClick={handleResetServer}
                className="w-full py-2.5 bg-slate-800 hover:bg-slate-700 text-slate-100 font-medium text-sm rounded-lg cursor-pointer"
              >
                Restart Server State [R]
              </button>
              <button
                type="button"
                onClick={() => setShellState('title')}
                className="w-full py-2.5 bg-slate-950 hover:bg-slate-800 text-slate-400 hover:text-slate-200 font-medium text-sm rounded-lg border border-slate-800 cursor-pointer"
              >
                Return to Title Screen
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Rojo & Luau Engineering Workbench Drawer */}
      <WorkbenchDrawer
        isOpen={isWorkbenchOpen}
        onClose={() => setIsWorkbenchOpen(false)}
        activeTab={workbenchTab}
        setActiveTab={setWorkbenchTab}
        players={hudSnapshot.players}
        remoteLogs={hudSnapshot.remoteLogs}
        onAddSimulatedPlayer={handleAddSimulatedPlayer}
        onRemoveSimulatedPlayer={handleRemoveSimulatedPlayer}
        onEliminatePlayer={handleEliminatePlayer}
        onMoveToExtractionZone={handleMoveToExtractionZone}
        onAdvancePhase={handleAdvancePhase}
        onResetServer={handleResetServer}
        onRunSecurityTest={handleRunSecurityTest}
        engine={engineRef.current!}
      />
    </main>
  );
}
