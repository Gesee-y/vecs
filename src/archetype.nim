# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import std/[macros, genasts, hashes, sets, algorithm]
import tables
import ecsseq
import componentid, archetypeid, operations


type Archetype* = ref object
  id*: ArchetypeId
  componentIds*: seq[ComponentId]
  componentLists*: Table[ComponentId, EcsSeqAny]
  componentSequences: seq[EcsSeqAny]
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
  var componentOrder = newSeq[int](componentIds.len)

  for index in 0..<componentOrder.len:
    componentOrder[index] = index

  componentOrder.sort do (left, right: int) -> int:
    cmp(componentIds[left].int, componentIds[right].int)

  var orderedComponentIds = newSeq[ComponentId](componentIds.len)
  var orderedBuilders = newSeq[Builder](builders.len)

  for index in 0..<componentOrder.len:
    let sourceIndex = componentOrder[index]
    orderedComponentIds[index] = componentIds[sourceIndex]
    orderedBuilders[index] = builders[sourceIndex]

  let archetypeId = archetypeIdFrom orderedComponentIds
  var componentLists = initTable[ComponentId, EcsSeqAny]()
  var componentSequences = newSeqOfCap[EcsSeqAny](orderedComponentIds.len)

  for index in 0..<orderedComponentIds.len:
    let componentId = orderedComponentIds[index]
    let componentSequence = orderedBuilders[index]()
    componentLists[componentId] = componentSequence
    componentSequences.add componentSequence

  Archetype(
    id: archetypeId,
    componentIds: orderedComponentIds,
    componentLists: componentLists,
    componentSequences: componentSequences,
    builders: orderedBuilders
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


proc add*(archetype: var Archetype, components: openArray[ComponentBytes]): int =
  for component in components:
    let bytesPtr = if component.data.len > 0: unsafeAddr component.data[0] else: nil
    result = archetype.componentLists[component.id].copyByte(bytesPtr)


proc remove*(archetype: var Archetype, archetypeEntityId: int) =
  for componentSequence in archetype.componentSequences:
    componentSequence.del archetypeEntityId


proc moveExisting*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype): int =
  var targetIndex = 0

  for index in 0..<fromArchetype.componentSequences.len:
    var fromEcsSeq = fromArchetype.componentSequences[index]
    let componentId = fromArchetype.componentIds[index]

    while toArchetype.componentIds[targetIndex] != componentId:
      inc targetIndex

    var toEcsSeq = toArchetype.componentSequences[targetIndex]
    result = moveEcsSeq(fromEcsSeq, fromArchetypeEntityId, toEcsSeq)
    inc targetIndex


proc moveAdding*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype, components: openArray[ComponentBytes]): int =
  result = fromArchetype.moveExisting(fromArchetypeEntityId, toArchetype)

  for component in components:
    let bytesPtr = if component.data.len > 0: unsafeAddr component.data[0] else: nil
    let index = copyByte(toArchetype.componentLists[component.id], bytesPtr)
    when not defined(danger): assert result == index


proc moveRemoving*(fromArchetype: var Archetype, fromArchetypeEntityId: int, toArchetype: var Archetype): int =
  var targetIndex = 0

  for index in 0..<fromArchetype.componentIds.len:
    let compId = fromArchetype.componentIds[index]
    var fromEcsSeq = fromArchetype.componentSequences[index]

    if targetIndex < toArchetype.componentIds.len and toArchetype.componentIds[targetIndex] == compId:
      var toEcsSeq = toArchetype.componentSequences[targetIndex]
      result = moveEcsSeq(fromEcsSeq, fromArchetypeEntityId, toEcsSeq)
      inc targetIndex
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
