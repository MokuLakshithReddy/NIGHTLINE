# NIGHTLINE: LAST TRAIN — Known Issues & Environment Limitations

## 1. Environment & Tooling Limitations

1. **No Direct Desktop Roblox Studio Instance in Cloud Container:**
   - **Cause:** This development workspace runs inside a containerized Linux environment (`x86_64 GNU/Linux`) without a desktop Roblox Studio installation, Studio MCP bridge, or pre-installed Rust `rojo`/`selene`/`stylua` binaries.
   - **Mitigation Implemented:**
     - The project is structured as a standard, importable **Rojo project** (`default.project.json`, `rokit.toml`, `stylua.toml`, `selene.toml`, `.luaurc`) with strict Luau modules under `/roblox`.
     - An automated **Luau Static & Rojo Structure Verifier** (`src/engine/luauVerifier.ts`) validates all `.lua` files and Rojo path mappings during `npx --yes tsx --test src/engine/nightline.test.ts`.
     - An interactive **Train Hub & Round State Machine Workbench** (`src/`) mirrors the exact server services and client controllers so Milestone 0 and Milestone 1 gameplay, multiplayer rostering, late-join isolation, and security checks can be interactively verified in the browser.

## 2. Current Scope Boundaries (By Design for Milestone 1)

1. **Station 001 Geometry & Objectives Not Yet Active During `EXPLORATION`:**
   - During Milestone 1, the `TRAVEL`, `EXPLORATION`, `EXTRACTION`, and `RETURN` phases run on authoritative server timers and transition cleanly back to the Train Hub, but Station 001 greybox cloning (`StationService`) and interactive objectives (`ObjectiveService`) are scheduled for **Milestone 2**.
2. **The Hollow AI Not Yet Spawned:**
   - Scheduled for **Milestone 3** per the build specification.
3. **DataStore Persistence & Scrap Economy Not Yet Enabled:**
   - Scheduled for **Milestone 4** per the build specification.
