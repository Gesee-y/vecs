# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest
import std/strutils
import ../../src/[vecs, id]


type
  Node = object
    name: string
    parentId: Id[Node]
    childrenIds: seq[Id[Node]]


  Transform = object
    position: array[3, float32]
    rotation: array[4, float32]


  Point = object
    x: float32
    y: float32


  Shape = object
    origin: Point


  Frame = object
    matrix: array[4, float32]


  Placement = object
    frame: Frame


  Inside = object
    target: Id[Node]
    entity: EntityId


  Outside = object
    inside: Inside


  Leaf = object
    value: float32


  Branch = object
    leaf: Leaf


  Trunk = object
    branch: Branch


  ValueSetter = proc(value: float32)


  Material = object
    path: string
    texture {.transient.}: int


  Model = object
    name: string
    material: Material


  Channel = object
    target: string
    setter {.transient.}: ValueSetter


  Timeline = object
    channels: seq[Channel]


proc noValueSetter(value: float32) =
  discard


suite "Text (JSON) serialization of complex fields should":
  test "round-trip an Id[] field":
    var world = World()
    let rootId = world.add((Node(name: "root"),), Immediate) of Node
    let childId = world.add((Node(name: "child", parentId: rootId),), Immediate) of Node

    let text = world.serializeToText((Node,))
    var restored = deserializeFromText(text, (Node,))

    checkpoint("The child's parentId should still point at the root entity.")
    check restored.read(childId).parentId == rootId

    checkpoint("The root has no parent, so parentId should stay invalid.")
    check restored.read(rootId).parentId == Id[Node]()


  test "round-trip an Id[] pointing at a recycled entity":
    var world = World()
    let staleId = world.add((Node(name: "stale"),), Immediate)
    world.remove(staleId, Immediate)
    let rootId = world.add((Node(name: "root"),), Immediate) of Node
    let childId = world.add((Node(name: "child", parentId: rootId),), Immediate) of Node

    let text = world.serializeToText((Node,))
    var restored = deserializeFromText(text, (Node,))

    checkpoint("The root should have taken the removed entity's slot under a newer generation.")
    check rootId.value == staleId.value
    check rootId.generation != staleId.generation

    checkpoint("The child's parentId should still point at the root.")
    check restored.read(childId).parentId == rootId

    checkpoint("The root should be reachable under the id the child holds.")
    check restored.has(restored.read(childId).parentId.entityId)


  test "round-trip a seq of Id[] fields":
    var world = World()
    let rootId = world.add((Node(name: "root"),), Immediate) of Node
    let childAId = world.add((Node(name: "childA", parentId: rootId),), Immediate) of Node
    let childBId = world.add((Node(name: "childB", parentId: rootId),), Immediate) of Node

    for parent in world.write(rootId):
      parent.childrenIds = @[childAId, childBId]

    let text = world.serializeToText((Node,))
    var restored = deserializeFromText(text, (Node,))

    check restored.read(rootId).childrenIds == @[childAId, childBId]


  test "round-trip a fixed size array field":
    var world = World()
    let transform = Transform(position: [1.0'f32, 2.0'f32, 3.0'f32], rotation: [0.0'f32, 0.0'f32, 0.0'f32, 1.0'f32])
    let entityId = world.add((transform,), Immediate)

    let text = world.serializeToText((Transform,))
    var restored = deserializeFromText(text, (Transform,))

    check restored.read(entityId, Transform) == transform


  test "round-trip a nested object field":
    var world = World()
    let shape = Shape(origin: Point(x: 3.0'f32, y: 4.0'f32))
    let entityId = world.add((shape,), Immediate)

    let text = world.serializeToText((Shape,))
    var restored = deserializeFromText(text, (Shape,))

    check restored.read(entityId, Shape) == shape


  test "round-trip a nested object field holding a fixed size array":
    var world = World()
    let placement = Placement(frame: Frame(matrix: [1.0'f32, 0.0'f32, 0.0'f32, 1.0'f32]))
    let entityId = world.add((placement,), Immediate)

    let text = world.serializeToText((Placement,))
    var restored = deserializeFromText(text, (Placement,))

    check restored.read(entityId, Placement) == placement


  test "round-trip ids held inside a nested object":
    var world = World()
    let rootId = world.add((Node(name: "root"),), Immediate) of Node
    let holderId = world.add((Outside(inside: Inside(target: rootId, entity: rootId.entityId)),), Immediate)

    let text = world.serializeToText((Node, Outside))
    var restored = deserializeFromText(text, (Node, Outside))
    let inside = restored.read(holderId, Outside).inside

    checkpoint("An Id[] two levels down should survive.")
    check inside.target == rootId

    checkpoint("A plain EntityId two levels down should survive.")
    check inside.entity == rootId.entityId


  test "round-trip plain objects nested several levels deep":
    var world = World()
    let trunk = Trunk(branch: Branch(leaf: Leaf(value: 2.5'f32)))
    let entityId = world.add((trunk,), Immediate)

    let text = world.serializeToText((Trunk,))
    var restored = deserializeFromText(text, (Trunk,))

    check restored.read(entityId, Trunk) == trunk


  test "skip a transient field nested in an object field":
    var world = World()
    let model = Model(name: "hero", material: Material(path: "hero.png", texture: 42))
    let entityId = world.add((model,), Immediate)

    let text = world.serializeToText((Model,))

    checkpoint("A transient field one level down should not appear in the serialized text.")
    check not text.contains("texture")

    var restored = deserializeFromText(text, (Model,))
    let material = restored.read(entityId, Model).material

    checkpoint("Its non-transient sibling should survive the round-trip.")
    check material.path == "hero.png"

    checkpoint("A nested transient field should read back at its default value.")
    check material.texture == 0


  test "skip a transient field of an unserializable type nested in a seq of objects":
    var world = World()
    let timeline = Timeline(channels: @[
      Channel(target: "Transform.position.x", setter: noValueSetter),
      Channel(target: "Transform.position.y", setter: noValueSetter)
    ])
    let entityId = world.add((timeline,), Immediate)

    let text = world.serializeToText((Timeline,))

    checkpoint("A transient field of a seq element should not appear in the serialized text.")
    check not text.contains("setter")

    var restored = deserializeFromText(text, (Timeline,))
    let channels = restored.read(entityId, Timeline).channels

    checkpoint("Every element should survive the round-trip with its non-transient fields.")
    check channels.len == 2
    check channels[0].target == "Transform.position.x"
    check channels[1].target == "Transform.position.y"

    checkpoint("A transient field inside a seq element should read back at its default value.")
    check channels[0].setter.isNil
    check channels[1].setter.isNil
