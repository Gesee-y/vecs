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

proc seqLenPtr(seqVar: pointer): ptr int {.inline.} =
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

proc growPayload(seqVar: pointer; stride: int; minCap: int) =
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
