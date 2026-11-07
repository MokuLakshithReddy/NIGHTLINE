import React from 'react';

interface TitleScreenOverlayProps {
  onStartGame: () => void;
  onOpenCodeInspector: () => void;
}

export const TitleScreenOverlay: React.FC<TitleScreenOverlayProps> = ({
  onStartGame,
  onOpenCodeInspector,
}) => {
  return (
    <div
      className="fixed inset-0 z-30 flex flex-col justify-between p-8 md:p-14 pointer-events-auto"
      style={{
        background:
          'linear-gradient(90deg, rgba(9, 13, 22, 0.94) 0%, rgba(9, 13, 22, 0.82) 48%, rgba(9, 13, 22, 0.28) 100%)',
      }}
    >
      {/* Top Identity Strip */}
      <div className="flex items-center justify-between">
        <div className="text-xs font-mono tracking-wider text-slate-400">
          <span>ROBLOX LUAU STRICT</span>
          <span className="mx-2" aria-hidden="true">·</span>
          <span>ROJO 7.4 WORKFLOW</span>
          <span className="mx-2" aria-hidden="true">·</span>
          <span>MILESTONE 0 &amp; 1 VERIFIED</span>
        </div>
      </div>

      {/* Asymmetric Left-Third Negative Space Focal Lockup */}
      <div className="max-w-xl my-auto space-y-6">
        {/* Custom Inline SVG Emblem & Locomotive Silhouette Lockup */}
        <div className="space-y-3">
          <svg
            viewBox="0 0 420 110"
            className="w-full max-w-md h-auto"
            role="img"
            aria-label="NIGHTLINE: LAST TRAIN Emblem"
          >
            {/* Subterranean Arch & Rail Perspective Lines */}
            <path
              d="M8 98 L412 98"
              stroke="#334155"
              strokeWidth="2"
            />
            <path
              d="M24 104 L396 104"
              stroke="#1e293b"
              strokeWidth="2"
            />
            {/* Armored Transit Locomotive Icon */}
            <g transform="translate(12, 16)">
              <rect
                x="0"
                y="8"
                width="68"
                height="62"
                rx="6"
                fill="#1e293b"
                stroke="#f59e0b"
                strokeWidth="2.5"
              />
              <rect
                x="8"
                y="18"
                width="22"
                height="16"
                rx="2"
                fill="#38bdf8"
              />
              <rect
                x="38"
                y="18"
                width="22"
                height="16"
                rx="2"
                fill="#38bdf8"
              />
              {/* Center Headlamp */}
              <circle
                cx="34"
                cy="50"
                r="7"
                fill="#fbbf24"
              />
              <path
                d="M12 70 L4 78 M56 70 L64 78"
                stroke="#94a3b8"
                strokeWidth="3"
                strokeLinecap="round"
              />
            </g>
            {/* Structural Display Typography */}
            <text
              x="96"
              y="54"
              fill="#f8fafc"
              fontFamily="Outfit, sans-serif"
              fontWeight="700"
              fontSize="44"
              letterSpacing="3"
            >
              NIGHTLINE
            </text>
            <text
              x="98"
              y="82"
              fill="#f59e0b"
              fontFamily="JetBrains Mono, monospace"
              fontWeight="600"
              fontSize="16"
              letterSpacing="5"
            >
              LAST TRAIN · SECTOR 001
            </text>
          </svg>

          <p className="text-base text-slate-300 leading-relaxed max-w-lg">
            Every stop is a risk. Every return is a reward. Board the armoured transit hub, configure your two-slot expedition loadout, and test the authoritative Luau round state machine.
          </p>
        </div>

        {/* Primary Action CTAs (<= 3 actions total) */}
        <div className="flex flex-wrap items-center gap-4 pt-2">
          <button
            type="button"
            data-start="true"
            onClick={(e) => {
              e.currentTarget.blur();
              onStartGame();
            }}
            className="px-6 py-3.5 bg-amber-500 hover:bg-amber-400 text-slate-950 font-semibold text-sm rounded-lg shadow-lg transition-transform active:scale-95 cursor-pointer whitespace-nowrap shrink-0"
          >
            Enter Train Hub
          </button>

          <button
            type="button"
            onClick={(e) => {
              e.currentTarget.blur();
              onOpenCodeInspector();
            }}
            className="px-5 py-3.5 bg-slate-800/90 hover:bg-slate-700 text-slate-100 border border-slate-700 font-medium text-sm rounded-lg transition-colors cursor-pointer whitespace-nowrap shrink-0"
          >
            Inspect Rojo &amp; Luau Source (24 Files)
          </button>
        </div>
      </div>

      {/* Bottom Safe Margin Control Hint Line */}
      <div className="text-xs font-mono text-slate-400 tracking-wide">
        WASD Move · Shift Sprint · E Trigger ProximityPrompt · 1 / 2 Equipment Slots · P Pause
      </div>
    </div>
  );
};
