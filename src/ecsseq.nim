# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import vseq

type EcsSeqAny* = ref object of RootObj
  deleted: seq[bool]
  free: seq[int]
  rawPtr*: pointer # Point to the raw data

type EcsSeq*[T] = ref object of EcsSeqAny
  data*: VSeq[T]


type Builder* =
  proc(): EcsSeqAny {.nimcall.}


type Adder* =
  proc(ecsSeq: var EcsSeqAny, itemPtr: pointer): int {.nimcall.}


type Mover* =
  proc(fromEcsSeq: var EcsSeqAny, index: int, toEcsSeq: var EcsSeqAny): int {.nimcall.}


type Getter* =
  proc(fromEcsSeq: EcsSeqAny, index: int): EcsSeqAny {.nimcall.}


iterator ids*(self: EcsSeqAny): int =
  if self.free.len == 0:
    for index in 0..<self.deleted.len:
      yield index
  else:
    for index in 0..<self.deleted.len:
      if not self.deleted[index]:
        yield index


proc initialize[T](self: EcsSeq[T]) =
  if self.rawPtr != nil:
    return

  self.data.stride = sizeof(T)
  self.rawPtr = cast[pointer](addr self.data)


proc add*[T](self: EcsSeq[T], item: sink T): int =
  self.initialize()

  if self.free.len > 0:
    let index = self.free.pop()
    self.data[index] = item
    self.deleted[index] = false
    result = index
  else:
    self.data.add item
    self.deleted.add false
    result = self.data.len - 1


# Type erased adder.
proc addByte*(self: EcsSeqAny, item: ptr byte): int =
  if self.free.len > 0:
    let index = self.free.pop()
    
    self.rawPtr.unsafeSet(index, item)
    self.deleted[index] = false
    result = index
  else:
    let index = self.deleted.len

    self.rawPtr.unsafeAdd(item)
    self.deleted.add false
    result = index

  zeroMem(item, self.rawPtr.unsafeStride[])


proc del*(self: EcsSeqAny, index: int) =
  self.deleted[index] = true
  self.free.add index
  var rawSrc = cast[ptr UncheckedArray[byte]](self.rawPtr.unsafeData[])
  let stride = self.rawPtr.unsafeStride[]
  let startIndex = index * stride
  if stride > 0:
    {.push boundChecks: off.}
    # Zero out deleted element memory to prevent ARC/ORC double-free when sequence is disposed.
    zeroMem(addr rawSrc[][startIndex], stride)
    {.pop.}


proc len*(self: EcsSeqAny): int =
  self.deleted.len - self.free.len

proc stride*(self: EcsSeqAny): int = self.rawPtr.unsafeStride[]

proc has*(self: EcsSeqAny, index: int): bool =
  index >= 0 and
  index < self.deleted.len and
  not self.deleted[index]


proc `[]`*[T](self: EcsSeq[T], index: int): var T =
  self.data[index]


proc `[]=`*[T](self: var EcsSeq[T], index: int, value: T) =
  self.data[index] = value


proc addAt*[T](self: var EcsSeq[T], index: int, value: T) =
  self.initialize()

  if index >= self.data.len:
    let oldLen = self.data.len
    self.data.setLen(index + 1)
    self.deleted.setLen(index + 1)

    for i in oldLen ..< self.data.len - 1:
      self.deleted[i] = true
      self.free.add i

  if self.deleted[index]:
    let freeIndex = self.free.find(index)
    if freeIndex >= 0:
      self.free.del(freeIndex)

  self.data[index] = value
  self.deleted[index] = false


proc `$`*[T](self: EcsSeq[T]): string =
  result &= "@["

  for i in 0..<self.data.len:
    if not self.deleted[i]:
      result &= $self.data[i]
      if i < self.data.len - 1:
        result &= ", "

  result &= "]"


proc buildEcsSeq*[T](): EcsSeq[T] = 
  var res = EcsSeq[T]()
  res.data = newVSeq[T]()
  res.initialize()
  res


proc ecsSeqBuilder*[T](): Builder =
  proc(): EcsSeqAny {.nimcall.} = buildEcsSeq[T]()


proc ecsSeqAdder*[T](): Adder =
  proc(ecsSeq: var EcsSeqAny, itemPtr: pointer): int {.nimcall.} =
    cast[EcsSeq[T]](ecsSeq).add cast[ptr T](itemPtr)[]

#[
proc ecsSeqMover*[T](): Mover =
  proc(fromEcsSeq: var EcsSeqAny, index: int, toEcsSeq: var EcsSeqAny): int {.nimcall.} =
    var typedFrom = cast[EcsSeq[T]](fromEcsSeq)
    var typedTo = cast[EcsSeq[T]](toEcsSeq)
    let element = typedFrom[index]
    var rawSrc = cast[ptr seq[byte]](fromEcsSeq.rawPtr)
    let startIndex = index * fromEcsSeq.stride
    if fromEcsSeq.stride > 0:
      {.push boundChecks: off.}
      # Zero out the moved element memory in source to prevent double free or dropping invalid references later
      zeroMem(addr rawSrc[][startIndex], fromEcsSeq.stride)
      {.pop.}
    fromEcsSeq.del index
    result = typedTo.add element
]#

proc moveEcsSeq*(fromEcsSeq: var EcsSeqAny, index: int, toEcsSeq: var EcsSeqAny): int =
  var rawSrc = cast[ptr UncheckedArray[byte]](fromEcsSeq.rawPtr.unsafeData[])
  let stride = fromEcsSeq.rawPtr.unsafeStride[]
  let startIndex = index * stride

  {.push boundChecks: off.}
  let srcPtr = if stride > 0: addr rawSrc[][startIndex] else: nil
  {.pop.}

  result = toEcsSeq.addByte(srcPtr)

  if srcPtr != nil and stride > 0:
    # Zero out the moved element memory in source to prevent double free or dropping invalid references later
    zeroMem(srcPtr, stride)

  fromEcsSeq.del index


proc ecsSeqGetter*[T](): Getter =
  proc(fromEcsSeq: EcsSeqAny, index: int): EcsSeqAny {.nimcall.} =
    let source = cast[EcsSeq[T]](fromEcsSeq)
    let snap = buildEcsSeq[T]()
    discard snap.add source[index]
    snap
