import unittest
include "../src/unsafeSeq.nim"


type
  A = object
    x: int

  B = object
    y: int
    a: ref A


proc addAndZero[T](v: var VSeq[T], val: var T) =
  let source = cast[ptr byte](addr val)
  let sequence = cast[pointer](addr v)
  sequence.unsafeAdd(source, sizeof(T))
  zeroMem(source, sizeof(T))


suite "VSeq with ref types - addAndZero safety":

  test "ref type: value is readable after addAndZero":
    var refA: ref A = new A
    refA.x = 42

    var sequence = newVSeqOfCap[ref A](4)
    sequence.addAndZero(refA)

    check refA.isNil
    check sequence.len == 1
    check sequence[0].x == 42

  test "ref type: ref declared in block survive, even after GC collect":
    var sequence = newVSeqOfCap[ref A](4)
      
    block:
      var refA: ref A = new A
      refA.x = 99
      sequence.addAndZero(refA)

    GC_fullCollect()

    check sequence[0] != nil
    check sequence[0].x == 99

  test "ref type: multiple adds keep all refs readable":
    var sequence = newVSeqOfCap[ref A](2)

    for i in 0 ..< 5:
      var refA: ref A = new A
      refA.x = i * 10
      sequence.addAndZero(refA)

    check sequence.len == 5
    for i in 0 ..< 5:
      check sequence[i].x == i * 10

  test "ref type: reallocation preserves ref validity":
    var sequence = newVSeqOfCap[ref A](1)

    var refA: ref A = new A
    refA.x = 7
    sequence.addAndZero(refA)

    var refB: ref A = new A
    refB.x = 13
    sequence.addAndZero(refB)

    check sequence.len == 2
    check sequence[0].x == 7
    check sequence[1].x == 13

  test "object with ref field: field is readable after addAndZero":
    var inner: ref A = new A
    inner.x = 55

    var b: B
    b.y = 1
    b.a = inner

    var sequence = newVSeqOfCap[B](4)
    sequence.addAndZero(b)

    check sequence.len == 1
    check sequence[0].y == 1
    check sequence[0].a != nil
    check sequence[0].a.x == 55

  test "object with ref field: sink copy is zeroed, stored object stays valid after addAndZero":
    var inner: ref A = new A
    inner.x = 88

    var b: B
    b.y = 3
    b.a = inner

    var sequence = newVSeqOfCap[B](4)
    sequence.addAndZero(b)

    # The sink parameter is a local copy: zeroing it does not modify the caller's binding.
    # The stored object in the VSeq must be intact.
    check sequence[0].y == 3
    check sequence[0].a != nil
    check sequence[0].a.x == 88

  test "object with ref field: multiple adds keep all inner refs readable":
    var sequence = newVSeqOfCap[B](2)

    for i in 0 ..< 4:
      var inner: ref A = new A
      inner.x = i + 100
      var b: B
      b.y = i
      b.a = inner
      sequence.addAndZero(b)

    check sequence.len == 4
    for i in 0 ..< 4:
      check sequence[i].y == i
      check sequence[i].a != nil
      check sequence[i].a.x == i + 100

  test "object with ref field: reallocation preserves inner ref validity":
    var sequence = newVSeqOfCap[B](1)

    for i in 0 ..< 8:
      var inner: ref A = new A
      inner.x = i * 3
      var b: B
      b.y = i
      b.a = inner
      sequence.addAndZero(b)

    check sequence.len == 8
    for i in 0 ..< 8:
      check sequence[i].a != nil
      check sequence[i].a.x == i * 3

  test "ref type: pop does not segfault and returns valid ref":
    var refA: ref A = new A
    refA.x = 21

    var sequence = newVSeqOfCap[ref A](4)
    sequence.addAndZero(refA)

    let popped = sequence.pop()
    check sequence.len == 0
    check popped != nil
    check popped.x == 21

  test "ref type: delete does not segfault":
    var sequence = newVSeqOfCap[ref A](4)

    for i in 0 ..< 3:
      var refA: ref A = new A
      refA.x = i
      sequence.addAndZero(refA)

    sequence.delete(1)

    check sequence.len == 2
    check sequence[0].x == 0
    check sequence[1].x == 2

  test "object with ref field: clear does not segfault":
    var sequence = newVSeqOfCap[B](4)

    for i in 0 ..< 3:
      var inner: ref A = new A
      inner.x = i
      var b: B
      b.y = i
      b.a = inner
      sequence.addAndZero(b)

    sequence.clear()
    check sequence.len == 0

  test "ref type: del (swap-delete) does not segfault":
    var sequence = newVSeqOfCap[ref A](4)

    for i in 0 ..< 4:
      var refA: ref A = (new A)
      refA.x = i * 5
      sequence.addAndZero(refA)

    sequence.del(1)

    check sequence.len == 3
    check sequence[0].x == 0
    check sequence[2].x == 10

  test "object with ref field: copy preserves inner ref access":
    var inner: ref A = new A
    inner.x = 77

    var b: B
    b.y = 9
    b.a = inner

    var sequence = newVSeqOfCap[B](4)
    sequence.addAndZero(b)

    let copy = sequence
    check copy[0].a != nil
    check copy[0].a.x == 77
