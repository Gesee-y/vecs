# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.


type EcsSeqAny* = ref object of RootObj


type EcsSeq*[T] = ref object of EcsSeqAny
  data*: seq[T]


type Builder* =
  proc(): EcsSeqAny {.nimcall.}


type Adder* =
  proc(ecsSeq: var EcsSeqAny, slot: int)


type Mover* =
  proc(fromEcsSeq: var EcsSeqAny, fromIndex: int, toEcsSeq: var EcsSeqAny, toIndex: int) {.nimcall.}


type Getter* =
  proc(fromEcsSeq: EcsSeqAny, index: int): EcsSeqAny {.nimcall.}


proc add*[T](self: EcsSeq[T], item: sink T): int =
  self.data.add item
  self.data.len - 1


proc addAt*[T](self: EcsSeq[T], index: int, value: sink T) =
  if index >= self.data.len:
    self.data.setLen(index + 1)
  self.data[index] = value


proc len*[T](self: EcsSeq[T]): int =
  self.data.len


proc `[]`*[T](self: EcsSeq[T], index: int): var T =
  self.data[index]


proc `[]=`*[T](self: EcsSeq[T], index: int, value: sink T) =
  self.data[index] = value


proc `$`*[T](self: EcsSeq[T]): string =
  $self.data


proc ecsSeqBuilder*[T](): Builder =
  proc(): EcsSeqAny = EcsSeq[T]()


proc ecsSeqMover*[T](): Mover =
  proc(fromEcsSeq: var EcsSeqAny, fromIndex: int, toEcsSeq: var EcsSeqAny, toIndex: int) =
    var typedFromEcsSeq = cast[EcsSeq[T]](fromEcsSeq)
    var typedToEcsSeq = cast[EcsSeq[T]](toEcsSeq)
    typedToEcsSeq.addAt(toIndex, typedFromEcsSeq[fromIndex])


proc ecsSeqGetter*[T](): Getter =
  proc(fromEcsSeq: EcsSeqAny, index: int): EcsSeqAny {.nimcall.} =
    let source = cast[EcsSeq[T]](fromEcsSeq)
    let snapshot = EcsSeq[T]()
    snapshot.addAt(0, source[index])
    snapshot
