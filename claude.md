# Project

- Engine: Godot 4.5 stable (.NET/Mono), language: C# (.NET 8)
- IDE: Visual Studio 2022 (17.14); the solution (`.sln`) is in the project root
- Project name: ProjectClaude
- Genre / goal: Card game, collector, Hearthstone-like
- Root namespace: `ProjectClaude`

# Workflow

- Write code in **larger, coherent blocks** (complete classes or features), not fragments.
- For larger tasks, briefly state the plan first (affected files, scenes, nodes), then implement it.
- Only change what belongs to the task. No unrequested refactoring of existing files.
- After every code change, run `dotnet build` and fix all errors and warnings yourself.
- At the end, briefly explain what was changed and what I still need to do in the editor (e.g. assign a script, set export values).

# Build & Commands

```bash
dotnet build                                            # Compile C#
godot --headless --path . --build-solutions --quit      # Build via Godot
godot --path . res://Szenen/Main.tscn                   # Run a scene
```

- Godot executable: `D:\Game Dev\Godot\Engine\Godot_v4.5-stable_mono_win64\Godot_v4.5-stable_mono_win64.exe`
- After changing C# files, the solution must be rebuilt so that new classes and `[Export]` fields appear in the editor.

# C# Conventions (Godot 4)

- Every node class is `partial` and inherits from a Godot type. **Class name = file name** (`Player.cs` → `class Player`); otherwise the script cannot be attached to a node.
- Namespace `ProjectClaude`, one type per file.
- Godot lifecycle: `public override void _Ready()`, `_Process(double delta)`, `_PhysicsProcess(double delta)`.
- Expose editor values with `[Export]`. Define custom resources as `[GlobalClass] public partial class X : Resource`.
- Declare signals as delegates with `[Signal]` and the suffix `EventHandler`:
  `[Signal] public delegate void HealthChangedEventHandler(int newValue);`
  Emit with `EmitSignal(SignalName.HealthChanged, value)`, connect with `+=`.
- Get nodes via `GetNode<T>("Path")` or `[Export]` references, never via string lookups at runtime in `_Process`.
- Use the Godot types `Callable`, `StringName` and `NodePath` instead of plain strings.
- Do not use `System.Threading.Thread` for game logic. To wait, use `await ToSignal(...)`.
- Naming: PascalCase for classes, methods and properties; `_camelCase` for private fields; camelCase for parameters and local variables.
- Short XML comments (`///`) on public methods; otherwise comment sparingly.

# Project Structure

```
res://
├── Scripts/     # C# scripts (grouped by feature)
├── Scenes/      # .tscn scenes
├── Resources/   # .tres resources
├── Assets/      # Graphics, audio, fonts
└── Addons/      # Plugins (do not modify)
```

# Godot Editor (MCP)

- The MCP server is only active while the Godot editor is open with this project.
- Use MCP for editor actions: reading the scene tree, creating and configuring nodes, running the game, reading error output.
- Write C# code directly in the `.cs` files, not via MCP tools.
- After attaching scripts to nodes, check that the build succeeded.
- If an MCP tool does not work with C#, tell me and fall back to editing the files directly.

# Do Not Touch Without Asking

- `project.godot` (input map, autoloads, project settings)
- The `.godot/` folder, `*.import` files, `.csproj`/`.sln` files
- The `addons/` folder
- Existing scenes (`.tscn`): do not rewrite them completely. Targeted changes are fine.

# Git

- I commit myself. Do not modify the Git history, and do not run `git` commands that discard changes (`reset --hard`, `checkout .`, `clean`).
