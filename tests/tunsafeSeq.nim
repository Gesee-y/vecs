import unittest
include "../src/unsafeSeq.nim"


type
  A = object
    x: int

  B = object
    y: int
    a: ref A


proc addAndZero[T](s: var VSeq[T]; val: var T) =
  let source  = cast[ptr byte](addr val)
  let seqVar  = cast[pointer](addr s)
  seqVar.unsafeAdd(source, sizeof(T))
  zeroMem(source, sizeof(T))


suite "unsafeSeq - type-erased operations on VSeq internals":

  test "unsafeSeqLen reads seq len":
    var s = newVSeq[int](3)
    check unsafeSeqLen(addr s) == 3

  test "unsafeSeqCap reads seq capacity":
    var s = newVSeqOfCap[int](8)
    check unsafeSeqCap(addr s) >= 8

  test "unsafeSeqCap on empty seq is zero":
    var s: VSeq[int]
    check unsafeSeqCap(addr s) == 0

  test "unsafeSeqDataPtr matches address of first element":
    var s = newVSeq[int](3)
    let rawData = unsafeSeqDataPtr(addr s)
    check rawData == addr s[0]

  test "unsafeAdd appends a plain int":
    var s: VSeq[int]
    var value = 42
    let seqVar = cast[pointer](addr s)
    seqVar.unsafeAdd(cast[ptr byte](addr value), sizeof(int))

    check s.len == 1
    check s[0] == 42

  test "unsafeAdd triggers growth beyond initial capacity":
    var s = newVSeqOfCap[int](2)
    for i in 0 ..< 10:
      var value = i
      let seqVar = cast[pointer](addr s)
      seqVar.unsafeAdd(cast[ptr byte](addr value), sizeof(int))

    check s.len == 10
    for i in 0 ..< 10:
      check s[i] == i

  test "addAndZero: ref type - value readable after add":
    var refA: ref A = new A
    refA.x = 99

    var s: VSeq[ref A]
    s.addAndZero(refA)

    check s.len == 1
    check s[0] != nil
    check s[0].x == 99

  test "addAndZero: ref type - source is nil after add":
    var refA: ref A = new A
    refA.x = 7

    var s: VSeq[ref A]
    s.addAndZero(refA)

    check refA == nil

  test "addAndZero: ref type survives GC collect after source is gone":
    var s: VSeq[ref A]

    block:
      var refA: ref A = new A
      refA.x = 55
      s.addAndZero(refA)

    GC_fullCollect()

    check s[0] != nil
    check s[0].x == 55

  test "addAndZero: multiple refs all readable":
    var s: VSeq[ref A]

    for i in 0 ..< 5:
      var refA: ref A = new A
      refA.x = i * 10
      s.addAndZero(refA)

    check s.len == 5
    for i in 0 ..< 5:
      check s[i].x == i * 10

  test "addAndZero: growth preserves all refs":
    var s = newVSeqOfCap[ref A](1)

    for i in 0 ..< 8:
      var refA: ref A = new A
      refA.x = i * 3
      s.addAndZero(refA)

    check s.len == 8
    for i in 0 ..< 8:
      check s[i] != nil
      check s[i].x == i * 3

  test "addAndZero: object with ref field - field readable":
    var inner: ref A = new A
    inner.x = 77

    var b: B
    b.y = 9
    b.a = inner

    var s: VSeq[B]
    s.addAndZero(b)

    check s.len == 1
    check s[0].y == 9
    check s[0].a != nil
    check s[0].a.x == 77

  test "addAndZero: object with ref field - source zeroed":
    var inner: ref A = new A
    inner.x = 33

    var b: B
    b.y = 4
    b.a = inner

    var s: VSeq[B]
    s.addAndZero(b)

    check b.y == 0
    check b.a == nil

  test "addAndZero: object with ref field - growth preserves inner refs":
    var s = newVSeqOfCap[B](1)

    for i in 0 ..< 6:
      var inner: ref A = new A
      inner.x = i + 100
      var b: B
      b.y = i
      b.a = inner
      s.addAndZero(b)

    check s.len == 6
    for i in 0 ..< 6:
      check s[i].a != nil
      check s[i].a.x == i + 100
