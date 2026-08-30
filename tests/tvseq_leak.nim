import unittest
include "../src/vseq.nim"


type
  Tracked = object
    id: int

var destroyed = 0

proc `=destroy`(t: var Tracked) =
  inc destroyed

proc newTracked(id: int): ref Tracked =
  result = new Tracked
  result.id = id


suite "VSeq leaks stored refs":

  setup:
    destroyed = 0

  test "control: a plain seq destroys the refs it owns":
    block:
      var s = newSeqOfCap[ref Tracked](4)
      for i in 0 ..< 3:
        s.add(newTracked(i))
      check destroyed == 0

    check destroyed == 3

  test "destroying a VSeq never destroys its elements":
    block:
      var s = newVSeqOfCap[ref Tracked](4)
      for i in 0 ..< 3:
        s.add(newTracked(i))
      check destroyed == 0

    check destroyed == 3

  test "clear drops every ref without destroying it":
    var s = newVSeqOfCap[ref Tracked](4)
    for i in 0 ..< 3:
      s.add(newTracked(i))

    s.clear()
    check destroyed == 3

  test "delete leaks the removed element":
    var s = newVSeqOfCap[ref Tracked](4)
    for i in 0 ..< 3:
      s.add(newTracked(i))

    s.delete(1)
    check destroyed == 1

  test "del leaks the element it overwrites":
    var s = newVSeqOfCap[ref Tracked](4)
    for i in 0 ..< 3:
      s.add(newTracked(i))

    s.del(0)
    check destroyed == 1

  test "setLen shrink leaks the truncated elements":
    var s = newVSeqOfCap[ref Tracked](4)
    for i in 0 ..< 3:
      s.add(newTracked(i))

    s.setLen(1)
    check destroyed == 2

  test "copy duplicates ownership without increfing":
    block:
      var original = newVSeqOfCap[ref Tracked](4)
      original.add(newTracked(1))
      var duplicate = original
      check duplicate[0].id == 1

    check destroyed == 1

  test "pop leaves the popped object alive forever":
    var s = newVSeqOfCap[ref Tracked](4)
    s.add(newTracked(7))

    block:
      let popped = s.pop()
      check popped.id == 7

    check destroyed == 1