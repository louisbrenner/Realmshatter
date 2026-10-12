# C# → GDScript porting spec (Realmshatter)

Source: `../Scripts/**/*.cs` (C#, Godot 4.5). Target: `GDPort/Scripts/**/*.gd` — a standalone Godot 4.5 project
in `GDPort/` (res:// = `GDPort/`). Many agents port files in parallel and NEVER see each other's output, so every
cross-file name must follow these rules mechanically. Read the C# of any dependency to know its API — its GDScript
name is derived by the rules below.

## Files & classes
- Same relative path and file name, `.gd` extension: `Scripts/Core/Piece.cs` → `GDPort/Scripts/Core/Piece.gd`.
- Each file starts with `class_name <SameClassName>` then `extends <SameBaseType>`. Plain C# classes (no Godot
  base) → `extends RefCounted`. Static classes → `extends RefCounted` with only `static func` / `const` / `static var`.
- Keep the namespace out (GDScript has none). Keep `///` doc comments as `##` comments (short).
- Use static typing everywhere practical (`var x: int`, `-> void`, `Array[Piece]`, `Dictionary[int, Piece]`).

## Naming (the core contract)
`snake(Name)` = apply in order: `re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1_\2')`, then `re.sub(r'([a-z0-9])([A-Z])', r'\1_\2')`, then lowercase.
Examples: `ApCost`→`ap_cost`, `MaxHp`→`max_hp`, `GetPieceAt`→`get_piece_at`, `HPBar`→`hp_bar`, `Player0Hp`→`player0_hp`.
- Public/internal/protected properties, fields, methods → `snake(Name)`.
- Private fields `_camelCase` → `_` + snake (`_tickerTween` → `_ticker_tween`). Private methods → `_` + snake(Name)
  (if that collides with a Godot virtual like `_process`, `_draw`, `_input`, append `_impl`).
- Constants (`const`, `static readonly` of constant values) → `UPPER_SNAKE` (`snake(Name).upper()`), public ones too.
- Godot virtuals: `_Ready`→`_ready`, `_Process`→`_process`, `_UnhandledInput`→`_unhandled_input`, etc.
- Parameters/locals → snake_case.
- If a public name would collide with an inherited Godot member or a GDScript keyword, append `_` (e.g. `class_`)
  and LIST IT in your final report.
- C# overloads (rare, file-local): merge with default args or rename privately.

## Properties
- Auto-properties → plain `var`. Computed get-only properties (`=> expr` / `get {}`) → `var x: T:` with `get:` so
  callers still use property syntax (`piece.effective_attack`, `card.targets_tile`). Properties with private
  setters → plain `var` too.

## Enums
- Each C# enum file → `class_name <EnumName>` `extends RefCounted` with an UNNAMED enum whose members are
  `UPPER_SNAKE` of the C# names and the same numeric values, e.g.
  ```gdscript
  class_name CardType
  extends RefCounted
  enum { UNIT = 0, SPELL = 1 }
  const NAMES := { UNIT: "Unit", SPELL: "Spell" }
  ## Equivalent of C# enum ToString() (for [Flags] enums: ", "-joined names, "None" for 0).
  static func name_of(value: int) -> String: ...
  ```
  Usage everywhere: `CardType.UNIT`, values typed as `int`. C# `x.ToString()` / interpolating an enum →
  `CardType.name_of(x)`. Enums nested in a class → inner unnamed enum in that class + same pattern if needed.
- `[Flags]` enums (Keyword) → same, bit ops on ints.

## Value types
- `GridPos` is REPLACED by `Vector2i` everywhere (types, dict keys, arrays). `GridPos.gd` becomes a static helper:
  `GridPos.ORTHOGONAL_DIRECTIONS: Array[Vector2i]`, `GridPos.manhattan_distance(a, b) -> int`,
  `GridPos.neighbors(p) -> Array[Vector2i]`. Mappings: `new GridPos(x,y)`→`Vector2i(x,y)`, `.X/.Y`→`.x/.y`,
  `a.ManhattanDistance(b)`→`GridPos.manhattan_distance(a, b)`, `p.Neighbors()`→`GridPos.neighbors(p)`,
  `ToVector2I()`/`FromVector2I()`→identity. `GridPos?` (nullable) → `Variant` holding Vector2i or `null`.
  `ToString()` → `str(v)` (prints `(x, y)` like C#).
- Other structs (`PieceStats`, `SpellEffect`, private structs) → RefCounted classes with a
  `func copy() -> <Class>` method. Where C# relies on copy semantics (assigning then mutating), call `.copy()`.
  Constructors → `_init(...)` with default args so `PieceStats.new()` works; static factories keep their names
  (`PieceStats.from_card(card)`).
- Godot structs: `Vector2/3`, `Color`, etc. map directly (`.X`→`.x`, `Vector3.Zero`→`Vector3.ZERO`,
  `Colors.White`→`Color.WHITE`, `Mathf.Lerp`→`lerp`, `Mathf.Clamp`→`clamp/clampf/clampi`, `Mathf.Pi`→`PI`).
- C# `int / int` stays integer division (fine in GDScript). Watch `float` vs `int` mixing: cast explicitly.

## Collections
- `List<T>` / `T[]` / `IReadOnlyList<T>` / `IEnumerable<T>` → `Array[T]` (untyped `Array` if T is Variant-ish).
- `Dictionary<K,V>` → `Dictionary[K, V]` (typed dicts are OK in 4.5) — or plain `Dictionary`.
- `HashSet<T>` → `Dictionary` used as set (`set[x] = true`, `set.has(x)`).
- `TryGetValue(k, out v)` → `d.get(k, default)` / `d.has(k)`.
- `out` parameters (all file-local) → return an Array/Dictionary or small inner class.
- `yield return` → build and return an Array.
- Sorting: `list.Sort(cmp)` → `arr.sort_custom(func(a, b): return cmp(a, b) < 0)`.
- No LINQ is used.

## Randomness
- `System.Random` → `RandomNumberGenerator` (type and object). `new Random(seed)` → `rng = RandomNumberGenerator.new(); rng.seed = seed`.
  `r.Next(n)`→`r.randi_range(0, n - 1)`, `r.Next(a, b)`→`r.randi_range(a, b - 1)`, `r.NextDouble()`→`r.randf()`.
  `GameState.random` is a `RandomNumberGenerator`.

## Events, signals, callables
- `[Signal] delegate void FooEventHandler(args)` → `signal foo(args)`; `EmitSignal(SignalName.Foo, a)` → `foo.emit(a)`.
- C# `event Action<...> Foo` → `signal foo(...)`; `Foo?.Invoke(a)` → `foo.emit(a)`; `x.Foo += H` → `x.foo.connect(_h)`; `-=` → `disconnect`.
- Godot signals: `button.Pressed += OnPressed` → `button.pressed.connect(_on_pressed)`.
- `Action`/`Func<>` fields/params → `Callable`; invoke with `.call(...)`. Lambdas → `func(...): ...`.
  WARNING: GDScript lambdas capture locals BY VALUE at creation. If C# mutates a captured local inside a lambda,
  use a member var or a 1-element Array/Dictionary box.
- `Callable.From(X).CallDeferred()` → `X.call_deferred()` / `_x.call_deferred()`.
- `TweenMethod(Callable.From<float>(f), a, b, t)` → `tween_method(f, a, b, t)`.

## Async
- `async Task` / `async Task<T>` / `async void` methods → normal funcs that use `await` (coroutines). Keep the
  same snake name, keeping any `Async` suffix (i.e. `RunGameAsync` → `_run_game_async`, `PlayReveal` → `play_reveal`).
- `await SomethingAsync()` → `await something_async()`. Fire-and-forget (`_ = X()` or unawaited call) → call without await.
- `await ToSignal(obj, Tween.SignalName.Finished)` → `await obj.finished`.
  `await ToSignal(GetTree().CreateTimer(s), SceneTreeTimer.SignalName.Timeout)` → `await get_tree().create_timer(s).timeout`.
- Callers of a coroutine that returns a value MUST `await` it.

## Godot API
- PascalCase API → snake_case API (`GetNode<T>("x")` → `get_node("x") as T` or `$x`, `AddChild` → `add_child`,
  `QueueFree` → `queue_free`, `GD.Print` → `print`, `GD.PushWarning` → `push_warning`, `Mathf.*` → globals).
- `[Export]` → `@export`; `[ExportGroup("X")]` → `@export_group("X")`; `PropertyHint.MultilineText` → `@export_multiline`.
  Exported enum ints → `@export_enum("Unit", "Spell") var card_type: int = CardType.UNIT`; flags → `@export_flags(...)`.
  Exported arrays of resources → `@export var cards: Array[CardData] = []`.
- `[Tool]` → `@tool`. `[GlobalClass]` → nothing extra (class_name suffices).
- `new Foo()` for Godot objects → `Foo.new()`. `is T x` pattern → `if obj is T: var x := obj as T`.
- String interpolation `$"{a} {b:0.0}"` → `"%s %.1f" % [a, b]` or `str(...)`. `string.Join(", ", xs)` → `", ".join(xs)` (strings only).
- `Math.Max/Min/Abs` → `maxi/mini/absi` for ints, `maxf/minf/absf` for floats.
- `Time`, `Engine`, `RenderingServer`, `ResourceLoader` etc. → same singletons with snake_case methods.
- Shaders under `res://Assets/Shaders/` are unchanged. Scene/resource paths stay identical (`res://Scenes/...`, `res://Resources/...`).
- Exported node references keep working via snake_case export names (the .tscn files are converted mechanically:
  every PascalCase property key on a scripted node/resource is renamed with `snake()`).

## Quality bar
- Port behavior faithfully, 1:1 logic. No new features, no redesign. Keep structure/order of members.
- Must parse with Godot 4.5 GDScript (no `?.`, no ternary `?:` → use `a if c else b`, no `++`, no `switch` → `match`).
- `null` checks: `x?.Foo()` → `if x != null: x.foo()`; `a ?? b` → `a if a != null else b`.
- `is_instance_valid(x)` where C# used `IsInstanceValid`.
- Do not create .tscn/.tres/.uid files. Do not touch anything outside your assigned output files.
- At the end report: files written, any deviations from the naming rules (public names you had to change), and anything
  other files' porters must know.

## Addendum (re-port of 2026-10-12: overworld, halls, buildings, legends, traps)
These rules close gaps that cross file boundaries. Apply them mechanically.
- **`out` parameters in public/internal methods** (e.g. `BattleSession.IsUnlocked(npc, out int beaten, out int needed)`,
  `PlayerProfile.TryAddToDeck(card, out string error)`): the GDScript func takes only the non-out params and returns a
  `Dictionary` with key `"result"` = the C# return value (omitted for `void`) plus one key per out param, named
  `snake(paramName)`: `is_unlocked(npc) -> Dictionary` returns `{"result": bool, "beaten": int, "needed": int}`.
  Callers: `var r := BattleSession.is_unlocked(npc)`, `if r.result: ...`, `r.beaten`. `TryGetValue` stays `has/get`.
- **Instance C# events** (`public event Action<int> TurnStarted`) → `signal turn_started(value)`; `+=` → `.connect`,
  invoke → `.emit`.
- **Static events on static classes** (`public static event Action Changed` in `PlayerProfile`) → GDScript has no
  static signals: `static var changed_listeners: Array[Callable] = []`. `PlayerProfile.Changed += F` →
  `PlayerProfile.changed_listeners.append(f)`, `-=` → `.erase(f)`, `Changed?.Invoke()` →
  `for cb in changed_listeners: if cb.is_valid(): cb.call()`.
- **Tuples crossing files** (return types, params, public fields, e.g. `KeywordVisuals.IconsFor` returns
  `List<(FxIconShape Shape, Color Fg, Color Bg)>`, `DialogueBox.Open(..., IReadOnlyList<(string Label, Action Action)>)`):
  each tuple → `Dictionary` with keys `snake(elementName)` (`{"shape": .., "fg": .., "bg": ..}`, `{"label": .., "action": Callable}`);
  unnamed elements → `"item1"`, `"item2"`, ... File-local tuples: same rule recommended.
- **`record struct` / `record class` / small private structs**: RefCounted inner class (or file) with the same fields;
  public nested ones (e.g. `TownMap.House`, `InfoSheet.Row`) become inner classes `class House:` with `_init(...)` taking the
  positional record parameters in order, so callers write `TownMap.House.new(body, clan)`. Where C# relies on value
  equality (`==`, dict keys, `Contains`), compare fields explicitly.
- **Static classes with state** (`PlayerProfile`, `BattleSession`, caches): `static var`; static properties with logic
  → `static func` getters are NOT property syntax in GDScript, so a C# static property `X` with a getter body becomes
  `static func get_x()`; C# static auto-properties (`{ get; set; }`) become `static var x`. Callers follow that rule.
- **Nested enums / constants** referenced from other files keep `Outer.INNER_NAME`.
- **`nameof`, `GetType().Name`** → string literals.
- `System.Text.Json` → `JSON.stringify(dict, "\t")` / `JSON.parse_string(text)` (numbers come back as float → cast to int).
- `Godot.Collections.Array<string>` (e.g. `NpcData.RequiresDefeated`) → `Array[String]`; `.Contains(x)` → `.has(x)`.
- `string.Contains(s)` → `s in text`; `string.IsNullOrEmpty(s)` → `s.is_empty()` (strings are never null in the port;
  use `""` instead of null for strings).
- `Callable.From(() => ...)` → lambda; `Tween.TweenCallback(Callable.From(F))` → `tween_callback(f)`.
- `(int)someEnumValue` and `(SomeEnum)intValue` → just the int.
- When a C# property/method name collides with an inherited Godot member after snaking (e.g. a Node2D field
  `Position`, `Scale`, `Name`, `Visible`, `Owner`, `Theme`, a Control `Size`), and the C# code means the inherited member
  anyway (no `new` keyword), just use the inherited one. If it is a genuinely new member that would shadow, append `_`
  and report it.
- **Static funcs must not reuse built-in method names**: a static `get_name(x)` on a script class is shadowed by
  `Resource.get_name()` when called as `ClanInfo.get_name(x)`. The `*Info.GetName(x)` helpers are therefore ported as
  `display_name(x)` (`ClanInfo.display_name`, `KeywordInfo.display_name`, `TriggerInfo.display_name` (deathrattle) /
  `get_first_hit_name`, ...).
