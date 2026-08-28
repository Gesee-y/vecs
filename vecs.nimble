packageName   = "vecs"
version       = "0.0.1"
author        = "Row"
description   = "Vexel's ECS"
license       = "MIT"

srcDir        = "src"
binDir        = "bin"
skipFiles     = @[]

requires "nim >= 2.0.0"
requires "cborious"

task test, "Run the test suite":
  exec "nim r tests/timmediate.nim"
  exec "nim r tests/tdeferred.nim"
  exec "nim r tests/tafter.nim"
  exec "nim r tests/tqueries.nim"
  exec "nim r tests/tid.nim"
  exec "nim r tests/tecsseq.nim"
  exec "nim r tests/tcomponents.nim"
  exec "nim r tests/tevents.nim"
  exec "nim r -d:ArchetypeWords=2 tests/tmanycomponents.nim 2>&1"
  exec "nim r tests/torder.nim"
  exec "nim r tests/tsnapshots.nim"
  exec "nim r tests/taddworld.nim"
  exec "nim r tests/serialization/tsimpletext.nim"
  exec "nim r tests/serialization/tsimplebinary.nim"
  exec "nim r tests/serialization/tcompositetext.nim"
  exec "nim r tests/serialization/tcompositebinary.nim"

task docs, "Generate documentation":
  exec "nim doc --project --git.url:git@github.com:RowDaBoat/vecs.git --index:on --outdir:docs src/vecs.nim"
