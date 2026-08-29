import ../src/vecs

type
  A = object
    value: int
  B = object
    value: int

var world = World()
# First, add an entity with A
let ab = world.add((A(value: 1),), Immediate)
echo "After add A(1): A value = ", world.read(ab, A).value

# Now add B to it - this triggers moveAdding
world.add(ab, B(value: 2), Immediate)
echo "After add B(2): A value = ", world.read(ab, A).value
echo "After add B(2): B value = ", world.read(ab, B).value
