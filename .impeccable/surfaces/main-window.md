# Surface: main window

Mode: Operate. The user adds torrents, watches them, and manages what downloads or seeds.

## Direction contract

Revision 4 (2026-11-23): the user found the monochrome build bland and chose the "LED pair" from three colour options. Revision 3's world stays; colour widens as below.

LED colours (each means one thing; shape still tells direction, so colour is never the only cue):
- Orange (Signal): bytes coming in. Download dots, digits, speeds, the tray's leading edge.
- Green (Growth): bytes going out. Upload rings, upload speed and figure, a ring column that walks a seeding tray, the finish bloom, the ratio ≥ 1 leaf.
- Amber (Caution): waiting, queued, checking, allocating, moving. State icons only.
- Red (Fault): errors, always with a word.
- Ink: everything else, all text, controls and selection.
Rules: a state icon keeps its state colour; dots and digits colour only while bytes move. When both directions move, orange wins the figure. Sidebar filter icons light only while true right now (Downloading while something fetches, Seeding while something uploads, Errors while any exist). Selected rows drop every LED colour for ink.

Delight (one focal moment, rest quiet): a download crossing 100% plays the bloom, a green sweep through its tray, and its figure reads DONE for 4 s. The Dock tile grows the icon's seedling with overall progress while Sprout downloads, tip orange, flowering green on a finish; seeding or idle shows the normal icon. A just-finished torrent stays in the Downloading list 4 s so its bloom is seen. Easter eggs: click the empty-state sprout to grow it until it flowers (its orange petals are the one decorative use of orange, allowed because the app icon's orange dot already names new growth); triple-click the pulse graph to scroll SPROUT through it. Haptics only for direct actions (drop, Alternative Speeds toggle, the sprout easter egg).
Motion: Animatable canvases, frames run only during a change; Reduce Motion skips sweeps and scrolls, colour changes still show.

Revision 3 (superseded on colour only):

Revision 3 (2026-11-17). Revision 1 (system grey + accent + table) was rejected as generic; revision 2 (earthy "Germination" palette) as "okayish but meh". The user asked for online references first and chose this direction from three.

Craft bar (references the user saw): Nothing OS dot-matrix UI and Ndot type; Teenage Engineering screens; Flighty (one huge fact per item); Tide Guide and (Not Boring) Weather (data shape and oversized numerals as hero).

THESIS: A torrent is thousands of pieces, so the whole interface is a dot matrix: progress, speed, history and even the numbers are drawn from the same dots. Refuses the category default of a table with thin progress bars, and the generic dashboard of cards.

OWN-WORLD: Dot matrix. Monochrome: lit dots in ink (white on a black ground in dark mode, near-black on neutral paper in light mode), unlit dots faintly visible like an LED panel. One signal colour, International Orange, means exactly one thing: data moving right now. Direction is told by shape, not colour: download dots are solid, upload dots are rings. System red only for errors, always with a word. Controls and selection use ink, never orange. Type: SF Pro for names and labels; every headline number is dot-matrix digits drawn from the dot grid (5×7 glyphs). Native window chrome, Liquid Glass toolbar, sidebar and inspector stay standard.

STORY: The user glances, sees orange where something is moving and how much is left, and reads one big number per torrent.

FIRST VIEWPORT: Sidebar of state filters with counts, monochrome icons. Content: a pulse band with the current download speed as large dot-matrix digits, upload as ring-dot digits, and a scrolling dot graph of the last minute (solid orange dots rise for download, rings hang below the baseline for upload). Below it, one row per torrent: name, a two-row dot tray of its progress, a quiet status line, and its percentage as large dot-matrix digits on the right. Inspector: a giant dot-matrix percentage, then the exact piece field as dots, then details. Sort in a toolbar menu; Add in the toolbar, ⌘O, drop and magnet links.

FORM: Seed tray thesis kept from the roll (candidate 6 of 7); world replaced at the user's direction. SEED REFERENCE: seed:292043893e28c466.

SIGNATURE: The numbers are made of the same dots as the data. One grid, one dot, everywhere.

Rules:
- Orange only while bytes are moving; never decorative, never for selection or chrome.
- Dots on a strict grid, never smoothed into bars.
- Each state is said once, as icon plus word.

Unresolved: product name (working name "Sprout"); app icon.
