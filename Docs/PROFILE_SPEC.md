# Devigator Profile Specification 1.2

Devigator profiles are portable UTF-8 JSON documents containing shortcut information for one or more applications. The canonical filename suffix is `.devigator.json`; the media type reserved for integrations is `application/vnd.devigator.profile+json`.

The normative JSON Schema is [`Schemas/devigator-profile.schema.json`](../Schemas/devigator-profile.schema.json). A minimal profile looks like this:

```json
{
  "schemaVersion": "1.2",
  "profiles": [
    {
      "id": "com.example.editor",
      "name": "Example Editor",
      "application": {
        "bundleIdentifiers": ["com.example.editor"],
        "bundleIdentifierPatterns": [],
        "applicationNames": ["Example Editor"]
      },
      "metadata": {
        "version": "1.0.0",
        "author": "Example Inc."
      },
      "groups": [
        {
          "id": "navigation",
          "title": "Code Navigation",
          "categoryID": "code.navigation.symbol",
          "shortcuts": [
            {
              "id": "go-to-definition",
              "action": "Go to Definition",
              "capabilityID": "code.definition",
              "keys": ["F12"],
              "pointerGestures": [
                {"modifiers": ["⌘"], "button": "primary", "clickCount": 1}
              ],
              "commandID": "editor.action.revealDefinition",
              "tags": ["navigation"]
            }
          ]
        }
      ]
    }
  ]
}
```

## Discovery and ownership

Devigator reads profiles below `~/Library/Application Support/Devigator/Profiles`:

```text
Profiles/
├── Providers/   # Files owned and atomically updated by IDE plugins or vendors
└── User/        # Files created, imported, or edited by the user
```

Provider integrations should use a reverse-DNS subdirectory, for example `Providers/com.example.editor/default.devigator.json`. Write updates to a temporary file in the same directory and atomically rename it over the target. A provider must not write to `User/`.

Resolution order is built-in profiles, provider profiles, then user profiles. A profile with the same `id` replaces the lower-level profile. If multiple different profiles match one application, Devigator compares source level, exact Bundle ID versus glob/name match, optional `priority`, and matcher specificity.

## Stable identifiers

- `profile.id` should be a stable reverse-DNS identifier and must not contain a version number.
- `group.id` and `shortcut.id` must be unique within a profile and remain stable across translations.
- `categoryID` identifies an editor-independent group from the capability catalog, such as `code.navigation.symbol` or `navigation.history`.
- `capabilityID` identifies the general meaning of an action, such as `code.definition`, independently from an IDE's wording.
- `commandID` should contain the IDE's stable internal action identifier. It allows a future provider to synchronize the user's live keymap without translating display names.
- `keys` is an ordered display representation, not a machine-level key event encoding.
- `pointerGestures` lists alternate mouse or trackpad gestures for the same action. `modifiers` uses the same display tokens as `keys`; `button` is `primary`, `secondary`, or `middle`; and `clickCount` is 1–3.
- `when` is reserved for provider context expressions. Devigator 1.x preserves it but does not evaluate it.

## Compatibility

Devigator accepts profile schema 1.0, 1.1, and 1.2. Version 1.1 adds optional `categoryID` and `capabilityID`; version 1.2 adds optional `pointerGestures`. The existing `title`, `action`, and `keys` remain required fallbacks for older consumers and unknown extensions. Consumers must reject unsupported schema versions. Profile content versions belong in `metadata.version` and are independent from `schemaVersion`.

## Capability catalog and localization

The capability catalog separates general concepts from editor-specific commands. Its normative schema is [`Schemas/devigator-capability-catalog.schema.json`](../Schemas/devigator-capability-catalog.schema.json), and the built-in English/Korean catalog is [`CapabilityCatalog.json`](../Sources/Devigator/Resources/CapabilityCatalog.json).

```text
capabilityID: code.definition          # General meaning
categoryID:   code.navigation.symbol   # General grouping
commandID:    editor.action.revealDefinition  # IDE-specific command
keys:         ["F12"]                  # User-facing binding
pointerGestures:                         # Alternate pointer binding
  - modifiers: ["⌘"]
    button: primary
    clickCount: 1
```

Catalog `labels` and `descriptions` are maps keyed by BCP 47 language code. The standard catalog requires `en` and `ko`; additional locales can be added without changing profile files. Devigator selects Korean for a Korean macOS locale and English otherwise. If a capability is unknown, it displays the profile's `action` or `title` fallback.
