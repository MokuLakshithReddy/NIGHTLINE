import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  NightlineServerEngine,
  GAME_CONFIG,
  HUB_INTERACTABLES,
} from './nightlineEngine';
import {
  runRojoAndStaticToolchainChecks,
  runActualLuauModulesInVm,
} from './luauVmRunner';

const ROOT_DIR = process.cwd();

test('Issue 06 & 07: rokit.toml pins Rojo 7.7.1+ and default.project.json omits deprecated Workspace.FilteringEnabled', () => {
  const projectJsonPath = path.join(ROOT_DIR, 'default.project.json');
  assert.equal(fs.existsSync(projectJsonPath), true, 'default.project.json must exist');

  const projectData = JSON.parse(fs.readFileSync(projectJsonPath, 'utf8'));
  assert.equal(projectData.name, 'NIGHTLINE_Last_Train');

  const workspaceProps = projectData.tree?.Workspace?.$properties ?? {};
  assert.equal(
    'FilteringEnabled' in workspaceProps,
    false,
    'Deprecated Workspace.FilteringEnabled must not be present in default.project.json'
  );

  const rokitToml = fs.readFileSync(path.join(ROOT_DIR, 'rokit.toml'), 'utf8');
  assert.equal(
    rokitToml.includes('rojo-rbx/rojo@7.7.1'),
    true,
    'rokit.toml must pin rojo 7.7.1 or newer'
  );
});

test('Issue 05 (Toolchain): Official Rojo 7.7.1 build, luau-lsp --!strict typecheck, Selene linter, and StyLua formatter pass on /roblox', () => {
  const results = runRojoAndStaticToolchainChecks();
  assert.equal(results.rojoBuildOk, true, 'rojo build default.project.json must succeed');
  assert.equal(
    results.rbxlSizeBytes > 20000,
    true,
    `Built .rbxl file must be non-empty (got ${results.rbxlSizeBytes} bytes)`
  );
  assert.equal(
    results.luauLspOutput,
    '',
    `luau-lsp analyze must report 0 type/lint errors, got: ${results.luauLspOutput}`
  );
  assert.equal(results.styluaOk, true, 'stylua --check roblox must pass');
  assert.equal(results.seleneOk, true, 'selene roblox must pass with 0 warnings/errors');
});

test('Issue 05 (Luau Runtime VM): Actual /roblox/**/*.lua modules execute inside the official Luau VM and pass Issues 01-04 integration checks', () => {
  const vmResult = runActualLuauModulesInVm();
  assert.equal(
    vmResult.passed,
    true,
    `Actual Luau VM test suite must pass: ${vmResult.assertionsSummary}`
  );
  assert.equal(
    vmResult.stdoutLines.some((line) => line.includes('ALL_LUAU_VM_TESTS_PASSED')),
    true,
    'Luau VM must emit ALL_LUAU_VM_TESTS_PASSED'
  );
});

test('Workbench Mirror: Issue 01 (State-aware respawn & elimination) and Issue 02 (Explicit 1..6 spawn-slot allocation)', () => {
  const engine = new NightlineServerEngine();

  // Issue 02: Allocate slots 1, 2, 3 -> remove player 2 -> next player gets freed slot 2
  const p1 = engine.addPlayer(101, 'Avery').player!;
  const p2 = engine.addPlayer(202, 'Morgan').player!;
  const p3 = engine.addPlayer(303, 'Quinn').player!;
  assert.equal(p1.spawnSlot, 1);
  assert.equal(p2.spawnSlot, 2);
  assert.equal(p3.spawnSlot, 3);

  engine.removePlayer(202);
  const p4 = engine.addPlayer(404, 'Riley').player!;
  assert.equal(p4.spawnSlot, 2, 'Joining player must receive freed slot #2 instead of colliding with slot #3');

  // Issue 01: Advance to EXPLORATION and eliminate Player 101 -> respawns in Recovery Bay and cannot re-enter active station
  engine.advanceToNextPhase(); // BOARDING
  engine.advanceToNextPhase(); // TRAVEL
  engine.advanceToNextPhase(); // EXPLORATION
  assert.equal(engine.state, 'EXPLORATION');

  const elimRes = engine.eliminatePlayer(101, 'HollowStrike');
  assert.equal(elimRes.ok, true);
  assert.equal(engine.players.get(101)?.status, 'ELIMINATED');

  const respawnRes = engine.handleCharacterRespawn(101);
  assert.equal(respawnRes.spawnZone, 'RECOVERY_BAY');
  assert.equal(engine.players.get(101)!.position.z >= 35, true);

  // Active expedition player 303 respawns inside active station boarding bay, not Hub
  const activeRespawn = engine.handleCharacterRespawn(303);
  assert.equal(activeRespawn.spawnZone, 'ACTIVE_STATION');
  assert.equal(engine.players.get(303)!.position.z <= -14, true);
});

test('Workbench Mirror: Issue 03 (Server-owned sprint eligibility & movement speed rubberbanding) and Issue 04 (Physical Extraction Zone validation)', () => {
  const engine = new NightlineServerEngine();
  engine.addPlayer(101, 'Avery');
  engine.addPlayer(202, 'Morgan');

  // Issue 03: Server-validated sprint
  const sprintOn = engine.handleSprintRequest(101, true);
  assert.equal(sprintOn.ok, true);
  assert.equal(engine.players.get(101)?.walkSpeed, GAME_CONFIG.SPRINT_SPEED);

  // Invalid sprint payload rejected
  const sprintInvalid = engine.handleSprintRequest(101, 'fast' as unknown);
  assert.equal(sprintInvalid.ok, false);
  assert.equal(sprintInvalid.reason, 'InvalidPayload');

  // Speed exploit displacement rubberbanded
  const p1 = engine.players.get(101)!;
  const startPos = { ...p1.position };
  const exploitCheck = engine.validatePlayerMovement(101, { x: startPos.x, z: startPos.z - 80 }, 0.25);
  assert.equal(exploitCheck.ok, false);
  assert.equal(exploitCheck.reason, 'SpeedAnomalyRubberbanded');
  assert.deepEqual(engine.players.get(101)?.position, startPos);

  // Issue 04: Advance to EXTRACTION. Move Player 101 into physical Extraction Zone (15, -8); leave Player 202 far away.
  engine.advanceToNextPhase(); // BOARDING
  engine.advanceToNextPhase(); // TRAVEL
  engine.advanceToNextPhase(); // EXPLORATION
  engine.advanceToNextPhase(); // EXTRACTION
  assert.equal(engine.state, 'EXTRACTION');

  // Player 202 is far from extraction zone -> tryExtractPlayer rejected
  p1.position = { x: 0, z: -20 };
  engine.players.get(202)!.position = { x: 0, z: 25 };
  const farExtract = engine.tryExtractPlayer(202);
  assert.equal(farExtract.ok, false);
  assert.equal(farExtract.reason, 'OutOfExtractionZone');

  // Move Player 101 into physical Extraction Platform Zone -> extracted!
  const moveExtract = engine.movePlayerToExtractionZone(101);
  assert.equal(moveExtract.ok, true);
  assert.equal(engine.players.get(101)?.status, 'EXTRACTED');

  // Advance EXTRACTION -> RETURN: Player 101 remains EXTRACTED, Player 202 is marked ELIMINATED (left behind)
  engine.advanceToNextPhase(); // RETURN
  assert.equal(engine.state, 'RETURN');
  assert.equal(engine.players.get(101)?.status, 'EXTRACTED');
  assert.equal(engine.players.get(202)?.status, 'ELIMINATED');
  assert.equal(engine.lastOutcome, 'SUCCESS');
});

test('Workbench Mirror: SecurityService & InventoryService reject invalid equipment, out-of-phase changes, far prompts, and rate spam', () => {
  const engine = new NightlineServerEngine();
  engine.addPlayer(101, 'Avery');

  engine.stepSimulation(1.0);
  const eqValid = engine.handleEquipmentRequest(101, 2, 'Flare');
  assert.equal(eqValid.ok, true);
  assert.equal(engine.players.get(101)?.equipmentSlots[2], 'Flare');

  engine.stepSimulation(1.0);
  const eqInvalidItem = engine.handleEquipmentRequest(101, 1, 'AdminMinigun');
  assert.equal(eqInvalidItem.ok, false);
  assert.equal(eqInvalidItem.reason, 'InvalidItemId');

  engine.stepSimulation(1.0);
  const farPrompt = engine.handleProximityPromptTriggered(101, 'DestinationConsole');
  assert.equal(farPrompt.ok, false);
  assert.equal(farPrompt.reason, 'OutOfRange');

  const player = engine.players.get(101)!;
  const consoleObj = HUB_INTERACTABLES.find((i) => i.id === 'DestinationConsole')!;
  player.position = { x: consoleObj.position.x, z: consoleObj.position.z + 3 };
  engine.stepSimulation(1.0);
  const nearPrompt = engine.handleProximityPromptTriggered(101, 'DestinationConsole');
  assert.equal(nearPrompt.ok, true);
});
