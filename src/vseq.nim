## VSeq - A custom seq implementation for Nim
## Uses ptr UncheckedArray[T] with secure memory handling
##
## Features:
## - Manual memory management via alloc/dealloc
## - Zero-fills old memory after reallocation
## - Type-erasure byte view for raw memory access
## - Full Nim 2.0 lifetime hooks (ARC/ORC compatible)

import std/[typetraits, strutils]

type
  VSeq*[T] = object
    ## A growable vector backed by raw memory.
    ## After every reallocation the old buffer is zeroed before freeing.
    len*: int
    cap*: int
    stride*: int
    data*: ptr UncheckedArray[T]

# -----------------------------------------------------------------------------
# Lifetime hooks (ARC / ORC)
# -----------------------------------------------------------------------------

proc `=destroy`*[T](s: var VSeq[T]) =
  if s.data != nil:
    for e in s.mitems:
      `=destroy`(e)
    
    dealloc(s.data)
    s.data = nil
    s.len = 0
    s.cap = 0

proc `=sink`*[T](dest: var VSeq[T]; src: VSeq[T]) =
  if dest.data != nil and dest.data != src.data:
    zeroMem(dest.data, dest.cap * sizeof(T))
    dealloc(dest.data)
  dest.data = src.data
  dest.len = src.len
  dest.cap = src.cap
  dest.stride = src.stride

proc `=copy`*[T](dest: var VSeq[T]; src: VSeq[T]) =
  if src.data == dest.data:
    return
  if src.data == nil:
    `=destroy`(dest)
    dest.data = nil
    dest.len = 0
    dest.cap = 0
    dest.stride = sizeof(T)
  else:
    let newCap = src.cap
    let newData = cast[ptr UncheckedArray[T]](alloc(newCap * sizeof(T)))
    copyMem(newData, src.data, src.len * sizeof(T))
    zeroMem(cast[pointer](cast[int](newData) + src.len * sizeof(T)),
            (newCap - src.len) * sizeof(T))
    `=destroy`(dest)
    dest.data = newData
    dest.len = src.len
    dest.cap = newCap
    dest.stride = src.stride

proc `=dup`*[T](src: VSeq[T]): VSeq[T] =
  if src.data != nil:
    result.cap = src.cap
    result.len = src.len
    result.stride = src.stride
    result.data = cast[ptr UncheckedArray[T]](alloc(result.cap * sizeof(T)))
    copyMem(result.data, src.data, result.len * sizeof(T))
    zeroMem(cast[pointer](cast[int](result.data) + result.len * sizeof(T)),
            (result.cap - result.len) * sizeof(T))

# -----------------------------------------------------------------------------
# Constructors
# -----------------------------------------------------------------------------

proc default*[T](s: typedesc[VSeq[T]]): VSeq[T] =
  result.stride = sizeof(T)

proc newVSeq*[T](len: int = 0): VSeq[T] =
  ## Create a new empty VSeq with a given capacity.
  result.stride = sizeof(T)
  if len > 0:
    result.cap = len
    result.len = len
    result.data = cast[ptr UncheckedArray[T]](alloc(len * sizeof(T)))
    zeroMem(result.data, len * sizeof(T))

proc newVSeqOfCap*[T](cap: int): VSeq[T] =
  result.stride = sizeof(T)
  if cap > 0:
    result.cap = cap
    result.data = cast[ptr UncheckedArray[T]](alloc(cap * sizeof(T)))
    zeroMem(result.data, cap * sizeof(T))

# -----------------------------------------------------------------------------
# Basic properties
# -----------------------------------------------------------------------------

proc len*[T](s: VSeq[T]): int {.inline.} = s.len
proc unsafeLen(s: pointer): ptr int {.inline.} = cast[ptr int](s)
proc cap*[T](s: VSeq[T]): int {.inline.} = s.cap
proc unsafeCap(s: pointer): ptr int {.inline.} = cast[ptr int](cast[pointer](cast[int](s) + sizeof(int)))
proc high*[T](s: VSeq[T]): int {.inline.} = s.len - 1
proc low*[T](s: VSeq[T]): int {.inline.} = 0
proc unsafeStride*(s: pointer): ptr int = cast[ptr int](cast[pointer](cast[int](s) + sizeof(int)*2))
proc unsafeData*(s: pointer): ptr pointer = cast[ptr pointer](cast[pointer](cast[int](s) + sizeof(int)*3))

proc `$`*[T](s: VSeq[T]): string =
  "VSeq[" & name(T) & "](len: " & $s.len & ", cap: " & $s.cap & ")"

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

proc ensureCap[T](s: var VSeq[T]; minCap: int) =
  if minCap <= s.cap:
    return
  var newCap = if s.cap == 0: 4 else: s.cap * 2
  if newCap < minCap:
    newCap = minCap
  let newData = cast[ptr UncheckedArray[T]](alloc(newCap * sizeof(T)))
  if s.len > 0:
    copyMem(newData, s.data, s.len * sizeof(T))
  zeroMem(cast[pointer](cast[int](newData) + s.len * sizeof(T)),
          (newCap - s.len) * sizeof(T))
  let oldData = s.data
  let oldCap = s.cap
  s.data = newData
  s.cap = newCap
  if oldData != nil:
    zeroMem(oldData, oldCap * sizeof(T))
    dealloc(oldData)

proc unsafeEnsureCap(s: pointer; minCap: int) =
  var scap = s.unsafeCap
  var sdata = s.unsafeData
  var stride = s.unsafeStride[]
  var slen = s.unsafeLen[]
  
  if minCap <= scap[]:
    return
  
  var newCap = if scap[] == 0: 4 else: scap[] * 2
  if newCap < minCap:
    newCap = minCap
  
  let newData = cast[ptr UncheckedArray[byte]](alloc(newCap * stride))
  zeroMem(cast[pointer](cast[int](newData) + slen * stride),
          (newCap - slen) * stride)
  if slen > 0:
    copyMem(newData, sdata[], slen * stride)
  
  let oldData = sdata[]
  let oldCap = scap[]
  sdata[] = newData
  scap[] = newCap
  if oldData != nil:
    zeroMem(oldData, oldCap * stride)
    dealloc(oldData)

# -----------------------------------------------------------------------------
# Element access
# -----------------------------------------------------------------------------

proc `[]`*[T](s: VSeq[T]; i: int): lent T {.inline.} =
  when not defined(danger):
    if i < 0 or i >= s.len:
      raise newException(IndexDefect, "index " & $i & " out of bounds (len=" & $s.len & ")")
  s.data[i]

proc `[]`*[T](s: var VSeq[T]; i: int): var T {.inline.} =
  when not defined(danger):
    if i < 0 or i >= s.len:
      raise newException(IndexDefect, "index " & $i & " out of bounds (len=" & $s.len & ")")
  s.data[i]

proc `[]=`*[T](s: var VSeq[T]; i: int; val: sink T) {.inline.} =
  when not defined(danger):
    if i < 0 or i >= s.len:
      raise newException(IndexDefect, "index " & $i & " out of bounds (len=" & $s.len & ")")
  s.data[i] = val

proc unsafeSet*(s: pointer; i: int; val: ptr byte) {.inline.} =
  let l = s.unsafeLen[]
  when not defined(danger):
    if i < 0 or i >= l:
      raise newException(IndexDefect, "index " & $i & " out of bounds (len=" & $l & ")")
  
  var data = cast[ptr UncheckedArray[byte]](s.unsafeData[])
  copyMem(addr data[i*s.unsafeStride[]], val, s.unsafeStride[])

proc `[]`*[T](s: VSeq[T]; i: BackwardsIndex): lent T {.inline.} =
  s[s.len - int(i)]

proc `[]`*[T](s: var VSeq[T]; i: BackwardsIndex): var T {.inline.} =
  s[s.len - int(i)]

proc `[]=`*[T](s: var VSeq[T]; i: BackwardsIndex; val: sink T) {.inline.} =
  s[s.len - int(i)] = val

# -----------------------------------------------------------------------------
# Mutation
# -----------------------------------------------------------------------------

proc add*[T](s: var VSeq[T]; val: sink T) =
  ## Append a single element.
  ensureCap(s, s.len + 1)
  s.data[s.len] = val
  inc s.len

proc unsafeAdd*(s: pointer; val: ptr byte) =
  ## Append a single element.
  let length = s.unsafeLen[]
  unsafeEnsureCap(s, length + 1)

  let stride = s.unsafeStride[]
  if stride > 0:
    let data = cast[ptr UncheckedArray[byte]](s.unsafeData[])
    copyMem(addr data[length * stride], val, stride)

  s.unsafeLen[] = length + 1

proc add*[T](s: var VSeq[T]; vals: openArray[T]) =
  ## Append multiple elements.
  if vals.len == 0: return
  ensureCap(s, s.len + vals.len)
  copyMem(cast[pointer](cast[int](s.data) + s.len * sizeof(T)),
          unsafeAddr vals[0], vals.len * sizeof(T))
  inc s.len, vals.len

proc setLen*[T](s: var VSeq[T]; newLen: int) =
  ## Resize the sequence. New slots are zeroed.
  if newLen < 0:
    raise newException(RangeDefect, "setLen negative")
  if newLen > s.len:
    ensureCap(s, newLen)
    zeroMem(cast[pointer](cast[int](s.data) + s.len * sizeof(T)),
            (newLen - s.len) * sizeof(T))
  elif newLen < s.len:
    for i in newLen..<s.len:
      `=destroy`(s.data[i])

  s.len = newLen

proc setCap*[T](s: var VSeq[T]; newCap: int) =
  ## Explicitly set capacity (may reallocate).
  if newCap < s.len:
    raise newException(RangeDefect, "setCap smaller than len")
  if newCap == s.cap:
    return
  let newData = cast[ptr UncheckedArray[T]](alloc(newCap * sizeof(T)))
  if s.len > 0:
    copyMem(newData, s.data, s.len * sizeof(T))
  zeroMem(cast[pointer](cast[int](newData) + s.len * sizeof(T)),
          (newCap - s.len) * sizeof(T))
  let oldData = s.data
  let oldCap = s.cap
  s.data = newData
  s.cap = newCap
  if oldData != nil:
    zeroMem(oldData, oldCap * sizeof(T))
    dealloc(oldData)

proc shrink*[T](s: var VSeq[T]; newCap: int) =
  ## Reduce capacity (must stay >= len).
  if newCap >= s.cap or newCap < s.len:
    return

  let newData = cast[ptr UncheckedArray[T]](alloc(newCap * sizeof(T)))
  if s.len > 0:
    copyMem(newData, s.data, s.len * sizeof(T))
  zeroMem(cast[pointer](cast[int](newData) + s.len * sizeof(T)),
          (newCap - s.len) * sizeof(T))
  let oldData = s.data
  let oldCap = s.cap
  s.data = newData
  s.cap = newCap
  zeroMem(oldData, oldCap * sizeof(T))
  dealloc(oldData)

proc insert*[T](s: var VSeq[T]; i: int; val: sink T) =
  ## Insert at index `i` (0 <= i <= len).
  if i < 0 or i > s.len:
    raise newException(IndexDefect, "insert index out of bounds")
  ensureCap(s, s.len + 1)
  if i < s.len:
    moveMem(cast[pointer](cast[int](s.data) + (i + 1) * sizeof(T)),
            cast[pointer](cast[int](s.data) + i * sizeof(T)),
            (s.len - i) * sizeof(T))
  s.data[i] = val
  inc s.len

proc delete*[T](s: var VSeq[T]; i: int) =
  ## Delete element at `i`, shifting subsequent elements down.
  if i < 0 or i >= s.len:
    raise newException(IndexDefect, "delete index out of bounds")
  if i < s.len - 1:
    `=destroy`(s.data[i])
    moveMem(cast[pointer](cast[int](s.data) + i * sizeof(T)),
            cast[pointer](cast[int](s.data) + (i + 1) * sizeof(T)),
            (s.len - 1 - i) * sizeof(T))

  dec s.len

proc del*[T](s: var VSeq[T]; i: int) =
  ## Delete element at `i` by swapping with the last element (O(1)).
  if i < 0 or i >= s.len:
    raise newException(IndexDefect, "del index out of bounds")
  if i != s.len - 1:
    copyMem(cast[pointer](cast[int](s.data) + i * sizeof(T)),
            cast[pointer](cast[int](s.data) + (s.len - 1) * sizeof(T)),
            sizeof(T))
    `=destroy`(s.data[s.len - 1])
  dec s.len

proc pop*[T](s: var VSeq[T]): T =
  ## Remove and return the last element.
  if s.len <= 0:
    raise newException(IndexDefect, "pop from empty VSeq")
  result = s.data[s.len - 1]
  `=destroy`(s.data[s.len - 1])
  dec s.len

  zeroMem(cast[pointer](cast[int](s.data) + s.len * sizeof(T)), sizeof(T))

proc clear*[T](s: var VSeq[T]) =
  ## Clear all elements (zero the entire buffer, keep capacity).
  if s.data != nil:
    for e in s.mitems:
      `=destroy`(e)
  
  s.len = 0

# -----------------------------------------------------------------------------
# Iterators
# -----------------------------------------------------------------------------

iterator items*[T](s: VSeq[T]): lent T =
  for i in 0 ..< s.len:
    yield s.data[i]

iterator mitems*[T](s: var VSeq[T]): var T =
  for i in 0 ..< s.len:
    yield s.data[i]

iterator pairs*[T](s: VSeq[T]): (int, lent T) =
  for i in 0 ..< s.len:
    yield (i, s.data[i])

iterator mpairs*[T](s: var VSeq[T]): (int, var T) =
  for i in 0 ..< s.len:
    yield (i, s.data[i])

# -----------------------------------------------------------------------------
# Queries / utilities
# -----------------------------------------------------------------------------

proc find*[T](s: VSeq[T]; val: T): int =
  ## Return index of `val` or -1.
  for i in 0 ..< s.len:
    if s.data[i] == val:
      return i
  return -1

proc contains*[T](s: VSeq[T]; val: T): bool {.inline.} =
  find(s, val) >= 0

proc `==`*[T](a, b: VSeq[T]): bool =
  if a.len != b.len: return false
  if a.len == 0: return true
  equalMem(a.data, b.data, a.len * sizeof(T))

proc `&`*[T](a, b: VSeq[T]): VSeq[T] =
  ## Concatenate two VSeqs.
  result = newVSeq[T](a.len + b.len)
  if a.len > 0:
    copyMem(result.data, a.data, a.len * sizeof(T))
  if b.len > 0:
    copyMem(cast[pointer](cast[int](result.data) + a.len * sizeof(T)),
            b.data, b.len * sizeof(T))
  result.len = a.len + b.len

proc toVSeq*[T](s: seq[T]): VSeq[T] =
  ## Convert a Nim seq to a VSeq.
  result = newVSeq[T](s.len)
  if s.len > 0:
    copyMem(result.data, unsafeAddr s[0], s.len * sizeof(T))
  result.len = s.len

proc toSeq*[T](s: VSeq[T]): seq[T] =
  ## Convert a VSeq to a Nim seq.
  result = newSeq[T](s.len)
  if s.len > 0:
    copyMem(addr result[0], s.data, s.len * sizeof(T))

proc toOpenArray*[T](s: VSeq[T]): openArray[T] =
  ## Borrow as an openArray.
  toOpenArray(s.data, 0, s.len - 1)

