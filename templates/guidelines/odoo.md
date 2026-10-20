# Odoo house rules (this deployment's guidelines for the coding agent)

You are customising a fork of **Odoo Community**. The branch you start from is an Odoo series
branch (e.g. `20.0`). These rules apply to every card unless the card says otherwise.

## Where code goes
- **New behaviour goes in a module under `custom_addons/`**, never as an edit to Odoo's own
  `addons/` or the `odoo/` framework. Extend existing models with `_inherit`, views with
  `inherit_id` + XPath, and Python methods with `super()`.
- **Do not modify other core modules** (`addons/*`, `odoo/addons/*`, `odoo/*`) unless the card
  names them explicitly. A change under `odoo/` is the framework: it is high-risk and always
  waits for a person.
- Module technical names are `snake_case` and prefixed for this organisation (`x_` by default),
  e.g. `custom_addons/x_hello/`.

## A module's shape
- `__init__.py`, `__manifest__.py` with at least `name`, `version`, `summary`, `author`, `depends`,
  `data`, `license` (`'LGPL-3'` unless the card says otherwise), `installable: True`, and
  `application: True` only for something with its own top-level menu.
- **`version` is `<series>.<major>.<minor>.<patch>`**, e.g. `20.0.1.0.0`. Bump it when you change
  data files or models of an existing module, so `-u` upgrades it.
- Models in `models/`, views in `views/` (one file per model), security in `security/`, data in
  `data/`, wizards in `wizard/`, controllers in `controllers/`, tests in `tests/`.
- **Every new model needs access rules**, in a CSV listed in the manifest's `data` (before the
  views). Which file depends on the series:
  - **20.0 and later**: `security/ir.access.csv` (model `ir.access`, which replaced both
    `ir.model.access` and `ir.rule`), header `id,name,model_id,group_id/id,operation,domain`.
    `model_id` is the model's technical name (`x_hello.greeting`), `operation` a subset of
    `crud` in that order (`r`, `cru`, `crud`, …), `domain` empty or a record-rule domain. There is
    no `ir.model.access.csv` and no `ir.rule` record on 20.0: a module that ships one does not load.
  - **Up to 19.0**: `security/ir.model.access.csv`, header
    `id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink`; record rules
    as `ir.rule` records in XML.
- Menus: a root `<menuitem>` for an application, actions as `ir.actions.act_window`. Use the
  view types of the series you are on (e.g. `<list>` since 18.0, not `<tree>`).
- Use the series' own APIs; check an existing core module in `addons/` for the current idiom
  before inventing one.

## Tests — the gate runs them
- Each module ships `tests/__init__.py` importing its `test_*.py` files; tests use
  `odoo.tests.TransactionCase` (or `HttpCase` for controllers/tours) and are tagged
  `@tagged('post_install', '-at_install')` when they need other modules installed.
- The factory's `validate` installs **only the modules you touched** into a fresh database and
  runs **their** tests (`--test-tags /<module>`). Code outside any addon also runs `base`'s tests,
  which takes a long time — another reason not to touch the framework.
- No demo data is loaded in tests: create the records a test needs in `setUpClass`.

## Data and upgrades
- XML ids are stable: do not rename them in a released module. Use `noupdate="1"` for data a user
  may edit afterwards.
- Never write migrations for core modules. A module's own migration scripts go in
  `migrations/<version>/` and only when the card asks for a data change.

## What not to do
- Do not commit generated files, `.pyc`, filestores or database dumps.
- Do not change `odoo-bin`, `requirements.txt`, `setup/` or CI files unless the card asks.
- Do not add Python dependencies that are not already in the Odoo image; if one is needed, say
  so on the card instead.
