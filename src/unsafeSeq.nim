## unsafeSeq - Type-erased unsafe access to Nim's built-in seq internals.
##
## Nim's seq[T] (NimSeqV2[T]) layout in memory:
##
##   seq variable  (on stack / in struct):
##     [0]              len : int
##     [sizeof(int)]    p   : pointer  →  heap payload
##
##   heap payload  (NimSeqPayload[T]):
##     [0]              cap  : int
##     [sizeof(int)]    data : UncheckedArray[T]   (assumes elemAlign <= sizeof(int))
##
## All procs below operate on a `pointer` to the seq variable itself,
## enabling archetype / ECS code to manipulate seqs without knowing T.
##
## Assumes element alignment <= sizeof(int) (true for all ECS component types).

# -----------------------------------------------------------------------------
# Internal layout accessors (not exported)
# -----------------------------------------------------------------------------

type
  VSeqPayload[T] = object
    cap: int
    data: UncheckedArray[T]

  VSeq*[T] = object
    len: int
    payload: ptr VSeqPayload[T]

const CHECKS_ENABLED = not defined(danger)

proc seqLenPtr*(seqVar: pointer): ptr int {.inline.} =
  cast[ptr int](seqVar)

proc seqPayloadPtr(seqVar: pointer): ptr pointer {.inline.} =
  cast[ptr pointer](cast[int](seqVar) + sizeof(int))

proc payloadCapPtr(payload: pointer): ptr int {.inline.} =
  cast[ptr int](payload)

proc payloadDataPtr(payload: pointer): pointer {.inline.} =
  cast[pointer](cast[int](payload) + sizeof(int))

# -----------------------------------------------------------------------------
# Public unsafe accessors
# -----------------------------------------------------------------------------

proc unsafeSeqLen*(seqVar: pointer): int {.inline.} =
  ## Current element count of the seq at `seqVar`.
  seqLenPtr(seqVar)[]

proc unsafeSeqCap*(seqVar: pointer): int {.inline.} =
  ## Current capacity of the seq at `seqVar`.
  let payload = seqPayloadPtr(seqVar)[]
  if payload == nil: 0
  else: payloadCapPtr(payload)[]

proc unsafeSeqDataPtr*(seqVar: pointer): pointer {.inline.} =
  ## Raw pointer to the first element of the seq data buffer.
  ## Returns nil if the seq has no allocated payload.
  let payload = seqPayloadPtr(seqVar)[]
  if payload == nil: nil
  else: payloadDataPtr(payload)

# -----------------------------------------------------------------------------
# Growth helpers
# -----------------------------------------------------------------------------

proc nextCap(current: int): int {.inline.} =
  if current == 0: 4 else: current * 2

proc growPayload*(seqVar: pointer; stride: int; minCap: int) =
  let payloadPtrLoc = seqPayloadPtr(seqVar)
  let oldPayload    = payloadPtrLoc[]
  let oldCap        = if oldPayload == nil: 0 else: payloadCapPtr(oldPayload)[]

  var newCap = nextCap(oldCap)
  if newCap < minCap:
    newCap = minCap

  let headerSize = sizeof(int)
  let newPayload = alloc0(headerSize + newCap * stride)
  payloadCapPtr(newPayload)[] = newCap

  let currentLen = seqLenPtr(seqVar)[]
  if currentLen > 0 and oldPayload != nil:
    copyMem(payloadDataPtr(newPayload), payloadDataPtr(oldPayload), currentLen * stride)

  if oldPayload != nil:
    dealloc(oldPayload)

  payloadPtrLoc[] = newPayload

template unsafeSet*(s: pointer, i: untyped, v: ptr byte, stride: int) =
  var data = unsafeSeqDataPtr(s)
  copyMem(cast[pointer](cast[int](data) + i * stride), v, stride)

template unsafeGet*(s: pointer, i: untyped, stride: int): ptr byte =
  var data = unsafeSeqDataPtr(s)
  cast[ptr byte](cast[int](data) + i * stride)


# -----------------------------------------------------------------------------
# Core operation
# -----------------------------------------------------------------------------

proc unsafeAdd*(seqVar: pointer; val: ptr byte; stride: int) =
  ## Append `stride` bytes from `val` to the seq at `seqVar`.
  ##
  ## This bypasses ARC/ORC: no destructor is called on existing elements,
  ## no ref-count is adjusted. Safe only when `T` is a plain-old-data type
  ## or when the caller manages lifetimes explicitly (e.g. via zeroMem).
  let length = seqLenPtr(seqVar)[]
  let cap    = unsafeSeqCap(seqVar)

  if length >= cap:
    growPayload(seqVar, stride, length + 1)

  let data = unsafeSeqDataPtr(seqVar)
  copyMem(cast[pointer](cast[int](data) + length * stride), val, stride)
  seqLenPtr(seqVar)[] = length + 1

# -------------------------------------------------------------------------------
# Safe API
# -------------------------------------------------------------------------------

proc ensureCap[T](s: var VSeq[T], len: int) =
  let header = sizeof(int)
  if s.payload == nil: 
    s.payload = cast[ptr VSeqPayload[T]](alloc0(header + len*sizeof(T)))
    s.payload.cap = len
  if s.payload.cap < len:
    let newCap = len*2
    let newData = realloc0(s.payload, header + s.payload.cap * sizeof(T), header + newCap * sizeof(T))

    assert newData != nil, "Insufficient memory to grow VSeq."
    s.payload = cast[ptr VSeqPayload[T]](newData)
    s.payload.cap = newCap

proc newVSeqOfCap*[T](cap: int = 0): VSeq[T] =
  result = VSeq[T](len: 0)
  if cap > 0:
    ensureCap(result, cap)


proc newVSeq*[T](len: int = 0): VSeq[T] =
  result = VSeq[T](len: len)
  if len > 0:
    ensureCap(result, len)

proc len*[T](s: VSeq[T]): int = s.len

proc `[]`*[T](s: VSeq[T], i: int): lent T {.inline.} =
  when CHECKS_ENABLED: assert i >= 0 and i < s.len, "Access out of bound"
  s.payload.data[i]

proc `[]`*[T](s: var VSeq[T], i: int): var T {.inline.} =
  when CHECKS_ENABLED: assert i >= 0 and i < s.len, "Access out of bound"
  s.payload.data[i]

proc `[]`*[T](s: VSeq[T], i: BackwardsIndex): lent T {.inline.} =
  s[s.len - i.int]

proc `[]`*[T](s: var VSeq[T], i: BackwardsIndex): var T {.inline.} =
  s[s.len - i.int]

proc `[]=`*[T](s: var VSeq[T], i: int, v: sink T) {.inline.} =
  when CHECKS_ENABLED: assert i >= 0 and i < s.len, "Access out of bound"
  s.payload.data[i] = v

proc `[]=`*[T](s: var VSeq[T], i: BackwardsIndex, v: sink T) {.inline.} =
  s[s.len - i.int] = v

proc shrink*[T](s: var VSeq[T], newLen: int) =
  assert newLen <= s.len, "Can't shrink to greater than the sequences length"
  for i in newLen..<s.len:
    s[i].reset()

  s.len = newLen

proc grow*[T](s: var VSeq[T], newLen: int) = 
  assert newLen >= s.len, "Can't grow to lesser than the sequence length"
  ensureCap(s, newLen)
  s.len = newLen

proc setLen*[T](s: var VSeq[T], newLen: int) =
  if s.len < newLen:
    grow(s, newLen)
  else:
    shrink(s, newLen)

proc unsafeAddAndZero*(v: pointer, source: ptr byte, stride: int) =
  v.unsafeAdd(source, stride)
  zeroMem(source, stride)

proc unsafeSetAndZero*(v: pointer, i: int, source: ptr byte, stride: int) =
  v.unsafeSet(i, source, stride)
  zeroMem(source, stride)

proc add*[T](s: var VSeq[T], v: T) =
  s.grow(s.len+1)
  s[s.len-1] = v

proc add*[T](s: var VSeq[T], v: openArray[T]) =
  let oldLen = s.len
  s.grow(oldLen + v.len)

  for i in oldLen..<s.len:
    s[i] = v[i - oldLen]

proc `&`*[T](s1, s2: VSeq[T]): VSeq[T] =
  result = newVSeq[T](s1.len + s2.len)
  for i in 0..<s1.len:
    result[i] = s1[i]

  for i in 0..<s2.len:
    result[s1.len + i] = s2[i]

proc pop*[T](s: var VSeq[T]): T =
  when CHECKS_ENABLED: assert s.len > 0, "Can't pop on empty VSeq."
  result = s[^1]
  s[^1] = default(T)
  dec s.len

proc delete*[T](s: var VSeq[T], i: int) =
  when CHECKS_ENABLED: assert i >= 0 and i < s.len, "Access out of bound"
  for i in i..<s.len-1:
    s[i] = s[i+1]

  s[^1] = default(T)
  dec s.len

proc insert*[T](s: var VSeq[T], i: int, v: T) =
  when CHECKS_ENABLED: assert i >= 0 and i < s.len, "Access out of bound"
  s.grow(s.len+1)
  for i in countdown(s.len-1, i+1):
    s[i] = s[i-1]
  s[i] = v


proc del*[T](s: var VSeq[T], i: int) =
  when CHECKS_ENABLED: assert i >= 0 and i < s.len, "Access out of bound"
  s[i] = s[^1]
  s[^1] = default(T)
  s.shrink(s.len-1)

proc toSeq*[T](s: VSeq[T]): seq[T] =
  result = newSeq[T](s.len)
  for i in 0..<s.len:
    result[i] = s[i]

proc toVSeq*[T](s: seq[T]): VSeq[T] =
  result = newVSeq[T](s.len)
  for i in 0..<s.len:
    result[i] = s[i]

proc clear*[T](s: var VSeq[T]) = 
  s.setLen(0)

iterator items*[T](s: VSeq[T]): T =
  for i in 0..<s.len:
    yield s[i]

iterator mitems*[T](s: var VSeq[T]): var T =
  for i in 0..<s.len:
    yield s[i]

iterator pairs*[T](s: VSeq[T]): (int, T) =
  for i in 0..<s.len:
    yield (i, s[i])

iterator mpairs*[T](s: var VSeq[T]): (int, T) =
  for i in 0..<s.len:
    yield (i, s[i])
  
template destroy[T](s: var VSeq[T]) =
  if s.payload != nil:
    for i in 0..<s.len:
      s[i].reset()

    s.payload.dealloc()
    s.payload = nil

  s.len = 0

proc `=destroy`*[T](s: var VSeq[T]) =
  destroy(s)

proc `=sink`*[T](dest: var VSeq[T]; src: VSeq[T]) =
  if dest.payload != src.payload:
    destroy(dest)
  
  dest.payload = src.payload
  dest.len = src.len

proc `=copy`*[T](dest: var VSeq[T]; src: VSeq[T]) =
  if src.payload == dest.payload:
    return
  if src.payload == nil:
    destroy(dest)
  else:
    let newCap = src.payload.cap

    dest.setLen(src.len)
    for i in 0..<src.len:
      dest[i] = src[i]
    
proc `=dup`*[T](src: VSeq[T]): VSeq[T] =
  if src.payload != nil:
    result = newVSeqOfCap[T](src.payload.cap)
    result.setLen(src.len)
    for i in 0..<src.len:
      result[i] = src[i]