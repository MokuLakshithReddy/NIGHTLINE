import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  NightlineServerEngine,
  GAME_CONFIG,
  HUB_INTERACTABLES,
  STATION_ENTRY_OFFSETS,
} from './nightlineEngine';
import {
  ensureToolchainInstalled,
  runRojoAndStaticToolchainChecks,
  runActualLuauModulesInVm,
} from './luauVmRunner';

const ROOT_DIR = process.cwd();

test('Priority 1 & Fix 5: package-lock.json, CI workflow npm cache config, and toolchain bootstrap script are valid for clean-checkout npm ci', () => {
  const packageLockPath = path.join(ROOT_DIR, 'package-lock.json');
  assert.equal(
    fs.existsSync(packageLockPath),
    true,
    'package-lock.json must exist at repository root for npm ci and actions/setup-node caching'
  );
  const lockData = JSON.parse(fs.readFileSync(packageLockPath, 'utf8'));
  assert.equal(
    typeof lockData.lockfileVersion === 'number' && lockData.lockfileVersion >= 3,
    true,
    'package-lock.json must be a valid npm v3+ lockfile'
  );

  const ciYmlPath = path.join(ROOT_DIR, '.github', 'workflows', 'ci.yml');
  assert.equal(fs.existsSync(ciYmlPath), true, '.github/workflows/ci.yml must exist');
  const ciYmlContent = fs.readFileSync(ciYmlPath, 'utf8');
  assert.equal(
    ciYmlContent.includes("cache-dependency-path: 'package-lock.json'"),
    true,
    'ci.yml must configure cache-dependency-path: package-lock.json for actions/setup-node'
  );
  assert.equal(
    ciYmlContent.includes('run: npm ci'),
    true,
    'ci.yml must run npm ci'
  );

  const bootstrapScriptPath = path.join(ROOT_DIR, 'scripts', 'bootstrap-toolchain.sh');
  assert.equal(
    fs.existsSync(bootstrapScriptPath),
    true,
    'scripts/bootstrap-toolchain.sh must exist for clean-checkout reproducibility'
  );

  const toolchain = ensureToolchainInstalled();
  assert.equal(fs.existsSync(toolchain.luauBin), true, 'Official luau CLI VM binary must exist');
  assert.equal(
    fs.existsSync(toolchain.luauAnalyzeBin),
    true,
    'Official luau-analyze CLI binary must exist'
  );
  assert.equal(
    fs.existsSync(toolchain.luauLspBin),
    true,
    'luau-lsp binary must exist'
  );
  assert.equal(
    fs.existsSync(toolchain.globalTypesPath),
    true,
    'Roblox globalTypes.d.luau type definitions must exist'
  );
  assert.equal(fs.existsSync(toolchain.rojoBin), true, 'Rojo 7.7.1 binary must exist');
  assert.equal(fs.existsSync(toolchain.styluaBin), true, 'StyLua binary must exist');
  assert.equal(fs.existsSync(toolchain.seleneBin), true, 'Selene binary must exist');

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

test('Fix 5 & Issue 05 (Toolchain): Official Rojo 7.7.1 build, luau-analyze, luau-lsp --!strict typecheck, Selene linter, and StyLua formatter pass on /roblox', () => {
  const results = runRojoAndStaticToolchainChecks();
  assert.equal(results.rojoBuildOk, true, 'rojo build default.project.json must succeed');
  assert.equal(
    results.rbxlSizeBytes > 20000,
    true,
    `Built .rbxl file must be non-empty (got ${results.rbxlSizeBytes} bytes)`
  );
  assert.equal(results.luauAnalyzeOk, true, 'Official luau-analyze binary must be operational');
  assert.equal(
    results.luauLspOutput,
    '',
    `luau-lsp analyze must report 0 type/lint errors, got: ${results.luauLspOutput}`
  );
  assert.equal(results.styluaOk, true, 'stylua --check roblox must pass');
  assert.equal(results.seleneOk, true, 'selene roblox must pass with 0 warnings/errors');
  assert.equal(
    fs.existsSync(path.join(ROOT_DIR, 'roblox.yml')),
    false,
    'selene must not pollute the repository root with an untracked roblox.yml file'
  );
});

test('Priorities 2, 3 & 4 (Luau Runtime VM): Actual /roblox/**/*.lua modules verify Station 001 physical geometry, CanCollide=true spawns, and 10-stage round lifecycle', () => {
  const vmResult = runActualLuauModulesInVm();
  assert.equal(
    vmResult.passed,
    true,
    `Actual Luau VM test suite must pass: ${vmResult.assertionsSummary}`
  );
  assert.equal(
    vmResult.stdoutLines.some((line) =>
      line.includes('Priority 2 & Fix 1: Physically playable Station 001 environment, CanCollide=true spawns, and collision walls verified')
    ),
    true,
    'Luau VM must verify Priority 2 (Station 001 physical floors, CanCollide=true spawns, and collision boundaries)'
  );
  assert.equal(
    vmResult.stdoutLines.some((line) =>
      line.includes('Fix 1: All 6 station spawn positions verified outside extraction zone')
    ),
    true,
    'Luau VM must verify Fix 1 (all 6 station spawn positions outside extraction zone)'
  );
  assert.equal(
    vmResult.stdoutLines.some((line) =>
      line.includes('Fix 2 & Issue 01: Dead characters are never healed/pivoted in-place')
    ),
    true,
    'Luau VM must verify Fix 2 (dead characters never healed/pivoted in Humanoid.Died; fresh-character respawn flow)'
  );
  assert.equal(
    vmResult.stdoutLines.some((line) =>
      line.includes('Fix 3 & Issue 03: Horizontal + vertical movement validation')
    ),
    true,
    'Luau VM must verify Fix 3 (horizontal + vertical movement validation)'
  );
  assert.equal(
    vmResult.stdoutLines.some((line) =>
      line.includes('Fix 4: All-crew-eliminated immediate round termination verified')
    ),
    true,
    'Luau VM must verify Fix 4 (all-crew-eliminated immediate round termination)'
  );
  assert.equal(
    vmResult.stdoutLines.some((line) =>
      line.includes('Priority 3: Complete 10-stage round lifecycle verified end-to-end')
    ),
    true,
    'Luau VM must verify Priority 3 (complete 10-stage round lifecycle)'
  );
  assert.equal(
    vmResult.stdoutLines.some((line) => line.includes('ALL_LUAU_VM_TESTS_PASSED')),
    true,
    'Luau VM must emit ALL_LUAU_VM_TESTS_PASSED'
  );
});

test('Workbench Mirror — Fix 1: All 6 active station entry spawn positions are outside the extraction zone and no player auto-extracts on arrival', () => {
  const engine = new NightlineServerEngine();
  const userIds = [101, 102, 103, 104, 105, 106];

  for (const uid of userIds) {
    engine.addPlayer(uid, `Crew_${uid}`);
  }

  assert.equal(STATION_ENTRY_OFFSETS.length, 6);
  for (let i = 0; i < STATION_ENTRY_OFFSETS.length; i += 1) {
    const spot = STATION_ENTRY_OFFSETS[i];
    const distToExtract = Math.hypot(
      spot.x - GAME_CONFIG.EXTRACTION_ZONE_POSITION.x,
      spot.z - GAME_CONFIG.EXTRACTION_ZONE_POSITION.z
    );
    assert.equal(
      distToExtract > GAME_CONFIG.EXTRACTION_ZONE_RADIUS,
      true,
      `Station entry slot #${i + 1} must be strictly outside ExtractionPlatformZone (dist=${distToExtract.toFixed(1)} > ${GAME_CONFIG.EXTRACTION_ZONE_RADIUS})`
    );
  }

  engine.advanceToNextPhase(); // BOARDING
  engine.advanceToNextPhase(); // TRAVEL
  engine.advanceToNextPhase(); // EXPLORATION
  assert.equal(engine.state, 'EXPLORATION');

  for (const uid of userIds) {
    assert.equal(
      engine.isPlayerInExtractionZone(uid),
      false,
      `Player ${uid} must NOT be inside the extraction zone upon entering Station 001`
    );
  }

  // Transition into EXTRACTION without moving players -> none of the 6 players can extract from their station entry spawn
  engine.advanceToNextPhase(); // EXTRACTION
  assert.equal(engine.state, 'EXTRACTION');
  for (const uid of userIds) {
    const res = engine.tryExtractPlayer(uid);
    assert.equal(res.ok, false);
    assert.equal(res.reason, 'OutOfExtractionZone');
    assert.equal(engine.players.get(uid)?.status, 'IN_EXPEDITION');
  }
});

test('Workbench Mirror — Fix 2 & Fix 4: State-aware respawning, slot allocation, and immediate round termination when all active crew are eliminated', () => {
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
  assert.equal(
    p4.spawnSlot,
    2,
    'Joining player must receive freed slot #2 instead of colliding with slot #3'
  );

  // Advance to EXPLORATION (3 crew members: 101, 303, 404)
  engine.advanceToNextPhase(); // BOARDING
  engine.advanceToNextPhase(); // TRAVEL
  engine.advanceToNextPhase(); // EXPLORATION
  assert.equal(engine.state, 'EXPLORATION');

  // Eliminate Player 101 -> respawns in Recovery Bay (Z >= 35) while round stays in EXPLORATION
  const elim1 = engine.eliminatePlayer(101, 'HollowStrike');
  assert.equal(elim1.ok, true);
  assert.equal(engine.players.get(101)?.status, 'ELIMINATED');
  assert.equal(engine.players.get(101)!.position.z >= 35, true);
  assert.equal(engine.state, 'EXPLORATION');

  // Active expedition player 303 respawns at Station 001 entry spawn (Z >= 18), outside extraction zone
  const activeRespawn = engine.handleCharacterRespawn(303);
  assert.equal(activeRespawn.spawnZone, 'ACTIVE_STATION');
  assert.equal(engine.players.get(303)!.position.z >= 18, true);
  assert.equal(engine.isPlayerInExtractionZone(303), false);

  // Fix 4: Eliminate remaining crew (303 and 404) -> Round must immediately terminate into RETURN with FAILED outcome
  engine.eliminatePlayer(303, 'HollowStrike');
  assert.equal(engine.state, 'EXPLORATION', 'Round continues while 404 is still alive');

  engine.eliminatePlayer(404, 'HollowStrike');
  assert.equal(
    engine.state,
    'RETURN',
    'Round must immediately transition to RETURN as soon as all active crew are eliminated'
  );
  assert.equal(engine.lastOutcome, 'FAILED');
});

test('Workbench Mirror — Fix 3 & Issue 03/04: Horizontal + vertical movement validation and physical extraction zone enforcement', () => {
  const engine = new NightlineServerEngine();
  engine.addPlayer(101, 'Avery');
  engine.addPlayer(202, 'Morgan');

  // Server-validated sprint
  const sprintOn = engine.handleSprintRequest(101, true);
  assert.equal(sprintOn.ok, true);
  assert.equal(engine.players.get(101)?.walkSpeed, GAME_CONFIG.SPRINT_SPEED);

  const p1 = engine.players.get(101)!;
  const startPos = { ...p1.position };

  // Legitimate jump (+11 studs Y in 0.25s) -> accepted
  const validJump = engine.validatePlayerMovement(
    101,
    { x: startPos.x, z: startPos.z - 2 },
    0.25,
    11
  );
  assert.equal(validJump.ok, true);
  assert.equal(validJump.reason, 'ValidMovement');

  // Legitimate gravity fall (-28 studs Y in 0.25s) -> accepted
  const posAfterJump = { ...p1.position };
  const validFall = engine.validatePlayerMovement(
    101,
    { x: posAfterJump.x, z: posAfterJump.z - 2 },
    0.25,
    -28
  );
  assert.equal(validFall.ok, true);
  assert.equal(validFall.reason, 'ValidMovement');

  // Horizontal speed exploit -> rejected & rubberbanded
  const posBeforeHack = { ...p1.position };
  const horizExploit = engine.validatePlayerMovement(
    101,
    { x: posBeforeHack.x, z: posBeforeHack.z - 80 },
    0.25,
    0
  );
  assert.equal(horizExploit.ok, false);
  assert.equal(horizExploit.reason, 'SpeedAnomalyRubberbanded');
  assert.deepEqual(engine.players.get(101)?.position, posBeforeHack);

  // Vertical upward fly exploit (+45 studs Y in 0.25s) -> rejected
  const upExploit = engine.validatePlayerMovement(101, posBeforeHack, 0.25, 45);
  assert.equal(upExploit.ok, false);
  assert.equal(upExploit.reason, 'RubberbandedVerticalUpwardAnomaly');

  // Vertical downward noclip exploit (-120 studs Y in 0.25s) -> rejected
  const downExploit = engine.validatePlayerMovement(101, posBeforeHack, 0.25, -120);
  assert.equal(downExploit.ok, false);
  assert.equal(downExploit.reason, 'RubberbandedVerticalDownwardAnomaly');

  // Issue 04: Advance to EXTRACTION. Move Player 101 into physical Extraction Zone (16, -8); leave Player 202 at station arrival spawn.
  engine.advanceToNextPhase(); // BOARDING
  engine.advanceToNextPhase(); // TRAVEL
  engine.advanceToNextPhase(); // EXPLORATION
  engine.advanceToNextPhase(); // EXTRACTION
  assert.equal(engine.state, 'EXTRACTION');

  // Player 202 is at their station entry spawn (Z >= 18) -> tryExtractPlayer rejected
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
