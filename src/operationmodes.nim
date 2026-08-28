# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import macros, tables
import ecsseq, queries


type OperationModeKind* = enum
  DeferredMode
  ImmediateMode
  AfterMode


type OperationMode*[T: tuple] = object
  case kind*: OperationModeKind
  of DeferredMode, ImmediateMode:
    discard
  of AfterMode:
    query*: ptr[Query[T]]


const Immediate* = OperationMode[(int,)](kind: ImmediateMode)
const Deferred* = OperationMode[(int,)](kind: DeferredMode)


proc after*[T: tuple](query: var Query[T]): OperationMode[T] =
  OperationMode[T](kind: AfterMode, query: addr query)
