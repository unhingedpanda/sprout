# Surface: main window

Mode: Operate. The user adds torrents, watches them, and manages what downloads or seeds.

## Direction contract

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
