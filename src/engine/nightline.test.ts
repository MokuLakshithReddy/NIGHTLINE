import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  NightlineServerEngine,
  GAME_CONFIG,
  HUB_INTERACTABLES,
} from './nightlineEngine';

const ROOT_DIR = process.cwd();

function collectLuaFiles(dirPath: string): string[] {
  const results: string[] = [];
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      results.push(...collectLuaFiles(fullPath));
    } else if (entry.isFile() && entry.name.endsWith('.lua')) {
      results.push(fullPath);
    }
  }
  return results;
}

test('Milestone 0: Rojo default.project.json maps valid existing paths and required documentation exists', () => {
  const projectJsonPath = path.join(ROOT_DIR, 'default.project.json');
  assert.equal(fs.existsSync(projectJsonPath), true, 'default.project.json must exist');

  const projectData = JSON.parse(fs.readFileSync(projectJsonPath, 'utf8'));
  assert.equal(projectData.name, 'NIGHTLINE_Last_Train');

  const verifyTreePaths = (node: Record<string, unknown>) => {
    for (const [key, value] of Object.entries(node)) {
      if (key === '$path' && typeof value === 'string') {
        const resolved = path.join(ROOT_DIR, value);
        assert.equal(
          fs.existsSync(resolved),
          true,
          `Rojo $path "${value}" must exist on disk`
        );
      } else if (value && typeof value === 'object' && !Array.isArray(value)) {
        verifyTreePaths(value as Record<string, unknown>);
      }
    }
  };
  verifyTreePaths(projectData.tree);

  const requiredDocs = [
    'README.md',
    'docs/ARCHITECTURE.md',
    'docs/DEVELOPMENT_PROGRESS.md',
    'docs/TESTING.md',
    'docs/KNOWN_ISSUES.md',
    '.luaurc',
    'selene.toml',
    'stylua.toml',
    'rokit.toml',
  ];
  for (const docRelPath of requiredDocs) {
    assert.equal(
      fs.existsSync(path.join(ROOT_DIR, docRelPath)),
      true,
      `Required project file ${docRelPath} must exist`
    );
  }
});

test('Milestone 0: All Luau modules enforce --!strict header and balanced block structure', () => {
  const robloxDir = path.join(ROOT_DIR, 'roblox');
  const luaFiles = collectLuaFiles(robloxDir);
  assert.equal(luaFiles.length >= 16, true, 'Expected at least 16 Luau modules and scripts');

  for (const filePath of luaFiles) {
    const content = fs.readFileSync(filePath, 'utf8');
    const relPath = path.relative(ROOT_DIR, filePath);

    assert.equal(
      content.startsWith('--!strict'),
      true,
      `${relPath} must start with --!strict`
    );

    // Strip block comments and line comments before checking block token balance
    const withoutBlockComments = content.replace(/--\[\[[\s\S]*?\]\]/g, '');
    const withoutComments = withoutBlockComments
      .split('\n')
      .map((line) => line.replace(/--.*$/, ''))
      .join('\n')
      .replace(/"(?:\\.|[^"\\])*"/g, '""')
      // Strip Luau inline ternary expressions (`= if ... then ... else ...` or `return if ... then ... else ...`)
      .replace(/(?:=|\breturn|,|\()\s*if\b[\s\S]*?\bthen\b[\s\S]*?\belse\b/g, '');

    const openers = (
      withoutComments.match(/\b(function|if|do|repeat)\b/g) || []
    ).length;
    const closers = (withoutComments.match(/\b(end|until)\b/g) || []).length;

    assert.equal(
      openers,
      closers,
      `${relPath} must have balanced Luau block openers (${openers}) and closers (${closers})`
    );
  }
});

test('Milestone 1: RoundService transitions from WAITING through full 8-state cycle and cleans up', () => {
  const engine = new NightlineServerEngine();
  assert.equal(engine.state, 'WAITING');

  // Joining Player 1 starts INTERMISSION (15s)
  const joinRes = engine.addPlayer(101, 'Avery');
  assert.equal(joinRes.ok, true);
  assert.equal(engine.state, 'INTERMISSION');
  assert.equal(engine.roundNumber, 1);
  assert.equal(engine.phaseRemainingSeconds, GAME_CONFIG.RoundDurations.INTERMISSION);

  // Advance INTERMISSION -> BOARDING (45s)
  engine.stepSimulation(15);
  assert.equal(engine.state, 'BOARDING');
  assert.equal(engine.players.get(101)?.status, 'BOARDED');

  // Advance BOARDING -> TRAVEL (20s)
  engine.advanceToNextPhase();
  assert.equal(engine.state, 'TRAVEL');
  assert.equal(engine.players.get(101)?.status, 'IN_EXPEDITION');
  assert.equal(engine.activeExpeditionUserIds.has(101), true);

  // Advance TRAVEL -> EXPLORATION (180s)
  engine.advanceToNextPhase();
  assert.equal(engine.state, 'EXPLORATION');
  assert.equal(engine.runtimeStationObjectsCount > 0, true);

  // Advance EXPLORATION -> EXTRACTION (60s)
  engine.advanceToNextPhase();
  assert.equal(engine.state, 'EXTRACTION');

  // Advance EXTRACTION -> RETURN (20s)
  engine.advanceToNextPhase();
  assert.equal(engine.state, 'RETURN');
  assert.equal(engine.players.get(101)?.status, 'EXTRACTED');

  // Advance RETURN -> RESULTS (30s)
  engine.advanceToNextPhase();
  assert.equal(engine.state, 'RESULTS');

  // Advance RESULTS -> CleanupRound -> Next INTERMISSION
  engine.advanceToNextPhase();
  assert.equal(engine.state, 'INTERMISSION');
  assert.equal(engine.roundNumber, 2);
  assert.equal(engine.runtimeStationObjectsCount, 0);
  assert.equal(engine.players.get(101)?.status, 'HUB_WAITING');
});

test('Milestone 1: Late-joining player during active round remains in safe Train Hub and does not enter active station', () => {
  const engine = new NightlineServerEngine();
  engine.addPlayer(101, 'Avery');
  engine.advanceToNextPhase(); // BOARDING
  engine.advanceToNextPhase(); // TRAVEL
  engine.advanceToNextPhase(); // EXPLORATION
  assert.equal(engine.state, 'EXPLORATION');

  // Player 2 joins mid-expedition
  engine.addPlayer(202, 'Morgan');
  const lateJoiner = engine.players.get(202);
  assert.ok(lateJoiner);
  assert.equal(lateJoiner.status, 'HUB_WAITING');
  assert.equal(engine.activeExpeditionUserIds.has(202), false);
  assert.equal(engine.activeExpeditionUserIds.has(101), true);
});

test('Milestone 1: Disconnecting all active expedition players safely terminates the round and cleans up', () => {
  const engine = new NightlineServerEngine();
  engine.addPlayer(101, 'Avery');
  engine.advanceToNextPhase(); // BOARDING
  engine.advanceToNextPhase(); // TRAVEL
  engine.advanceToNextPhase(); // EXPLORATION
  assert.equal(engine.runtimeStationObjectsCount > 0, true);

  engine.removePlayer(101);
  assert.equal(engine.state, 'WAITING');
  assert.equal(engine.runtimeStationObjectsCount, 0);
  assert.equal(engine.activeExpeditionUserIds.size, 0);
});

test('Milestone 1: SecurityService & InventoryService reject invalid equipment, out-of-phase changes, far prompts, and rate spam', () => {
  const engine = new NightlineServerEngine();
  engine.addPlayer(101, 'Avery');

  // Valid equipment request in INTERMISSION
  engine.stepSimulation(1.0);
  const eqValid = engine.handleEquipmentRequest(101, 2, 'Flare');
  assert.equal(eqValid.ok, true);
  assert.equal(engine.players.get(101)?.equipmentSlots[2], 'Flare');

  // Invalid item ID rejected
  engine.stepSimulation(1.0);
  const eqInvalidItem = engine.handleEquipmentRequest(101, 1, 'AdminMinigun');
  assert.equal(eqInvalidItem.ok, false);
  assert.equal(eqInvalidItem.reason, 'InvalidItemId');

  // Invalid slot index rejected
  engine.stepSimulation(1.0);
  const eqInvalidSlot = engine.handleEquipmentRequest(101, 99, 'Flashlight');
  assert.equal(eqInvalidSlot.ok, false);
  assert.equal(eqInvalidSlot.reason, 'InvalidSlotIndex');

  // Invalid destination vote rejected
  const voteInvalid = engine.handleDestinationVote(101, 'Station999');
  assert.equal(voteInvalid.ok, false);
  assert.equal(voteInvalid.reason, 'InvalidStationId');

  // Far-distance ProximityPrompt rejected (Player 1 spawns at z=12, DestinationConsole is at z=-34 -> distance ~46 > 14)
  engine.stepSimulation(1.0);
  const farPrompt = engine.handleProximityPromptTriggered(101, 'DestinationConsole');
  assert.equal(farPrompt.ok, false);
  assert.equal(farPrompt.reason, 'OutOfRange');

  // Move player next to DestinationConsole and trigger prompt -> accepted!
  const player = engine.players.get(101)!;
  const consoleObj = HUB_INTERACTABLES.find((i) => i.id === 'DestinationConsole')!;
  player.position = { x: consoleObj.position.x, z: consoleObj.position.z + 3 };
  engine.stepSimulation(1.0);
  const nearPrompt = engine.handleProximityPromptTriggered(101, 'DestinationConsole');
  assert.equal(nearPrompt.ok, true);

  // Rate limit spam test (> 6 calls within 1.0s window)
  let rateLimitedCount = 0;
  for (let i = 0; i < 10; i++) {
    const res = engine.handleDestinationVote(101, 'Station001');
    if (res.reason === 'RateLimited') {
      rateLimitedCount += 1;
    }
  }
  assert.equal(rateLimitedCount > 0, true, 'Excessive remote calls in 1s window must be rate-limited');
});
