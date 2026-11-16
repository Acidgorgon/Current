# Studio plugin

The Current plugin lets you write schemas and generate the networking modules inside Roblox Studio, without the CLI or any external tools. It uses the same compiler, so schemas behave exactly as on the command line.

Install it by downloading `current-plugin.rbxm` from [GitHub Releases](https://github.com/Acidgorgon/Current/releases) into your Studio plugins folder (see [Installation](/guide/installation#studio-plugin)).

::: info Screenshots
The screenshots below come from upstream Blink's plugin, which Current's is built from. The layout is identical; the toolbar and window say **Current** instead of Blink.
:::

## Opening the editor

Open the **Plugins** tab and press **Editor** in the **Current** toolbar. The first time you generate, Studio asks the plugin for permission to inject scripts: allow it, because that is how the generated modules are created.

![The plugin in the Plugins tab](/plugin/Locate.png)

## Editor

The editor is the centre of the plugin. It highlights the schema language, completes keywords, types and fields, closes brackets, indents, and underlines mistakes as you type.

![The editor](/plugin/Editor.png)

The **Import** button at the top loads a `.blink`, `.current` or `.txt` file from your computer into the editor.

## Managing files

Open the side menu with the menu button on the left:

![Opening the side menu](/plugin/Menu.png)

It lists your saved schemas, each with buttons to edit, generate and delete it:

![The file list](/plugin/Navigation.png)

### Saving

Press the save button at the bottom of the side menu and enter a name. Entering the name of an existing file overwrites it.

![Saving a file](/plugin/Save.png)

Schemas are saved in the place itself, as `StringValue`s in `ServerStorage.BLINK_CONFIGURATION_FILES` (the same folder Blink's plugin uses, so your existing schemas carry over). They are saved with the place and shared with everyone working in it.

## Generating

Press **Generate** on a file, then select where the modules should go in the Explorer:

![Choosing where to generate](/plugin/Generate.png)

::: warning
Pick a place that both the server and clients can reach, such as `ReplicatedStorage`. Otherwise one side can't require its module.
:::

Press **Generate** again to confirm:

![Confirming the destination](/plugin/GenerateSelected.png)

The plugin creates (or replaces the contents of) a folder named `Current` there, containing three modules: `Server`, `Client` and `Types`.

![The generated folder](/plugin/Output.png)

The `ServerOutput`, `ClientOutput` and `TypesOutput` options are not needed in the plugin and are ignored. All other [options](./options) apply.

## Errors

When a schema has errors, generating stops and the plugin shows what is wrong and where:

![An error in the plugin](/plugin/Error.png)

## Imports in Studio

[`import`](./schema#imports) works in the plugin too, but only for sibling files: `import "./Common"` imports the saved file named `Common`.
