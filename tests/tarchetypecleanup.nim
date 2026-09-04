# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import ../src/[examples, vecs]


suite "Archetype cleanup should":
  setup:
    var world = World()
    let marcusId = world.add((Character(name: "Marcus", class: "Warrior"),), Immediate)
    world.add(marcusId, Health(health: 120, maxHealth: 120), Immediate)


  test "leave a world queryable after cleaning up empty archetypes":
    world.cleanupEmptyArchetypes()

    var query: Query[(Meta, Character)]
    var characterCount = 0

    for (meta, character) in world.query(query):
      inc characterCount
      check character.name == "Marcus"

    checkpoint("Only Marcus should be matched, and scanning must skip cleaned up archetypes")
    check characterCount == 1


  test "tolerate cleaning up empty archetypes twice":
    world.cleanupEmptyArchetypes()
    world.cleanupEmptyArchetypes()

    var query: Query[(Meta, Character)]
    var characterCount = 0

    for (meta, character) in world.query(query):
      inc characterCount

    checkpoint("A second cleanup must not disturb the surviving archetypes")
    check characterCount == 1


  test "invalidate cached query matches when archetypes are cleaned up":
    let elenaId = world.add((Character(name: "Elena", class: "Mage"),), Immediate)

    var query: Query[(Meta, Character)]
    var countBeforeCleanup = 0

    for (meta, character) in world.query(query):
      inc countBeforeCleanup

    checkpoint("Marcus and Elena live in different archetypes, both matched and cached")
    check countBeforeCleanup == 2

    world.add(elenaId, Health(health: 80, maxHealth: 80), Immediate)
    world.cleanupEmptyArchetypes()

    var countAfterCleanup = 0

    for (meta, character) in world.query(query):
      inc countAfterCleanup

    checkpoint("The cached match for the emptied archetype must be dropped")
    check countAfterCleanup == 2


  test "match archetypes registered after a cleanup freed their slot":
    world.cleanupEmptyArchetypes()

    var query: Query[(Meta, Weapon)]
    var countBeforeWeapon = 0

    for (meta, weapon) in world.query(query):
      inc countBeforeWeapon

    checkpoint("No entity carries a Weapon yet")
    check countBeforeWeapon == 0

    discard world.add((Weapon(name: "Sword", attack: 10),), Immediate)

    var countAfterWeapon = 0

    for (meta, weapon) in world.query(query):
      inc countAfterWeapon
      check weapon.name == "Sword"

    checkpoint("A query must see an archetype registered into a slot freed by cleanup")
    check countAfterWeapon == 1
