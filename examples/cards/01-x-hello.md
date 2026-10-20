<!-- A first card. Paste the title and body into the panel's "new card" form (Board), or run:
     of-odoo of act card_create -p odoo -P title="Add a custom module x_hello" -P body="$(sed -n '/^## Objective/,$p' examples/cards/01-x-hello.md)"
     of-odoo of act card_move -p odoo -i 1 -P column=TO-DO -->
# Add a custom module x_hello

## Objective
A first custom module, so we can see the factory floor working end to end: a "Hello" app with
one model and a menu.

## Scope
- New module `custom_addons/x_hello` (Odoo 20.0, version `20.0.1.0.0`, license LGPL-3,
  depends on `base`), installable and an application.
- Model `x_hello.greeting` with fields `name` (Char, required) and `message` (Text), and a
  computed Char `display_message` = "Hello, <name>!" when `message` is empty, else `message`.
- List and form views, a window action and a top-level menu "Hello" › "Greetings".
- Access rules: internal users (`base.group_user`) may read, write, create and unlink.

## Acceptance criteria
- `x_hello` installs on a fresh database without warnings about missing access rules.
- The menu Hello › Greetings opens the list of greetings, and a greeting can be created from it.
- `display_message` returns "Hello, Ada!" for name "Ada" with no message, and the message
  otherwise.
- Tests in `custom_addons/x_hello/tests/` cover the computed field; the factory's validate runs
  them and they pass.

## Out of scope
- Any change to Odoo's own modules or framework.
