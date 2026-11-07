/**
 * nightlineEngine.ts
 * Authoritative TypeScript mirror of the NIGHTLINE: LAST TRAIN Luau Server Services
 * (SecurityService, HubService, InventoryService, RoundService, InteractionService).
 * Used for both deterministic unit testing (`node:test`) and the interactive Train Hub Studio Workbench.
 */

export type RoundState =
  | 'WAITING'
  | 'INTERMISSION'
  | 'BOARDING'
  | 'TRAVEL'
  | 'EXPLORATION'
  | 'EXTRACTION'
  | 'RETURN'
  | 'RESULTS';

export type PlayerRoundStatus =
  | 'HUB_WAITING'
  | 'BOARDED'
  | 'IN_EXPEDITION'
  | 'EXTRACTED'
  | 'ELIMINATED'
  | 'DISCONNECTED';

export type StationId = 'Station001';
export type MissionTemplateId = 'RestorePower' | 'RecoverCargo' | 'RepairSignal';
export type EquipmentItemId = 'Flashlight' | 'Flare';
export type NotificationSeverity = 'Info' | 'Warning' | 'Success' | 'Danger';

export interface Vec2 {
  x: number; // X in Roblox studs (-11 to +11 across train width)
  z: number; // Z in Roblox studs (-42 front locomotive bulkhead to +42 rear bulkhead)
}

export interface HubInteractable {
  id: string;
  name: string;
  objectText: string;
  actionText: string;
  tag: 'NightlineDestinationTerminal' | 'NightlineEquipmentLocker' | 'NightlineBoardingZone';
  position: Vec2;
  size: { w: number; d: number };
  stationId?: StationId;
  itemId?: EquipmentItemId;
  slotIndex?: 1 | 2;
}

export interface PlayerEntity {
  userId: number;
  name: string;
  displayName: string;
  position: Vec2;
  velocity: Vec2;
  facingAngle: number;
  isSprinting: boolean;
  health: number;
  maxHealth: number;
  status: PlayerRoundStatus;
  isReady: boolean;
  votedStationId: StationId;
  equipmentSlots: {
    1: EquipmentItemId | null;
    2: EquipmentItemId | null;
  };
  activeSlot: 1 | 2;
  missionItems: Record<string, number>;
  isLocal?: boolean;
}

export interface NotificationEntry {
  id: number;
  targetUserId: number | 'ALL';
  messageKey: string;
  messageText: string;
  severity: NotificationSeverity;
  timestamp: number;
}

export interface RemoteLogEntry {
  id: number;
  timestamp: number;
  direction: 'Server->Clients' | 'Server->Client' | 'Client->Server';
  remoteName:
    | 'RoundStateChanged'
    | 'ObjectiveUpdated'
    | 'PlayerStatusUpdated'
    | 'InventoryUpdated'
    | 'Notification'
    | 'RequestEquipment'
    | 'RequestDestinationVote'
    | 'PromptTriggered';
  actorName: string;
  accepted: boolean;
  reason: string;
  payloadSummary: string;
}

export const GAME_CONFIG = {
  GAME_TITLE: 'NIGHTLINE: LAST TRAIN',
  VERSION: '0.1.0-milestone1',
  MAX_PLAYERS_PER_SERVER: 6,
  MIN_CREW_TO_START: 1,
  EQUIPMENT_SLOTS: 2,
  DEFAULT_STATION_ID: 'Station001' as StationId,
  RoundDurations: {
    WAITING: 0,
    INTERMISSION: 15,
    BOARDING: 45,
    TRAVEL: 20,
    EXPLORATION: 180,
    EXTRACTION: 60,
    RETURN: 20,
    RESULTS: 30,
  } satisfies Record<RoundState, number>,
  WALK_SPEED: 14,
  SPRINT_SPEED: 22,
  DEFAULT_MAX_HEALTH: 100,
  MAX_INTERACTION_DISTANCE: 14.0,
  PROMPT_COOLDOWN_SECONDS: 0.5,
  EQUIPMENT_COOLDOWN_SECONDS: 0.25,
  REMOTE_RATE_LIMIT_WINDOW: 1.0,
  REMOTE_MAX_CALLS_PER_WINDOW: 6,
} as const;

export const MISSION_TEMPLATES: Record<
  MissionTemplateId,
  { id: MissionTemplateId; title: string; instruction: string; requiredProgress: number }
> = {
  RestorePower: {
    id: 'RestorePower',
    title: 'Restore Auxiliary Power',
    instruction: 'Find and install 3 transit fuses in designated maintenance sockets.',
    requiredProgress: 3,
  },
  RecoverCargo: {
    id: 'RecoverCargo',
    title: 'Recover Lost Cargo',
    instruction: 'Locate and deliver 2 sealed cargo containers to the platform drop point.',
    requiredProgress: 2,
  },
  RepairSignal: {
    id: 'RepairSignal',
    title: 'Repair the Dispatch Signal',
    instruction: 'Activate 3 communication terminals across the terminal concourse.',
    requiredProgress: 3,
  },
};

export const ORDERED_MISSION_IDS: MissionTemplateId[] = [
  'RestorePower',
  'RecoverCargo',
  'RepairSignal',
];

export const HUB_SPAWN_OFFSETS: Vec2[] = [
  { x: -5, z: 12 },
  { x: 5, z: 12 },
  { x: -5, z: 22 },
  { x: 5, z: 22 },
  { x: -5, z: 32 },
  { x: 5, z: 32 },
];

export const BOARDING_BAY_OFFSETS: Vec2[] = [
  { x: -4, z: -24 },
  { x: 4, z: -24 },
  { x: -4, z: -19 },
  { x: 4, z: -19 },
  { x: -4, z: -14 },
  { x: 4, z: -14 },
];

export const HUB_INTERACTABLES: HubInteractable[] = [
  {
    id: 'DestinationConsole',
    name: 'DestinationConsole',
    objectText: 'Dispatch Navigation Console',
    actionText: 'Confirm Route: Station 001',
    tag: 'NightlineDestinationTerminal',
    position: { x: 0, z: -34 },
    size: { w: 6, d: 2.5 },
    stationId: 'Station001',
  },
  {
    id: 'EquipmentLocker_Flashlight',
    name: 'EquipmentLocker_Flashlight',
    objectText: 'Crew Equipment Locker (Slot 1)',
    actionText: 'Equip Service Flashlight',
    tag: 'NightlineEquipmentLocker',
    position: { x: -8.8, z: -12 },
    size: { w: 2.2, d: 4 },
    itemId: 'Flashlight',
    slotIndex: 1,
  },
  {
    id: 'EquipmentLocker_Flare',
    name: 'EquipmentLocker_Flare',
    objectText: 'Crew Equipment Locker (Slot 2)',
    actionText: 'Equip Acoustic Signal Flare',
    tag: 'NightlineEquipmentLocker',
    position: { x: -8.8, z: -4 },
    size: { w: 2.2, d: 4 },
    itemId: 'Flare',
    slotIndex: 2,
  },
  {
    id: 'BoardingReadyGate',
    name: 'BoardingReadyGate',
    objectText: 'Expedition Boarding Hatch',
    actionText: 'Toggle Boarding Ready',
    tag: 'NightlineBoardingZone',
    position: { x: 8.8, z: -8 },
    size: { w: 2.0, d: 8 },
  },
];

interface RateBucket {
  windowStart: number;
  count: number;
}

export class NightlineServerEngine {
  public state: RoundState = 'WAITING';
  public roundNumber = 0;
  public clockSeconds = 0;
  public phaseRemainingSeconds = 0;
  public selectedStationId: StationId = GAME_CONFIG.DEFAULT_STATION_ID;
  public selectedMissionId: MissionTemplateId = 'RestorePower';
  public players: Map<number, PlayerEntity> = new Map();
  public activeExpeditionUserIds: Set<number> = new Set();
  public notifications: NotificationEntry[] = [];
  public remoteLogs: RemoteLogEntry[] = [];
  public runtimeStationObjectsCount = 0;

  private nextLogId = 1;
  private nextNotificationId = 1;
  private rateBuckets: Map<number, Map<string, RateBucket>> = new Map();
  private cooldowns: Map<number, Map<string, number>> = new Map();

  constructor() {
    this.resetServer();
  }

  public resetServer(): void {
    this.state = 'WAITING';
    this.roundNumber = 0;
    this.clockSeconds = 0;
    this.phaseRemainingSeconds = 0;
    this.selectedStationId = GAME_CONFIG.DEFAULT_STATION_ID;
    this.selectedMissionId = 'RestorePower';
    this.players.clear();
    this.activeExpeditionUserIds.clear();
    this.notifications = [];
    this.remoteLogs = [];
    this.runtimeStationObjectsCount = 0;
    this.rateBuckets.clear();
    this.cooldowns.clear();
  }

  public isExpeditionPhase(state: RoundState = this.state): boolean {
    return (
      state === 'TRAVEL' ||
      state === 'EXPLORATION' ||
      state === 'EXTRACTION' ||
      state === 'RETURN' ||
      state === 'RESULTS'
    );
  }

  public addPlayer(userId: number, displayName: string, isLocal = false): { ok: boolean; reason: string; player?: PlayerEntity } {
    if (this.players.size >= GAME_CONFIG.MAX_PLAYERS_PER_SERVER && !this.players.has(userId)) {
      return { ok: false, reason: 'ServerFull' };
    }

    const slotIndex = this.players.size;
    const spawnOffset = HUB_SPAWN_OFFSETS[slotIndex % HUB_SPAWN_OFFSETS.length];
    const player: PlayerEntity = {
      userId,
      name: `Player_${userId}`,
      displayName,
      position: { x: spawnOffset.x, z: spawnOffset.z },
      velocity: { x: 0, z: 0 },
      facingAngle: Math.PI,
      isSprinting: false,
      health: GAME_CONFIG.DEFAULT_MAX_HEALTH,
      maxHealth: GAME_CONFIG.DEFAULT_MAX_HEALTH,
      status: 'HUB_WAITING',
      isReady: false,
      votedStationId: GAME_CONFIG.DEFAULT_STATION_ID,
      equipmentSlots: {
        1: 'Flashlight',
        2: null,
      },
      activeSlot: 1,
      missionItems: {},
      isLocal,
    };

    this.players.set(userId, player);

    this.logRemote(
      'Server->Client',
      'InventoryUpdated',
      displayName,
      true,
      'InitialSync',
      `Slot1=${player.equipmentSlots[1] ?? 'Empty'}, Slot2=${player.equipmentSlots[2] ?? 'Empty'}`
    );

    if (this.isExpeditionPhase()) {
      this.pushNotification(
        userId,
        'LateJoinWaiting',
        `An expedition is currently underway (${this.state}). ${displayName} is safely rostered in the Train Hub for the next departure.`,
        'Info'
      );
    } else {
      this.pushNotification(
        userId,
        'WelcomeHub',
        `Welcome aboard NIGHTLINE, ${displayName}. Prepare your 2-slot equipment and confirm route before departure.`,
        'Info'
      );
    }

    if (this.state === 'WAITING' && this.players.size >= GAME_CONFIG.MIN_CREW_TO_START) {
      this.startNewIntermission();
    } else {
      this.broadcastPlayerStatusSummary();
    }

    return { ok: true, reason: 'JoinedHub', player };
  }

  public removePlayer(userId: number): void {
    const player = this.players.get(userId);
    if (!player) return;

    this.players.delete(userId);
    this.activeExpeditionUserIds.delete(userId);
    this.rateBuckets.delete(userId);
    this.cooldowns.delete(userId);

    this.broadcastPlayerStatusSummary();

    if (this.isExpeditionPhase() && this.countActiveExpeditionPlayers() === 0) {
      this.pushNotification(
        'ALL',
        'RoundTerminatedEmpty',
        'All active expedition crew disconnected. Terminating round safely and cleaning runtime instances.',
        'Warning'
      );
      this.cleanupRound();
      this.transitionTo('WAITING', 0);
    } else if (!this.isExpeditionPhase() && this.players.size < GAME_CONFIG.MIN_CREW_TO_START) {
      this.cleanupRound();
      this.transitionTo('WAITING', 0);
    }
  }

  public stepSimulation(dtSeconds: number): void {
    const validDt = Math.max(0, dtSeconds);
    this.clockSeconds += validDt;

    // Move characters inside Train Hub boundaries (-8.8 <= x <= 8.8, -38.5 <= z <= 38.5)
    const moveStep = Math.min(validDt, 0.1);
    for (const player of this.players.values()) {
      if (player.velocity.x !== 0 || player.velocity.z !== 0) {
        const speed = player.isSprinting ? GAME_CONFIG.SPRINT_SPEED : GAME_CONFIG.WALK_SPEED;
        const nextX = player.position.x + player.velocity.x * speed * moveStep;
        const nextZ = player.position.z + player.velocity.z * speed * moveStep;
        player.position.x = Math.max(-8.8, Math.min(8.8, nextX));
        player.position.z = Math.max(-38.5, Math.min(38.5, nextZ));
        player.facingAngle = Math.atan2(player.velocity.x, -player.velocity.z);
      }
    }

    if (this.state === 'WAITING') {
      if (this.players.size >= GAME_CONFIG.MIN_CREW_TO_START) {
        this.startNewIntermission();
      }
      return;
    }

    this.phaseRemainingSeconds = Math.max(0, this.phaseRemainingSeconds - validDt);
    if (this.phaseRemainingSeconds <= 0) {
      this.advanceToNextPhase();
    }
  }

  public advanceToNextPhase(): void {
    switch (this.state) {
      case 'WAITING':
        if (this.players.size >= GAME_CONFIG.MIN_CREW_TO_START) {
          this.startNewIntermission();
        }
        break;
      case 'INTERMISSION':
        this.enterBoardingPhase();
        break;
      case 'BOARDING':
        this.lockCrewAndDepart();
        break;
      case 'TRAVEL':
        this.enterExplorationPhase();
        break;
      case 'EXPLORATION':
        this.enterExtractionPhase();
        break;
      case 'EXTRACTION':
        this.enterReturnPhase();
        break;
      case 'RETURN':
        this.enterResultsPhase();
        break;
      case 'RESULTS':
        this.cleanupRound();
        if (this.players.size >= GAME_CONFIG.MIN_CREW_TO_START) {
          this.startNewIntermission();
        } else {
          this.transitionTo('WAITING', 0);
        }
        break;
    }
  }

  public startNewIntermission(): void {
    this.roundNumber += 1;
    const missionIndex = (this.roundNumber - 1) % ORDERED_MISSION_IDS.length;
    this.selectedMissionId = ORDERED_MISSION_IDS[missionIndex];

    for (const player of this.players.values()) {
      player.status = 'HUB_WAITING';
      player.isReady = false;
    }
    this.activeExpeditionUserIds.clear();

    this.transitionTo('INTERMISSION', GAME_CONFIG.RoundDurations.INTERMISSION);
    this.broadcastPlayerStatusSummary();
    this.pushNotification(
      'ALL',
      'IntermissionStarted',
      `Round #${this.roundNumber} Intermission started (15s). Select equipment and confirm route in the Train Hub.`,
      'Info'
    );
  }

  public enterBoardingPhase(): void {
    for (const player of this.players.values()) {
      player.isReady = true;
      player.status = 'BOARDED';
    }

    this.transitionTo('BOARDING', GAME_CONFIG.RoundDurations.BOARDING);
    this.broadcastPlayerStatusSummary();
    this.broadcastObjectivePreview();
    this.pushNotification(
      'ALL',
      'BoardingStarted',
      'Boarding doors open (45s). Finalize your 2-slot loadout before departure.',
      'Warning'
    );
  }

  public lockCrewAndDepart(): void {
    this.activeExpeditionUserIds.clear();
    const departingPlayers: PlayerEntity[] = [];

    for (const player of this.players.values()) {
      if (player.isReady || player.status === 'BOARDED') {
        player.status = 'IN_EXPEDITION';
        this.activeExpeditionUserIds.add(player.userId);
        departingPlayers.push(player);
      } else {
        player.status = 'HUB_WAITING';
      }
    }

    if (departingPlayers.length === 0) {
      for (const player of this.players.values()) {
        player.isReady = true;
        player.status = 'IN_EXPEDITION';
        this.activeExpeditionUserIds.add(player.userId);
        departingPlayers.push(player);
      }
    }

    if (departingPlayers.length === 0) {
      this.cleanupRound();
      this.transitionTo('WAITING', 0);
      return;
    }

    // Move departing crew to forward boarding spots inside the carriage
    departingPlayers.forEach((player, idx) => {
      const spot = BOARDING_BAY_OFFSETS[idx % BOARDING_BAY_OFFSETS.length];
      player.position = { x: spot.x, z: spot.z };
    });

    this.transitionTo('TRAVEL', GAME_CONFIG.RoundDurations.TRAVEL);
    this.broadcastPlayerStatusSummary();
    this.pushNotification(
      'ALL',
      'TrainDeparting',
      `Train departing Hub (${departingPlayers.length} crew aboard). En route to Station 001: The Forgotten Terminal.`,
      'Info'
    );
  }

  public enterExplorationPhase(): void {
    this.runtimeStationObjectsCount = 12; // Tracked runtime station markers to verify cleanup on round end
    this.transitionTo('EXPLORATION', GAME_CONFIG.RoundDurations.EXPLORATION);
    this.broadcastObjectivePreview();
    this.pushNotification(
      'ALL',
      'ArrivedAtStation',
      'Arrived at Station 001 (180s). Complete primary objective and monitor acoustic levels.',
      'Warning'
    );
  }

  public enterExtractionPhase(): void {
    this.transitionTo('EXTRACTION', GAME_CONFIG.RoundDurations.EXTRACTION);
    this.pushNotification(
      'ALL',
      'ExtractionWarning',
      'Departure horn sounded! Return to the extraction platform within 60 seconds!',
      'Danger'
    );
  }

  public enterReturnPhase(): void {
    for (const userId of this.activeExpeditionUserIds) {
      const player = this.players.get(userId);
      if (player && player.status === 'IN_EXPEDITION') {
        player.status = 'EXTRACTED';
      }
    }

    this.transitionTo('RETURN', GAME_CONFIG.RoundDurations.RETURN);
    this.broadcastPlayerStatusSummary();
    this.pushNotification(
      'ALL',
      'ReturningToHub',
      'Train departing Station 001. Returning extracted crew to the Train Hub.',
      'Success'
    );
  }

  public enterResultsPhase(): void {
    this.transitionTo('RESULTS', GAME_CONFIG.RoundDurations.RESULTS);
    this.broadcastPlayerStatusSummary();
    this.pushNotification(
      'ALL',
      'ExpeditionResults',
      'Expedition complete. Reviewing crew status and preparing Train Hub cleanup.',
      'Info'
    );
  }

  public cleanupRound(): void {
    this.runtimeStationObjectsCount = 0;
    this.activeExpeditionUserIds.clear();

    let index = 0;
    for (const player of this.players.values()) {
      player.status = 'HUB_WAITING';
      player.isReady = false;
      player.missionItems = {};
      player.health = player.maxHealth;
      const spawn = HUB_SPAWN_OFFSETS[index % HUB_SPAWN_OFFSETS.length];
      player.position = { x: spawn.x, z: spawn.z };
      index += 1;
    }

    this.broadcastPlayerStatusSummary();
  }

  public handleEquipmentRequest(
    userId: number,
    slotIndex: unknown,
    requestedItemId: unknown
  ): { ok: boolean; reason: string } {
    const player = this.players.get(userId);
    if (!player) {
      return { ok: false, reason: 'InvalidPlayer' };
    }

    if (!this.checkRateLimit(userId, 'RequestEquipment')) {
      this.logRemote(
        'Client->Server',
        'RequestEquipment',
        player.displayName,
        false,
        'RateLimited',
        `slot=${String(slotIndex)}, item=${String(requestedItemId)}`
      );
      return { ok: false, reason: 'RateLimited' };
    }

    if (!this.checkAndSetCooldown(userId, 'RequestEquipment', GAME_CONFIG.EQUIPMENT_COOLDOWN_SECONDS)) {
      this.logRemote(
        'Client->Server',
        'RequestEquipment',
        player.displayName,
        false,
        'CooldownActive',
        `slot=${String(slotIndex)}, item=${String(requestedItemId)}`
      );
      return { ok: false, reason: 'CooldownActive' };
    }

    const isPrepPhase =
      this.state === 'WAITING' || this.state === 'INTERMISSION' || this.state === 'BOARDING';
    if (!isPrepPhase && player.status !== 'HUB_WAITING') {
      this.logRemote(
        'Client->Server',
        'RequestEquipment',
        player.displayName,
        false,
        'InvalidRoundPhase',
        `Blocked during ${this.state}`
      );
      this.pushNotification(
        userId,
        'EquipmentLocked',
        'Equipment can only be changed inside the Train Hub before departure.',
        'Warning'
      );
      return { ok: false, reason: 'InvalidRoundPhase' };
    }

    if (
      typeof slotIndex !== 'number' ||
      !Number.isInteger(slotIndex) ||
      slotIndex < 1 ||
      slotIndex > GAME_CONFIG.EQUIPMENT_SLOTS
    ) {
      this.logRemote(
        'Client->Server',
        'RequestEquipment',
        player.displayName,
        false,
        'InvalidSlotIndex',
        `slot=${String(slotIndex)}`
      );
      return { ok: false, reason: 'InvalidSlotIndex' };
    }

    const validSlot = slotIndex as 1 | 2;

    if (requestedItemId === null || requestedItemId === '') {
      player.equipmentSlots[validSlot] = null;
      this.logRemote(
        'Client->Server',
        'RequestEquipment',
        player.displayName,
        true,
        'SlotCleared',
        `Slot ${validSlot} cleared`
      );
      return { ok: true, reason: 'SlotCleared' };
    }

    if (
      typeof requestedItemId !== 'string' ||
      (requestedItemId !== 'Flashlight' && requestedItemId !== 'Flare')
    ) {
      this.logRemote(
        'Client->Server',
        'RequestEquipment',
        player.displayName,
        false,
        'InvalidItemId',
        `item=${String(requestedItemId)}`
      );
      return { ok: false, reason: 'InvalidItemId' };
    }

    const otherSlot: 1 | 2 = validSlot === 1 ? 2 : 1;
    if (player.equipmentSlots[otherSlot] === requestedItemId) {
      player.equipmentSlots[otherSlot] = null;
    }

    player.equipmentSlots[validSlot] = requestedItemId;
    player.activeSlot = validSlot;

    this.logRemote(
      'Client->Server',
      'RequestEquipment',
      player.displayName,
      true,
      'Equipped',
      `Slot ${validSlot} -> ${requestedItemId}`
    );
    this.logRemote(
      'Server->Client',
      'InventoryUpdated',
      player.displayName,
      true,
      'Synced',
      `Slot1=${player.equipmentSlots[1] ?? 'Empty'}, Slot2=${player.equipmentSlots[2] ?? 'Empty'}`
    );
    this.pushNotification(
      userId,
      'EquipmentUpdated',
      `Equipped ${requestedItemId === 'Flashlight' ? 'Service Flashlight' : 'Acoustic Signal Flare'} in Slot ${validSlot}.`,
      'Info'
    );

    return { ok: true, reason: 'Equipped' };
  }

  public handleDestinationVote(
    userId: number,
    stationId: unknown
  ): { ok: boolean; reason: string } {
    const player = this.players.get(userId);
    if (!player) {
      return { ok: false, reason: 'InvalidPlayer' };
    }

    if (!this.checkRateLimit(userId, 'RequestDestinationVote')) {
      this.logRemote(
        'Client->Server',
        'RequestDestinationVote',
        player.displayName,
        false,
        'RateLimited',
        `station=${String(stationId)}`
      );
      return { ok: false, reason: 'RateLimited' };
    }

    if (
      this.state !== 'WAITING' &&
      this.state !== 'INTERMISSION' &&
      this.state !== 'BOARDING'
    ) {
      this.logRemote(
        'Client->Server',
        'RequestDestinationVote',
        player.displayName,
        false,
        'VotingClosed',
        `phase=${this.state}`
      );
      return { ok: false, reason: 'VotingClosed' };
    }

    if (typeof stationId !== 'string' || stationId !== 'Station001') {
      this.logRemote(
        'Client->Server',
        'RequestDestinationVote',
        player.displayName,
        false,
        'InvalidStationId',
        `station=${String(stationId)}`
      );
      return { ok: false, reason: 'InvalidStationId' };
    }

    player.votedStationId = 'Station001';
    this.selectedStationId = 'Station001';

    this.logRemote(
      'Client->Server',
      'RequestDestinationVote',
      player.displayName,
      true,
      'VoteRecorded',
      `Station001`
    );
    this.pushNotification(
      userId,
      'DestinationVoteRecorded',
      'Route confirmed for Station 001: The Forgotten Terminal.',
      'Info'
    );

    return { ok: true, reason: 'VoteRecorded' };
  }

  public togglePlayerBoardingReady(userId: number): { ok: boolean; reason: string } {
    const player = this.players.get(userId);
    if (!player) {
      return { ok: false, reason: 'NotRegistered' };
    }

    if (this.state !== 'INTERMISSION' && this.state !== 'BOARDING') {
      this.pushNotification(
        userId,
        'BoardingClosed',
        'Boarding preparation is only active during Intermission and Boarding.',
        'Warning'
      );
      return { ok: false, reason: 'InvalidPhase' };
    }

    player.isReady = !player.isReady;
    player.status = player.isReady ? 'BOARDED' : 'HUB_WAITING';

    this.broadcastPlayerStatusSummary();
    this.pushNotification(
      userId,
      player.isReady ? 'BoardingReadyConfirmed' : 'BoardingSteppedOff',
      player.isReady
        ? 'You are boarded and ready for departure.'
        : 'You stepped out of the boarding roster.',
      player.isReady ? 'Success' : 'Info'
    );

    return { ok: true, reason: player.isReady ? 'Ready' : 'Unready' };
  }

  public handleProximityPromptTriggered(
    userId: number,
    interactableId: string
  ): { ok: boolean; reason: string } {
    const player = this.players.get(userId);
    if (!player || player.health <= 0) {
      return { ok: false, reason: 'InvalidPlayer' };
    }

    const interactable = HUB_INTERACTABLES.find((item) => item.id === interactableId);
    if (!interactable) {
      return { ok: false, reason: 'InvalidPrompt' };
    }

    if (!this.checkAndSetCooldown(userId, 'PromptTriggered', GAME_CONFIG.PROMPT_COOLDOWN_SECONDS)) {
      this.logRemote(
        'Client->Server',
        'PromptTriggered',
        player.displayName,
        false,
        'CooldownActive',
        interactable.name
      );
      return { ok: false, reason: 'CooldownActive' };
    }

    const dx = player.position.x - interactable.position.x;
    const dz = player.position.z - interactable.position.z;
    const distance = Math.hypot(dx, dz);

    if (distance > GAME_CONFIG.MAX_INTERACTION_DISTANCE) {
      this.logRemote(
        'Client->Server',
        'PromptTriggered',
        player.displayName,
        false,
        'OutOfRange',
        `${interactable.name} dist=${distance.toFixed(1)} > ${GAME_CONFIG.MAX_INTERACTION_DISTANCE}`
      );
      this.pushNotification(
        userId,
        'PromptOutOfRange',
        `Move closer to ${interactable.objectText} (${distance.toFixed(1)} studs away; max 14 studs).`,
        'Warning'
      );
      return { ok: false, reason: 'OutOfRange' };
    }

    this.logRemote(
      'Client->Server',
      'PromptTriggered',
      player.displayName,
      true,
      'Accepted',
      `${interactable.name} (${distance.toFixed(1)} studs)`
    );

    if (interactable.tag === 'NightlineEquipmentLocker') {
      return this.handleEquipmentRequest(
        userId,
        interactable.slotIndex ?? 1,
        interactable.itemId ?? 'Flashlight'
      );
    } else if (interactable.tag === 'NightlineDestinationTerminal') {
      return this.handleDestinationVote(userId, interactable.stationId ?? 'Station001');
    } else if (interactable.tag === 'NightlineBoardingZone') {
      return this.togglePlayerBoardingReady(userId);
    }

    return { ok: false, reason: 'UnhandledTag' };
  }

  public countBoardedPlayers(): number {
    let count = 0;
    for (const player of this.players.values()) {
      if (player.status === 'BOARDED' || player.isReady) {
        count += 1;
      }
    }
    return count;
  }

  public countActiveExpeditionPlayers(): number {
    let count = 0;
    for (const userId of this.activeExpeditionUserIds) {
      if (this.players.has(userId)) {
        count += 1;
      }
    }
    return count;
  }

  private checkRateLimit(
    userId: number,
    actionKey: string,
    maxCalls: number = GAME_CONFIG.REMOTE_MAX_CALLS_PER_WINDOW,
    windowSeconds: number = GAME_CONFIG.REMOTE_RATE_LIMIT_WINDOW
  ): boolean {
    let playerMap = this.rateBuckets.get(userId);
    if (!playerMap) {
      playerMap = new Map();
      this.rateBuckets.set(userId, playerMap);
    }

    const bucket = playerMap.get(actionKey);
    if (!bucket || this.clockSeconds - bucket.windowStart >= windowSeconds) {
      playerMap.set(actionKey, {
        windowStart: this.clockSeconds,
        count: 1,
      });
      return true;
    }

    if (bucket.count >= maxCalls) {
      return false;
    }

    bucket.count += 1;
    return true;
  }

  private checkAndSetCooldown(
    userId: number,
    actionKey: string,
    cooldownSeconds: number
  ): boolean {
    let playerCooldowns = this.cooldowns.get(userId);
    if (!playerCooldowns) {
      playerCooldowns = new Map();
      this.cooldowns.set(userId, playerCooldowns);
    }

    const expiresAt = playerCooldowns.get(actionKey);
    if (expiresAt !== undefined && this.clockSeconds < expiresAt) {
      return false;
    }

    playerCooldowns.set(actionKey, this.clockSeconds + cooldownSeconds);
    return true;
  }

  private transitionTo(newState: RoundState, durationSeconds: number): void {
    this.state = newState;
    this.phaseRemainingSeconds = durationSeconds;
    this.logRemote(
      'Server->Clients',
      'RoundStateChanged',
      'RoundService',
      true,
      'StateTransition',
      `Round #${this.roundNumber} -> ${newState} (${durationSeconds}s)`
    );
  }

  private broadcastObjectivePreview(): void {
    const template = MISSION_TEMPLATES[this.selectedMissionId];
    this.logRemote(
      'Server->Clients',
      'ObjectiveUpdated',
      'RoundService',
      true,
      'MissionBrief',
      `${template.title} (0/${template.requiredProgress})`
    );
  }

  private broadcastPlayerStatusSummary(): void {
    this.logRemote(
      'Server->Clients',
      'PlayerStatusUpdated',
      'RoundService',
      true,
      'RosterSync',
      `${this.players.size} players (${this.countBoardedPlayers()} boarded)`
    );
  }

  private pushNotification(
    targetUserId: number | 'ALL',
    messageKey: string,
    messageText: string,
    severity: NotificationSeverity
  ): void {
    this.notifications.unshift({
      id: this.nextNotificationId++,
      targetUserId,
      messageKey,
      messageText,
      severity,
      timestamp: this.clockSeconds,
    });
    if (this.notifications.length > 25) {
      this.notifications.pop();
    }
  }

  private logRemote(
    direction: RemoteLogEntry['direction'],
    remoteName: RemoteLogEntry['remoteName'],
    actorName: string,
    accepted: boolean,
    reason: string,
    payloadSummary: string
  ): void {
    this.remoteLogs.unshift({
      id: this.nextLogId++,
      timestamp: this.clockSeconds,
      direction,
      remoteName,
      actorName,
      accepted,
      reason,
      payloadSummary,
    });
    if (this.remoteLogs.length > 40) {
      this.remoteLogs.pop();
    }
  }
}
