# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import tables, intsets
import entityid, componentid

type OperationKind* = enum
  RemoveEntity
  AddComponents
  RemoveComponents


type Operation* = object
  id*: EntityId
  case kind*: OperationKind:
  of RemoveEntity:
    discard
  of AddComponents:
    rawComponentsById*: Table[ComponentId, seq[byte]]
  of RemoveComponents:
    compIdsToRemove*: PackedSet[ComponentId]
