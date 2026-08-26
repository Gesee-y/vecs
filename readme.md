# vecs
A fast, archetype-based ECS for Nim👑. Components are plain `object`s stored in contiguous columns for cache-friendly iteration, with cached queries, deferred structural changes, snapshots, and serialization built in. No base types nor registration for components is required.


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


## Credits
`vecs` began as a spin-off of [Beef🥩](https://github.com/beef331)'s [yeacs](https://github.com/beef331/nimtrest/blob/master/yeacs.nim). Its early API mirrored yeacs closely and some macros were adapted directly. It has since diverged: `vecs` erases components via abstract types cast to concrete ones (rather than memory copies), and stores one collection per component type per archetype instead of a single collection of component tuples.
