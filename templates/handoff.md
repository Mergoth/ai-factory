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

<!-- each one runs the code where it can. a grep checks spelling, not behaviour.
     ask what a truncated or literal-minded run could do to tick this box
     without doing the work - see PRINCIPLES #13. -->

- [ ] checkable statement one
- [ ] checkable statement two
- [ ] tests above pass

## Environment limits

<!-- what cannot be verified on this machine: no docker daemon, no network, no
     credentials. write the artefact, do not claim it works, list it under
     "not covered" in the walkthrough. delete this section if there are none. -->

- thing that cannot be verified here, and what to do instead

---

<!-- factory-check appends "## Check <timestamp>" blocks below this line -->
