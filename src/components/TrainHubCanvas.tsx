import React, { useEffect, useRef } from 'react';
import {
  NightlineServerEngine,
  HUB_INTERACTABLES,
  HUB_SPAWN_OFFSETS,
  ELIMINATED_SPAWN_OFFSETS,
  BOARDING_BAY_OFFSETS,
  STATION_ENTRY_OFFSETS,
  GAME_CONFIG,
  HubInteractable,
} from '../engine/nightlineEngine';

interface TrainHubCanvasProps {
  engineRef: React.MutableRefObject<NightlineServerEngine>;
  localUserId: number;
  simSpeedRef: React.MutableRefObject<number>;
  isPausedRef: React.MutableRefObject<boolean>;
  onNearestPromptChange: (prompt: HubInteractable | null, distance: number) => void;
  onEngineTickUI: () => void;
  onTriggerPrompt: (interactableId: string) => void;
}

export const TrainHubCanvas: React.FC<TrainHubCanvasProps> = ({
  engineRef,
  localUserId,
  simSpeedRef,
  isPausedRef,
  onNearestPromptChange,
  onEngineTickUI,
  onTriggerPrompt,
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const callbacksRef = useRef({
    onNearestPromptChange,
    onEngineTickUI,
    onTriggerPrompt,
  });

  useEffect(() => {
    callbacksRef.current = {
      onNearestPromptChange,
      onEngineTickUI,
      onTriggerPrompt,
    };
  }, [onNearestPromptChange, onEngineTickUI, onTriggerPrompt]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const keysPressed = new Set<string>();
    let lastNearestId: string | null = null;
    let lastNearestDist = -1;
    let railScrollOffset = 0;

    const resizeCanvas = () => {
      const parent = canvas.parentElement;
      if (!parent) return;
      const rect = parent.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.max(320, Math.floor(rect.width * dpr));
      canvas.height = Math.max(240, Math.floor(rect.height * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };

    resizeCanvas();
    const resizeObserver = new ResizeObserver(resizeCanvas);
    if (canvas.parentElement) {
      resizeObserver.observe(canvas.parentElement);
    }

    const handleKeyDown = (e: KeyboardEvent) => {
      if (
        document.activeElement &&
        (document.activeElement.tagName === 'INPUT' ||
          document.activeElement.tagName === 'TEXTAREA' ||
          document.activeElement.tagName === 'SELECT')
      ) {
        return;
      }

      const key = e.key.toLowerCase();
      const wasShiftHeld = keysPressed.has('shift');
      keysPressed.add(key);

      if (key === 'shift' && !wasShiftHeld && !isPausedRef.current) {
        engineRef.current.handleSprintRequest(localUserId, true);
      }

      if (key === 'e' && !e.repeat && !isPausedRef.current) {
        const engine = engineRef.current;
        const player = engine.players.get(localUserId);
        if (player) {
          let best: HubInteractable | null = null;
          let bestDist = Infinity;
          for (const item of HUB_INTERACTABLES) {
            const dist = Math.hypot(
              player.position.x - item.position.x,
              player.position.z - item.position.z
            );
            if (dist <= GAME_CONFIG.MAX_INTERACTION_DISTANCE && dist < bestDist) {
              best = item;
              bestDist = dist;
            }
          }
          if (best) {
            callbacksRef.current.onTriggerPrompt(best.id);
          }
        }
      }
    };

    const handleKeyUp = (e: KeyboardEvent) => {
      const key = e.key.toLowerCase();
      keysPressed.delete(key);
      if (key === 'shift' && !isPausedRef.current) {
        engineRef.current.handleSprintRequest(localUserId, false);
      }
    };

    const clearHeldKeys = () => {
      if (keysPressed.has('shift')) {
        engineRef.current.handleSprintRequest(localUserId, false);
      }
      keysPressed.clear();
    };

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    window.addEventListener('blur', clearHeldKeys);

    let lastTime = performance.now();
    let animationFrameId = 0;
    let frameTimerId: ReturnType<typeof setTimeout> | null = null;
    let isUnmounted = false;
    let lastSyncedSecond = -1;
    let lastSyncedState = '';
    let lastSyncedLogCount = -1;

    const scheduleNextFrame = () => {
      if (isUnmounted) return;
      const delayMs = keysPressed.size > 0 ? 16 : 50;
      frameTimerId = setTimeout(() => {
        if (isUnmounted) return;
        animationFrameId = requestAnimationFrame(renderFrame);
      }, delayMs);
    };

    const renderFrame = (now: number) => {
      if (isUnmounted) return;
      const rawDt = (now - lastTime) / 1000;
      lastTime = now;
      const dt = Math.min(Math.max(rawDt, 0), 0.1);

      const engine = engineRef.current;
      const localPlayer = engine.players.get(localUserId);

      if (!isPausedRef.current) {
        // Compute local player movement vector from WASD / Arrow keys
        if (localPlayer) {
          let vx = 0;
          let vz = 0;
          if (keysPressed.has('w') || keysPressed.has('arrowup')) vz -= 1;
          if (keysPressed.has('s') || keysPressed.has('arrowdown')) vz += 1;
          if (keysPressed.has('a') || keysPressed.has('arrowleft')) vx -= 1;
          if (keysPressed.has('d') || keysPressed.has('arrowright')) vx += 1;

          const mag = Math.hypot(vx, vz);
          if (mag > 0) {
            localPlayer.velocity.x = vx / mag;
            localPlayer.velocity.z = vz / mag;
          } else {
            localPlayer.velocity.x = 0;
            localPlayer.velocity.z = 0;
          }
        }

        // Advance authoritative simulation
        engine.stepSimulation(dt * simSpeedRef.current);

        // Animate rail sleepers when train is moving
        if (engine.state === 'TRAVEL' || engine.state === 'RETURN') {
          railScrollOffset = (railScrollOffset + dt * 180) % 48;
        } else if (engine.state === 'INTERMISSION' || engine.state === 'BOARDING') {
          railScrollOffset = (railScrollOffset + dt * 20) % 48;
        }

        // Check nearest ProximityPrompt for local player
        if (localPlayer) {
          let nearest: HubInteractable | null = null;
          let minDist = Infinity;
          for (const item of HUB_INTERACTABLES) {
            const d = Math.hypot(
              localPlayer.position.x - item.position.x,
              localPlayer.position.z - item.position.z
            );
            if (d < minDist) {
              minDist = d;
              nearest = item;
            }
          }
          const withinRange =
            nearest && minDist <= GAME_CONFIG.MAX_INTERACTION_DISTANCE ? nearest : null;
          const roundedDist = Math.round(minDist * 10) / 10;
          if (
            (withinRange?.id ?? null) !== lastNearestId ||
            (withinRange && Math.abs(roundedDist - lastNearestDist) >= 0.5)
          ) {
            lastNearestId = withinRange?.id ?? null;
            lastNearestDist = roundedDist;
            callbacksRef.current.onNearestPromptChange(withinRange, roundedDist);
          }
        }

        const currentCeilSecond = Math.ceil(engine.phaseRemainingSeconds);
        if (
          currentCeilSecond !== lastSyncedSecond ||
          engine.state !== lastSyncedState ||
          engine.remoteLogs.length !== lastSyncedLogCount
        ) {
          lastSyncedSecond = currentCeilSecond;
          lastSyncedState = engine.state;
          lastSyncedLogCount = engine.remoteLogs.length;
          callbacksRef.current.onEngineTickUI();
        }
      }

      // Draw Scene
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const width = canvas.width / dpr;
      const height = canvas.height / dpr;

      ctx.clearRect(0, 0, width, height);

      // Background Subterranean Tunnel Canvas
      ctx.fillStyle = '#090d16';
      ctx.fillRect(0, 0, width, height);

      const centerX = width * 0.5;
      const centerY = height * 0.5;
      const scale = Math.min((width * 0.82) / 96, (height * 0.62) / 36);

      const worldToScreen = (wx: number, wz: number) => {
        return {
          sx: centerX - wz * scale,
          sy: centerY + wx * scale,
        };
      };

      // Draw Subterranean Rail Ties & Ballast Tracks
      ctx.strokeStyle = '#1e293b';
      ctx.lineWidth = 2;
      for (let gx = -56; gx <= 56; gx += 4) {
        const tieX = centerX + gx * scale - (railScrollOffset % (4 * scale));
        ctx.beginPath();
        ctx.moveTo(tieX, centerY - 14 * scale);
        ctx.lineTo(tieX, centerY + 14 * scale);
        ctx.stroke();
      }

      // Steel Rails
      ctx.strokeStyle = '#334155';
      ctx.lineWidth = 3;
      [-7.5, 7.5].forEach((railY) => {
        ctx.beginPath();
        ctx.moveTo(0, centerY + railY * scale);
        ctx.lineTo(width, centerY + railY * scale);
        ctx.stroke();
      });

      // Station 001 Boarding Platform on the bottom side (Positive X in world = lower on screen)
      const isAtStation =
        engine.state === 'EXPLORATION' || engine.state === 'EXTRACTION';
      const platformTopLeft = worldToScreen(11.5, 42);
      const platformBottomRight = worldToScreen(20.5, -42);
      ctx.fillStyle = isAtStation ? '#1e293b' : '#111827';
      ctx.fillRect(
        platformTopLeft.sx,
        platformTopLeft.sy,
        platformBottomRight.sx - platformTopLeft.sx,
        platformBottomRight.sy - platformTopLeft.sy
      );
      ctx.strokeStyle = isAtStation ? '#10b981' : '#334155';
      ctx.lineWidth = 2;
      ctx.strokeRect(
        platformTopLeft.sx,
        platformTopLeft.sy,
        platformBottomRight.sx - platformTopLeft.sx,
        platformBottomRight.sy - platformTopLeft.sy
      );

      ctx.fillStyle = isAtStation ? '#34d399' : '#64748b';
      ctx.font = `600 ${Math.max(10, Math.floor(scale * 1.1))}px "JetBrains Mono", monospace`;
      ctx.textAlign = 'center';
      ctx.fillText(
        isAtStation
          ? 'STATION 001: THE FORGOTTEN TERMINAL · PHYSICAL EXTRACTION ZONE ACTIVE'
          : 'HUB PLATFORM BAY · BOARDING & EXTRACTION ZONE ALIGNED',
        centerX,
        platformTopLeft.sy + 6.5 * scale
      );

      // Train Carriage Outer Hull (Z from -42 to +42, X from -11 to +11)
      const hullTL = worldToScreen(-11, 42);
      const hullBR = worldToScreen(11, -42);
      const hullW = hullBR.sx - hullTL.sx;
      const hullH = hullBR.sy - hullTL.sy;

      // Exterior Hull Shadow & Fill
      ctx.fillStyle = '#161e2e';
      ctx.fillRect(hullTL.sx, hullTL.sy, hullW, hullH);

      // Diamond-Plate Grid Floor Lines inside Carriage
      ctx.strokeStyle = 'rgba(51, 65, 85, 0.45)';
      ctx.lineWidth = 1;
      for (let z = -38; z <= 38; z += 4) {
        const p1 = worldToScreen(-10.2, z);
        const p2 = worldToScreen(10.2, z);
        ctx.beginPath();
        ctx.moveTo(p1.sx, p1.sy);
        ctx.lineTo(p2.sx, p2.sy);
        ctx.stroke();
      }

      // Locomotive Front Nose Cone (Right side, Z = -42 to -48)
      const noseTop = worldToScreen(-11, -42);
      const noseBottom = worldToScreen(11, -42);
      const noseTipTop = worldToScreen(-7, -48);
      const noseTipBottom = worldToScreen(7, -48);
      ctx.fillStyle = '#1e293b';
      ctx.beginPath();
      ctx.moveTo(noseTop.sx, noseTop.sy);
      ctx.lineTo(noseTipTop.sx, noseTipTop.sy);
      ctx.lineTo(noseTipBottom.sx, noseTipBottom.sy);
      ctx.lineTo(noseBottom.sx, noseBottom.sy);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = '#f59e0b';
      ctx.lineWidth = 2;
      ctx.stroke();

      // Locomotive Headlamp Cone
      const beamGradient = ctx.createLinearGradient(
        noseTipTop.sx,
        centerY,
        noseTipTop.sx + 16 * scale,
        centerY
      );
      beamGradient.addColorStop(0, 'rgba(251, 191, 36, 0.32)');
      beamGradient.addColorStop(1, 'rgba(251, 191, 36, 0)');
      ctx.fillStyle = beamGradient;
      ctx.beginPath();
      ctx.moveTo(noseTipTop.sx, noseTipTop.sy);
      ctx.lineTo(noseTipTop.sx + 18 * scale, noseTipTop.sy - 6 * scale);
      ctx.lineTo(noseTipBottom.sx + 18 * scale, noseTipBottom.sy + 6 * scale);
      ctx.lineTo(noseTipBottom.sx, noseTipBottom.sy);
      ctx.closePath();
      ctx.fill();

      // Carriage Structural Walls
      ctx.strokeStyle = '#475569';
      ctx.lineWidth = 3;
      ctx.strokeRect(hullTL.sx, hullTL.sy, hullW, hullH);

      // Zone Labels inside Train Hub
      ctx.fillStyle = 'rgba(148, 163, 184, 0.55)';
      ctx.font = `600 ${Math.max(9, Math.floor(scale * 0.9))}px "JetBrains Mono", monospace`;
      ctx.textAlign = 'center';
      const recZonePos = worldToScreen(0, 37);
      ctx.fillText('RECOVERY BAY', recZonePos.sx, recZonePos.sy);

      const rearZonePos = worldToScreen(0, 22);
      ctx.fillText('CREW SPAWN CARRIAGE', rearZonePos.sx, rearZonePos.sy);

      const midZonePos = worldToScreen(0, -8);
      ctx.fillText('LOCKER & BOARDING BAY', midZonePos.sx, midZonePos.sy);

      const frontZonePos = worldToScreen(0, -28);
      ctx.fillText('COMMAND & DISPATCH', frontZonePos.sx, frontZonePos.sy);

      // Eliminated Recovery Berths (Issue 01: Z = 35..38)
      ELIMINATED_SPAWN_OFFSETS.forEach((berth, idx) => {
        const pos = worldToScreen(berth.x, berth.z);
        const sz = 2.4 * scale;
        ctx.fillStyle = 'rgba(244, 63, 94, 0.16)';
        ctx.strokeStyle = 'rgba(244, 63, 94, 0.6)';
        ctx.lineWidth = 1.2;
        ctx.fillRect(pos.sx - sz / 2, pos.sy - sz / 2, sz, sz);
        ctx.strokeRect(pos.sx - sz / 2, pos.sy - sz / 2, sz, sz);

        ctx.fillStyle = '#fb7185';
        ctx.font = `600 ${Math.max(7, Math.floor(scale * 0.7))}px "JetBrains Mono", monospace`;
        ctx.fillText(`R${idx + 1}`, pos.sx, pos.sy + 3);
      });

      // 6 Hub Spawn Pads (Issue 02: Explicit Slots S1..S6 at Z = 12, 22, 32)
      HUB_SPAWN_OFFSETS.forEach((pad, idx) => {
        const pos = worldToScreen(pad.x, pad.z);
        const padSize = 3.4 * scale;
        ctx.fillStyle = 'rgba(56, 189, 248, 0.14)';
        ctx.strokeStyle = 'rgba(56, 189, 248, 0.65)';
        ctx.lineWidth = 1.5;
        ctx.fillRect(pos.sx - padSize / 2, pos.sy - padSize / 2, padSize, padSize);
        ctx.strokeRect(pos.sx - padSize / 2, pos.sy - padSize / 2, padSize, padSize);

        ctx.fillStyle = '#38bdf8';
        ctx.font = `600 ${Math.max(8, Math.floor(scale * 0.8))}px "JetBrains Mono", monospace`;
        ctx.fillText(`S${idx + 1}`, pos.sx, pos.sy + 3);
      });

      // 6 Forward Boarding Spots (Z = -14, -19, -24)
      BOARDING_BAY_OFFSETS.forEach((spot, idx) => {
        const pos = worldToScreen(spot.x, spot.z);
        const spotSize = 2.8 * scale;
        ctx.fillStyle = 'rgba(245, 158, 11, 0.14)';
        ctx.strokeStyle = 'rgba(245, 158, 11, 0.55)';
        ctx.lineWidth = 1.2;
        ctx.fillRect(pos.sx - spotSize / 2, pos.sy - spotSize / 2, spotSize, spotSize);
        ctx.strokeRect(pos.sx - spotSize / 2, pos.sy - spotSize / 2, spotSize, spotSize);

        ctx.fillStyle = '#fbbf24';
        ctx.font = `600 ${Math.max(8, Math.floor(scale * 0.75))}px "JetBrains Mono", monospace`;
        ctx.fillText(`B${idx + 1}`, pos.sx, pos.sy + 3);
      });

      // 6 Station 001 Entry Spawns (Fix 1: E1..E6 at X = 14..18, Z = 18..30, outside ExtractionPlatformZone)
      STATION_ENTRY_OFFSETS.forEach((entrySpot, idx) => {
        const pos = worldToScreen(entrySpot.x, entrySpot.z);
        const spotSize = 2.6 * scale;
        ctx.fillStyle = 'rgba(168, 85, 247, 0.16)';
        ctx.strokeStyle = 'rgba(168, 85, 247, 0.65)';
        ctx.lineWidth = 1.2;
        ctx.fillRect(pos.sx - spotSize / 2, pos.sy - spotSize / 2, spotSize, spotSize);
        ctx.strokeRect(pos.sx - spotSize / 2, pos.sy - spotSize / 2, spotSize, spotSize);

        ctx.fillStyle = '#c084fc';
        ctx.font = `600 ${Math.max(7, Math.floor(scale * 0.7))}px "JetBrains Mono", monospace`;
        ctx.fillText(`E${idx + 1}`, pos.sx, pos.sy + 3);
      });

      // Render Tagged Interactables (DestinationConsole, Equipment Lockers, Boarding Gate, ExtractionPlatformZone)
      HUB_INTERACTABLES.forEach((item) => {
        const pos = worldToScreen(item.position.x, item.position.z);
        const wScreen = item.size.d * scale;
        const hScreen = item.size.w * scale;

        const isHighlighted = lastNearestId === item.id;

        if (item.tag === 'NightlineDestinationTerminal') {
          ctx.fillStyle = isHighlighted ? '#0284c7' : '#0369a1';
          ctx.strokeStyle = isHighlighted ? '#fde047' : '#38bdf8';
        } else if (item.tag === 'NightlineEquipmentLocker') {
          ctx.fillStyle = isHighlighted ? '#3b82f6' : '#1d4ed8';
          ctx.strokeStyle = isHighlighted ? '#fde047' : '#60a5fa';
        } else if (item.tag === 'NightlineExtractionZone') {
          ctx.fillStyle =
            engine.state === 'EXTRACTION'
              ? 'rgba(16, 185, 129, 0.35)'
              : 'rgba(16, 185, 129, 0.15)';
          ctx.strokeStyle = isHighlighted ? '#fde047' : '#10b981';
        } else {
          ctx.fillStyle = isHighlighted ? '#d97706' : '#b45309';
          ctx.strokeStyle = isHighlighted ? '#fde047' : '#fbbf24';
        }

        ctx.lineWidth = isHighlighted ? 2.5 : 1.5;
        ctx.fillRect(pos.sx - wScreen / 2, pos.sy - hScreen / 2, wScreen, hScreen);
        ctx.strokeRect(pos.sx - wScreen / 2, pos.sy - hScreen / 2, wScreen, hScreen);

        // Label
        ctx.fillStyle = '#f8fafc';
        ctx.font = `600 ${Math.max(9, Math.floor(scale * 0.85))}px "Plus Jakarta Sans", sans-serif`;
        ctx.textAlign = 'center';
        const shortLabel =
          item.id === 'DestinationConsole'
            ? 'NAV CONSOLE'
            : item.id === 'EquipmentLocker_Flashlight'
            ? 'FLASHLIGHT [1]'
            : item.id === 'EquipmentLocker_Flare'
            ? 'FLARE [2]'
            : item.id === 'ExtractionPlatformZone'
            ? 'EXTRACTION ZONE'
            : 'BOARDING GATE';
        const labelOffsetY =
          item.id === 'ExtractionPlatformZone'
            ? 4
            : item.position.x < 0
            ? -hScreen / 2 - 6
            : hScreen / 2 + 12;
        ctx.fillText(shortLabel, pos.sx, pos.sy + labelOffsetY);
      });

      // Draw Players
      for (const player of engine.players.values()) {
        const pos = worldToScreen(player.position.x, player.position.z);
        const radius = 1.35 * scale;

        // Flashlight Cone if Flashlight is equipped in active slot
        const activeEquipment = player.equipmentSlots[player.activeSlot];
        if (activeEquipment === 'Flashlight' && player.status !== 'ELIMINATED') {
          ctx.save();
          ctx.translate(pos.sx, pos.sy);
          const screenDirX = -Math.cos(player.facingAngle);
          const screenDirY = Math.sin(player.facingAngle);
          const angle = Math.atan2(screenDirY, screenDirX);
          ctx.rotate(angle);

          const coneGrad = ctx.createRadialGradient(0, 0, radius * 0.4, 0, 0, 11 * scale);
          coneGrad.addColorStop(0, 'rgba(254, 240, 138, 0.32)');
          coneGrad.addColorStop(1, 'rgba(254, 240, 138, 0)');
          ctx.fillStyle = coneGrad;
          ctx.beginPath();
          ctx.moveTo(0, 0);
          ctx.arc(0, 0, 11 * scale, -0.42, 0.42);
          ctx.closePath();
          ctx.fill();
          ctx.restore();
        }

        // Interaction range ring around local player
        if (player.userId === localUserId) {
          ctx.strokeStyle = 'rgba(56, 189, 248, 0.18)';
          ctx.lineWidth = 1;
          ctx.setLineDash([4, 4]);
          ctx.beginPath();
          ctx.arc(pos.sx, pos.sy, GAME_CONFIG.MAX_INTERACTION_DISTANCE * scale, 0, Math.PI * 2);
          ctx.stroke();
          ctx.setLineDash([]);
        }

        // Player Avatar Circle
        ctx.beginPath();
        ctx.arc(pos.sx, pos.sy, radius, 0, Math.PI * 2);
        if (player.status === 'ELIMINATED') {
          ctx.fillStyle = '#e11d48';
          ctx.strokeStyle = '#fecdd3';
        } else if (player.status === 'EXTRACTED') {
          ctx.fillStyle = '#10b981';
          ctx.strokeStyle = '#d1fae5';
        } else if (player.userId === localUserId) {
          ctx.fillStyle = '#38bdf8';
          ctx.strokeStyle = '#f8fafc';
        } else if (player.status === 'IN_EXPEDITION' || player.status === 'BOARDED') {
          ctx.fillStyle = '#f59e0b';
          ctx.strokeStyle = '#fef3c7';
        } else {
          ctx.fillStyle = '#94a3b8';
          ctx.strokeStyle = '#e2e8f0';
        }
        ctx.lineWidth = 2;
        ctx.fill();
        ctx.stroke();

        // Player Name, Slot & Status Label
        ctx.fillStyle = '#f8fafc';
        ctx.font = `600 ${Math.max(10, Math.floor(scale * 0.9))}px "Plus Jakarta Sans", sans-serif`;
        ctx.textAlign = 'center';
        ctx.fillText(
          `${player.displayName} [S${player.spawnSlot}] (${player.status === 'HUB_WAITING' ? 'HUB' : player.status})`,
          pos.sx,
          pos.sy - radius - 6
        );
      }

      scheduleNextFrame();
    };

    animationFrameId = requestAnimationFrame(renderFrame);

    return () => {
      isUnmounted = true;
      cancelAnimationFrame(animationFrameId);
      if (frameTimerId) clearTimeout(frameTimerId);
      resizeObserver.disconnect();
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
      window.removeEventListener('blur', clearHeldKeys);
    };
  }, [engineRef, isPausedRef, localUserId, simSpeedRef]);

  return (
    <div className="relative w-full h-full overflow-hidden bg-slate-950" data-testid="train-hub-viewport">
      <canvas
        ref={canvasRef}
        className="block w-full h-full focus:outline-none"
        tabIndex={0}
        aria-label="NIGHTLINE Train Hub Interactive Simulation Canvas"
      />
    </div>
  );
};
