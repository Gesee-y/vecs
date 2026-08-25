# vecs

Vexel's ECS library for Nim👑, heavily inspired by [Beef🥩](https://github.com/beef331)'s [yeacs](https://github.com/beef331/nimtrest/blob/master/yeacs.nim), a lot of his ideas were used, and some of his macros were directly copied.

`vecs`'s API aims to be mostly the same, with minor differences.

The main design differences between `vecs` and `yeacs` are in the implementation:
- `vecs` avoids manually copying memory, erasure is implemented by using abstract types, then casting to concrete types when needed. This simplifies book-keeping a bit, and goes easier on references, not needing to track move semantics.
- `vecs` approaches ECS with a collection for each component in the archetype, while `yeacs` instead uses a single collection of tuples of components for each archetype.


## Installation
Add `vecs` to your `.nimble` file by its repository url:
```nim
requires "https://github.com/RowDaBoat/vecs"
```


## At a glance
```nim
import vecs

type Character = object
  name*: string
  class*: string

type Health = object
  current*: int
  max*: int

type Poisoned = object

var world = World()

world.add((
  Character(name: "Marcus", class: "Warrior"),
  Health(current: 120, max: 120),
  Poisoned()
), Immediate)

world.add((
  Character(name: "Elena", class: "Mage"),
  Health(current: 80, max: 80)
), Immediate)

var poisonedCharacters = Query[(Character, Write[Health], Poisoned)]()

for (character, health, _) in world.query(poisonedCharacters):
  health.current -= 10
  echo character.name, " is poisoned: ", health.current, "/", health.max
```


## Features
- Components are plain value `object`s, no base type, no registration, no macros.
- Archetype storage with a contiguous column per component type, for cache friendly iteration.
- Cached queries, with `Write[T]`, `Opt[T]` and `Not[T]` to declare access and presence.
- Add and remove immediately, deferred until `consolidate()`, or after a query finishes iterating.
- Typed `Id[T]` references to other entities, safe to embed in components.
- Snapshots of an entity's whole state, for undo/redo and duplication.
- JSON and CBOR serialization, filtered by component type, with entity references preserved.
- Multiple independent worlds, mergeable whole or in fragments, with ids remapped.
- Typed event queues, emitted anywhere and collected by any system.


## Documentation
- [Manual](manual.md), a guided tour of the library.
- [API reference](https://rowdaboat.github.io/vecs/), generated from the source.
