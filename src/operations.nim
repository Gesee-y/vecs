# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import intsets
import entityid, componentid

type OperationKind* = enum
  RemoveEntity
  AddComponents
  RemoveComponents


type ComponentBytes* = object
  id*: ComponentId
  data*: seq[byte]


type Operation* = object
  id*: EntityId
  case kind*: OperationKind:
  of RemoveEntity:
    discard
  of AddComponents:
    componentsToAdd*: seq[ComponentBytes]
  of RemoveComponents:
    compIdsToRemove*: PackedSet[ComponentId]
