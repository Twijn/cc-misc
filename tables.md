# tables

A utility module for table operations in ComputerCraft providing common table manipulation functions like searching, counting, copying, and comparison operations. Features: Element existence checking with includes(), table size counting for any table type, deep recursive copying with nested table support, deep recursive equality comparison, and works with both array-like and associative tables.

## Functions

### `module.includes(table, object)`

Check if a table contains a specific value

**Parameters:**

- `table` (table): The table to search in
- `object` (any): The value to search for

**Returns:** boolean # True if the object is found in the table

### `module.count(table)`

Count the number of elements in a table (works with both arrays and associative tables)

**Parameters:**

- `table` (table): The table to count elements in

**Returns:** number # The number of key-value pairs in the table

### `module.recursiveCopy(table)`

Create a deep copy of a table, recursively copying all nested tables

**Parameters:**

- `table` (table): The table to copy

**Returns:** table # A new table with all values copied (nested tables are also copied)

### `module.recursiveEquals(t1, t2)`

Compare two tables for deep equality, recursively checking nested tables

**Parameters:**

- `t1` (table): The first table to compare
- `t2` (table): The second table to compare

**Returns:** boolean # True if both tables have the same structure and values

