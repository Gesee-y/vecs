# Vecs - Manual
A guided tour of `vecs`. The API reference is available [here](https://rowdaboat.github.io/vecs/).


## How it works
Entities are grouped into archetypes by their exact set of component types, keeping one contiguous column per component type. This way iterating touches only the columns a query asks for, in order keeping cache coherence.

Archetypes are created on demand, and adding or removing a component moves the entity to another archetype. For this reason structural changes (add or remove an entity or component) are `Deferred` by default and applied together on `consolidate()`.

Queries cache the archetypes they match, so matching runs once per archetype instead of once per entity, and each iteration only examines the archetypes created since the last one. Keep a query alive rather than declaring it per call. `cleanupEmptyArchetypes()` is the only operation that invalidates those caches.


## Basic Usage
```nim
# Import the library
import vecs
```
```nim
# Declare some components, components are regular value objects.
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
```nim
# Create a world
var world = World()
```
```nim
# Add an entity with components, `Immediate` applies the addition right away,
# the default `Deferred` mode would hold it back until `consolidate()`.
let entityId = world.add((
  Character(name: "Marcus", class: "Warrior"),
  Health(current: 120, max: 120)
), Immediate)
```
```nim
# Get a component from an entity to read its values
let health = world.read(entityId, Health)
echo health.current, " / ", health.max
```
```nim
# Get a component from an entity with write access
for health in world.write(entityId, Health):
  health.current += 75
```
```nim
# Read multiple components from an entity
let (character, health) = world.read(entityId, (Character, Health))
echo character.name, "'s health is: ", health.current
```
```nim
# Write to multiple components from an entity
for (character, health) in world.components(entityId, (Write[Character], Write[Health])):
  character.name = "Happy " & character.name
  health.current += 75
```
```nim
# Query for components
var characterWithWeaponsQuery = Query[(Character, Write[Weapon])]()
for (character, weapon) in world.query(characterWithWeaponsQuery):
  weapon.attack += 10
  echo character.name, "'s weapon ", weapon.name, " reforged!"
```
```nim
# Removing an entity
world.remove entityId
```
```nim
# Adding a component
world.add(entityId, Shield(name: "Steel Shield", defense: 15))
```
```nim
# Removing a component
world.remove(entityId, Shield)
```
```nim
# The `Meta` component is automatically added, and holds the `Id` of the entity.
# This is useful for embedding references to other entities into components.
let entityId = world.add((Character(name: "Leon", class: "Paladin"),), Immediate)

let meta = world.read(entityId, Meta)
assert entityId == meta.id
```


## Advanced querying
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


## Features to cover
- [ ] Tag components, components with no fields, are supported and queriable.
- [ ] Typed `Id[T]` references to other entities, embeddable in components.
- [ ] Three modes for add and remove operations: immediate, deferred, and after a query, to safely mutate the entities a query is iterating.
- [ ] Components queued for deferred removal can be queried, so systems can react before they are gone.
- [ ] An explicit filter chooses which components are serialized, and the `{.transient.}` pragma which fields are skipped.
- [ ] Deserialization skips unknown component types and unknown fields, so older saves keep loading.
- [ ] Console output of a world as a text table, for debugging.
