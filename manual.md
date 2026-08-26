# Vecs - Manual
A guided tour of `vecs`. The API reference is available [here](https://rowdaboat.github.io/vecs/).


## How it works
Entities are grouped into archetypes by their exact set of component types, keeping one contiguous column per component type. This way iterating touches only the columns a query asks for, in order keeping cache coherence.

Archetypes are created on demand, and adding or removing a component moves the entity to another archetype. For this reason structural changes (add or remove an entity or component) are `Deferred` by default and applied together on `consolidate()`.

Queries cache the archetypes they match, so matching runs once per archetype instead of once per entity, and each iteration only examines the archetypes created since the last one. Keep a query alive rather than declaring it per call. `cleanupEmptyArchetypes()` is the only operation that invalidates those caches.


## Setup
Import the library and create a world to hold the entities.
```nim
import vecs
```
```nim
var world = World()
```


## Components
Components are regular value objects — just data, no behaviour.
```nim
type Character = object
  name*: string
  class*: string

type Health = object
  current*: int
  max*: int

type Weapon = object
  name*: string
  attack*: int

type Shield = object
  name*: string
  defense*: int
```


## Adding entities
An entity is created from a tuple of components. `Immediate` applies the addition right away; the default `Deferred` mode holds it back until `consolidate()`.
```nim
let entityId = world.add((
  Character(name: "Marcus", class: "Warrior"),
  Health(current: 120, max: 120)
), Immediate)
```


## Reading and writing components
`read` returns a copy of a component; `write` yields a mutable reference through a single-pass iterator. Both have single- and multi-component forms.
```nim
# Read a single component
let health = world.read(entityId, Health)
echo health.current, " / ", health.max
```
```nim
# Write a single component
for health in world.write(entityId, Health):
  health.current += 75
```
```nim
# Read multiple components at once
let (character, health) = world.read(entityId, (Character, Health))
echo character.name, "'s health is: ", health.current
```
```nim
# Write multiple components at once
for (character, health) in world.components(entityId, (Write[Character], Write[Health])):
  character.name = "Happy " & character.name
  health.current += 75
```


## Querying entities
A query walks every entity that has the requested components. Keep a query alive across frames rather than declaring it per call.
```nim
var characterWithWeaponsQuery = Query[(Character, Write[Weapon])]()
for (character, weapon) in world.query(characterWithWeaponsQuery):
  weapon.attack += 10
  echo character.name, "'s weapon ", weapon.name, " reforged!"
```


## Adding and removing on the fly
Whole entities and individual components can be added or removed at any time. These are structural changes, so they honour the same operation modes as `add`.
```nim
# Remove an entity
world.remove entityId
```
```nim
# Add a component
world.add(entityId, Shield(name: "Steel Shield", defense: 15))
```
```nim
# Remove a component
world.remove(entityId, Shield)
```


## The Meta component
`Meta` is added to every entity automatically and holds its `Id`. This is useful for embedding references to other entities into components.
```nim
let entityId = world.add((Character(name: "Leon", class: "Paladin"),), Immediate)

let meta = world.read(entityId, Meta)
assert entityId == meta.id
```


## Tag components
Components with no fields work as tags — markers that carry no data but still narrow a query.
```nim
# A tag is just an empty object
type Frozen = object
```
```nim
# Add and remove it like any other component
world.add(entityId, Frozen())
world.remove(entityId, Frozen)
```
```nim
# Query for it — the tag has no value to read, so discard it with `_`
var frozenCharacters = Query[(Character, Frozen)]()
for (character, _) in world.query(frozenCharacters):
  echo character.name, " is frozen"
```


## Entity references
Store a typed `Id[T]` inside a component to reference another entity. The type parameter records which component the reference points at, so following it stays type-checked. A default `Id[T]` points at nothing.
```nim
# Embed references in components — a single one or a collection of them
type Party = object
  leader: Id[Character]
  members: seq[Id[Character]]
```
```nim
# Turn an entity's id into a typed reference with `of`
let marcusId = world.add((Character(name: "Marcus", class: "Warrior"),), Immediate)
let leaderRef = marcusId of Character
```
```nim
# Follow a reference to read or write the component it points at
echo world.read(leaderRef).name

for character in world.write(leaderRef):
  character.name = "Sir " & character.name
```
```nim
# `has` checks the referenced entity still carries the component
if world.has(leaderRef):
  echo "leader is still a character"
```
```nim
# Re-type a reference to reach a different component on the same entity
let healthRef = leaderRef of Health
```


## Advanced querying
Query modifiers change how components are matched and accessed: `Write` for mutable access, `Opt` for components that may be absent, and `Not` to exclude entities that have a component.
```nim
# Query components for writting
var charactersWithHealth = Query[(Character, Write[Health])]()
for (character, health) in world.query(charactersWithHealth):
  health.current += 10
```
```nim
# Query for optional components
var charactersWithWeapons = Query[(Character, Opt[Weapon])]()
for (character, weapon) in world.query(charactersWithWeapons):
  weapon.isSomething:
    echo character.name, " has a weapon, ", value.name
  weapon.isNothing:
    echo character.name, " has no weapon"
```
```nim
# Exclude components from a query
var disarmedCharacters = Query[(Character, Not[Weapon])]()
for (character,) in world.query(disarmedCharacters):
  echo character.name, " has no weapon"
```


## Operation modes
Every `add` and `remove` takes an operation mode that decides when the structural change is applied.
```nim
# `Immediate` applies the change right away
world.add(entityId, Shield(name: "Steel Shield", defense: 15), Immediate)
```
```nim
# `Deferred` is the default — the change is queued and applied on the next consolidate()
world.add(entityId, Shield(name: "Steel Shield", defense: 15))
world.consolidate()
```
```nim
# `after(query)` defers the change until that query finishes iterating,
# so a system can safely restructure the entities it is walking over
var disarmed: Query[(Meta, Character, Not[Weapon])]
for (meta, character) in world.query(disarmed):
  world.add(meta.id, Weapon(name: "Sword", attack: 10), after(disarmed))
  # During iteration the weapon is not there yet
  assert not world.has(meta.id, Weapon)

# Once the loop ends the queued changes are applied
assert world.has(marcusId, Weapon)
```
`after(query)` works for adding and removing components, and for adding and removing whole entities.


## Reacting to removals
A component queued for deferred removal is still present until the next `consolidate()`, so a system can query for it and react before it is gone. `queryForRemoval` yields those components with write access.
```nim
# Queue a deferred removal
world.remove(entityId, Health)
```
```nim
# See the components about to be removed, and act on them one last time
for (meta, health) in world.queryForRemoval(Health):
  echo "entity ", meta.id, " is losing ", health.current, " health"
```
```nim
# After consolidate() the removal is applied and the component no longer appears
world.consolidate()
for (meta, health) in world.queryForRemoval(Health):
  echo "won't run"
```
This also catches components on an entity queued for whole-entity removal, since removing the entity removes each of its components. Immediate removals skip the queue, so they never show up here.


## Snapshots
Snapshots are useful for implementing features like Undo/Redo, Copy/Paste/Duplicate
```nim
# Take a snapshot of an entity's components at a point in time
let snap = world.snapshot(entityId)
```
```nim
# Restore the entity to its snapshot state
# Modified components are reset, removed components are re-added,
# components added after the snapshot are removed
world.restore(snap)
```
```nim
# Restore a snapshot onto a different entity — useful for copy/duplicate
world.restore(snap, targetEntityId)
```


## Serialization
Serialization takes a tuple of the component types to write, so derived or engine-owned components stay out of the output
```nim
# Serialize a world to CBOR, or to JSON
let binary = world.serializeToBinary((Character, Health, Weapon))
let text = world.serializeToText((Character, Health, Weapon))
```
```nim
# Deserialize into a fresh world
var restored = deserializeFromBinary(binary, (Character, Health, Weapon))
```
```nim
# Mark a field `{.transient.}` to keep it out of the output — it is neither
# written nor read back, and must be re-derivable at runtime.
type Sprite = object
  path: string
  texture {.transient.}: int   # runtime handle, restored as its default value
```
`Id[T]` and `EntityId` fields serialize as the entity id they refer to, and nested objects, `seq`s and fixed size arrays are walked through.


## Adding worlds
`add` copies entities between worlds, remapping the ids inside their components
```nim
# Merge a whole world into a populated one, e.g. right after deserializing it
var loaded = deserializeFromBinary(binary, (Character, Health, Weapon))
let mapping = world.add(loaded, (Character, Health, Weapon))
```
```nim
# The returned mapping is a `Table`, going from the source's ids to the newly created ones
import std/tables

let addedId = mapping[sourceId]
```
```nim
# Copy only some entities, e.g. to lift a fragment out into a world of its own
var fragment = World()
discard fragment.add(world, @[entityId, childId], (Character, Health, Weapon))
```
Ids pointing at copied entities are remapped to their counterparts, ids pointing outside the copied set are invalidated. The source world is left unchanged.


## Events
Events are value objects passed between systems through a per-type queue — emit them from anywhere in the game loop and collect them wherever you handle them.
```nim
# Declare event types, events are regular value objects.
type DamageEvent = object
  amount: int

type HealEvent = object
  amount: int
```
```nim
# Emit an event from anywhere in the game loop
world.emit(DamageEvent(amount: 25))
world.emit(HealEvent(amount: 10))
```
```nim
# Collect and process events, the events can be collected multiple times
for event in world.collect(DamageEvent):
  echo "Damage dealt: ", event.amount
```
```nim
# Each event type is isolated — collecting DamageEvent does not affect HealEvent
for event in world.collect(HealEvent):
  echo "Health restored: ", event.amount
```
```nim
# Calling consolidate() drains all event queues
world.consolidate()

for event in world.collect(DamageEvent):
  echo "Won't be called"
```


## Debugging
`show` renders a world as a text table, one block per archetype, listing the chosen components for every entity. Handy for inspecting state at a glance.
```nim
# Pick which components to print; long values are truncated at maxWidth (default 20)
echo world.show((Character, Health, Weapon))
```
```
.-----------.
| Archetype |
.---------------------------------------------.
| Character      | Health       | Weapon      |
|---------------------------------------------|
| name: Marcus   | current: 120 | name: Sword |
| class: Warrior | max: 120     | attack: 10  |
'---------------------------------------------'

.-----------.
| Archetype |
.---------------------------.
| Character   | Health      |
|---------------------------|
| name: Elena | current: 80 |
| class: Mage | max: 80     |
'---------------------------'
```
