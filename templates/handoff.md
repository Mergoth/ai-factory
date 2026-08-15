# Handoff: <slug>

Spec: `specs/<slug>.md`
Created: <timestamp>

## Goal

One paragraph. What is true when this is done.

Difficulty: mechanical | normal | tricky
<!-- mechanical = rename, small patch, few files
     normal     = a feature with tests
     tricky     = subtle logic, concurrency, wide refactor
     /factory-build maps this to a model from `agy models`. No model ids here,
     they rotate. -->


## Files to touch

- `path/to/file.py` - what changes here
- `path/to/new_file.py` - NEW, what it is for

## Tests to run

```
<TEST_CMD from factory.env>
```

Must pass:
- `test_name_one`
- `test_name_two`

## Done criteria

- [ ] checkable statement one
- [ ] checkable statement two
- [ ] tests above pass

---

<!-- factory-check appends "## Check <timestamp>" blocks below this line -->
