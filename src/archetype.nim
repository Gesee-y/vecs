# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import std/[macros, genasts, hashes, sets]
import tables
import ecsseq
import componentid, archetypeid


type Archetype* = ref object
  id*: ArchetypeId
  componentIds*: seq[ComponentId]
  componentLists*: Table[ComponentId, EcsSeqAny]
  builders: seq[Builder]


macro fieldTypes*(tup: typed, body: untyped): untyped =
  result = newStmtList()
  let tup =
    if tup.kind != nnkTupleConstr:
      tup.getTypeInst[^1]
    else:
      tup

  for x in tup:
    let body = body.copyNimTree()
    body.insert 0:
      genast(x):
        type FieldType {.inject.} = x
    result.add nnkIfStmt.newTree(nnkElifBranch.newTree(newLit(true), body))
  result = nnkBlockStmt.newTree(newEmptyNode(), result)


proc makeArchetype*(componentIds: seq[ComponentId], builders: seq[Builder]): Archetype =
  let archetypeId = archetypeIdFrom componentIds
  var componentLists = initTable[ComponentId, EcsSeqAny]()

  for index in 0..<componentIds.len:
    let componentId = componentIds[index]
    componentLists[componentId] = builders[index]()

  Archetype(
    id: archetypeId,
    componentIds: componentIds,
    componentLists: componentLists,
    builders: builders
  )


proc makeNextAdding*(archetype: Archetype, compIds: seq[ComponentId], builders: seq[Builder]): Archetype =
  let newCompIds = archetype.componentIds & compIds
  let newBuilders = archetype.builders & builders
  makeArchetype(newCompIds, newBuilders)


proc makeNextRemoving*(archetype: Archetype, compIds: seq[ComponentId]): Archetype =
  var newCompIds: seq[ComponentId] = @[]
  var newBuilders: seq[Builder] = @[]
  let toRemove = compIds.toHashSet

  for index in 0..<archetype.componentIds.len:
    let compId = archetype.componentIds[index]
    if (not toRemove.contains(compId)):
      newCompIds.add compId
      newBuilders.add archetype.builders[index]

  makeArchetype(newCompIds, newBuilders)


iterator entities*(archetype: Archetype): int =
  let firstCompId = archetype.componentIds[0]
  let firstComponentList = archetype.componentLists[firstCompId]
  for index in firstComponentList.ids:
    yield index


iterator components*[T](archetype: Archetype, componentId: ComponentId): T =
  let ecsSeq = archetype.componentLists[componentId]
  for index in ecsSeq.ids:
    yield cast[EcsSeq[T]](ecsSeq)[index]


proc addField[T](ecsSeqAny: EcsSeqAny, item: sink T): int =
  cast[EcsSeq[T]](ecsSeqAny).add item


proc add*[T: tuple](archetype: var Archetype, components: sink T): int =
  for name, field in fieldPairs components:
    let componentId = (typeof field).toComponentId
    result = addField(archetype.componentLists[componentId], field)


proc add*(archetype: var Archetype, rawComponents: Table[ComponentId, seq[byte]]): int =
  for compId, bytes in rawComponents.pairs:
    let bytesPtr = if bytes.len > 0: unsafeAddr bytes[0] else: nil
    result = archetype.componentLists[compId].addByte(bytesPtr)


proc remove*(archetype: var Archetype, archetypeEntityId: int) =
  for components in archetype.componentLists.values:
    components.del archetypeEntityId


proc moveAdding*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype, rawComponents: Table[ComponentId, seq[byte]]): int =
  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    var fromEcsSeq = fromArchetype.componentLists[compId]
    var toEcsSeq = toArchetype.componentLists[compId]
    result = moveEcsSeq(fromEcsSeq, fromArchetypeEntityId, toEcsSeq)

  for compId, bytes in rawComponents.pairs:
    let bytesPtr = if bytes.len > 0: unsafeAddr bytes[0] else: nil
    let index = addByte(toArchetype.componentLists[compId], bytesPtr)
    when not defined(danger): assert result == index


proc moveRemoving*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype): int =
  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    var fromEcsSeq = fromArchetype.componentLists[compId]

    if (toArchetype.id.contains compId):
      var toEcsSeq = toArchetype.componentLists[compId]
      result = moveEcsSeq(fromEcsSeq, fromArchetypeEntityId, toEcsSeq)
    else:
      fromEcsSeq.del fromArchetypeEntityId


proc contains*(archetype: Archetype, candidateId: ComponentId): bool =
  candidateId in archetype.id


proc contains*(archetype: Archetype, candidateId: ArchetypeId): bool =
  archetype.id.contains candidateId


proc disjointed*(archetype: Archetype, candidateId: ArchetypeId): bool =
  archetype.id.disjointed candidateId


proc isEmpty*(archetype: Archetype): bool =
  for componentList in archetype.componentLists.values:
    return componentList.len == 0
