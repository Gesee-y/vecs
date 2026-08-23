# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest, sets
import ../src/[examples, vecs]


type ReadCopyProbe = object
  value: int


type WriteProbe = object
  value: int


type QueryTag = object


var componentCopyCount = 0


proc `=copy`(target: var ReadCopyProbe, source: ReadCopyProbe) =
  target.value = source.value
  inc componentCopyCount


suite "Queries should":
  setup:
    var world = World()
    let marcus = (Character(name: "Marcus", class: "Warrior"), Health(health: 120, maxHealth: 120))
    let elena = (Character(name: "Elena", class: "Mage"), Health(health: 80, maxHealth: 80))
    let grimm = (Character(name: "Grimm", class: "Paladin"), Health(health: 15, maxHealth: 100))
    let marcusId = world.add(marcus, Immediate)
    let elenaId = world.add(elena, Immediate)
    let grimmId = world.add(grimm, Immediate)

  test "query components for removal":

    world.remove(elenaId, Health)
    var removeCount = 0

    for (meta, health) in world.queryForRemoval(Health):
      inc removeCount
      checkpoint("Health should be removed from Elena")
      check meta.id == elenaId
      checkpoint("Only one compnent should be removed")
      check removeCount == 1

    check removeCount == 1

    world.consolidate()

    checkpoint("After consolidation, no more components should appear in a query for components to be removed")
    for (meta, health) in world.queryForRemoval(Health):
      fail()

    world.remove(grimmId, Health, Immediate)

    checkpoint("After an immediate removal, no components should appear in a query for components to be removed")
    for (meta, health) in world.queryForRemoval(Health):
      fail()

  test "query components for reading":
    var query: Query[(Meta, Character, Health)]
    var characters = @[marcusId, elenaId, grimmId].toHashSet

    checkpoint("All 3 characters should be read")
    for (meta, character, health) in world.query(query):
      if meta.id notin characters:
        fail()


  test "query optional components":
    world.add(marcusId, Weapon(name: "Sword", attack: 10), Immediate)
    var query: Query[(Meta, Opt[Weapon])]
    var foundCount = 0
    var weaponCount = 0
    var missingCount = 0

    for (meta, weapon) in world.query(query):
      inc foundCount

      weapon.isSomething:
        inc weaponCount
        check meta.id == marcusId
        check value.name == "Sword"

      weapon.isNothing:
        inc missingCount
        check meta.id != marcusId

    check foundCount == 3
    check weaponCount == 1
    check missingCount == 2


  test "query for deferred component addition":
    var sword = Weapon(name: "Excalibur", attack: 25)
    world.add((sword,))

    checkpoint("Query should return nothing before consolidation.")
    var query: Query[(Meta, Weapon)]
    var foundCount = 0
    for (meta, weapon) in world.query(query):
      inc foundCount
    check foundCount == 0

    world.consolidate()

    checkpoint("Query should return the component with correct properties after consolidation.")
    foundCount = 0

    for (meta, weapon) in world.query(query):
      inc foundCount
      check weapon.name == "Excalibur"
      check weapon.attack == 25

    check foundCount == 1

  test "query for removal should not yield added components":
    checkpoint("Adding a component should not make it appear in removal query.")
    var sword = Weapon(name: "Sword", attack: 10)
    world.add(elenaId, sword)

    var removalCount = 0
    for (meta, weapon) in world.queryForRemoval(Weapon):
      inc removalCount

    checkpoint("Nothing should be yielded from removal query when component is added.")
    check removalCount == 0


  test "avoid copying components while scanning removals":
    var removalWorld = World()
    discard removalWorld.add((ReadCopyProbe(value: 1),), Immediate)
    let removedId = removalWorld.add((ReadCopyProbe(value: 2),), Immediate)
    discard removalWorld.add((ReadCopyProbe(value: 3),), Immediate)

    removalWorld.remove(removedId, ReadCopyProbe)
    componentCopyCount = 0

    var foundCount = 0

    for (meta, readProbe) in removalWorld.queryForRemoval(ReadCopyProbe):
      inc foundCount
      check meta.id == removedId
      check readProbe.value == 2

    check foundCount == 1
    check componentCopyCount == 1


  test "preserve value semantics for read access":
    discard world.add((ReadCopyProbe(value: 7),), Immediate)
    var query: Query[(ReadCopyProbe,)]
    var foundCount = 0

    componentCopyCount = 0

    for (readProbe,) in world.query(query):
      inc foundCount
      check readProbe.value == 7

    check foundCount == 1
    check componentCopyCount == 1


  test "preserve read snapshots for duplicate write access":
    let entityId = world.add((WriteProbe(value: 5),), Immediate)
    var query: Query[(WriteProbe, Write[WriteProbe])]

    for (snapshot, writeProbe) in world.query(query):
      writeProbe.value += 1
      check snapshot.value == 5

    check world.read(entityId, WriteProbe).value == 6


  test "query after deleting the first archetype row":
    var fragmentedWorld = World()
    let removedId = fragmentedWorld.add((Health(health: 10),), Immediate)
    let retainedId = fragmentedWorld.add((Health(health: 20),), Immediate)

    fragmentedWorld.remove(removedId, Immediate)

    var query: Query[(Meta, Write[Health])]
    var foundCount = 0

    for (meta, health) in fragmentedWorld.query(query):
      inc foundCount
      check meta.id == retainedId
      health.health += 1

    check foundCount == 1
    check fragmentedWorld.read(retainedId, Health).health == 21


  test "query tag components":
    discard world.add((QueryTag(),), Immediate)

    var query: Query[(QueryTag,)]
    var foundCount = 0

    for (tag,) in world.query(query):
      discard tag
      inc foundCount

    check foundCount == 1


  test "support queries containing only an exclusion":
    var query: Query[(Not[Weapon],)]
    var foundCount = 0

    for emptyTuple in world.query(query):
      discard emptyTuple
      inc foundCount

    check foundCount == 3
