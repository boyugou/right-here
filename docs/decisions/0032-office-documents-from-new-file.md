# 0032: New File makes blank Word, Excel and PowerPoint documents, and each template can be left out

Date: 2026-10-29. Status: decided; none of the three documents has been opened in Microsoft Office on the machine this was written on.

## Decision

- **Three more built-in templates**: Word Document (`docx`), Excel Workbook (`xlsx`) and PowerPoint Presentation (`pptx`), after the
  text and Markdown ones, named with Microsoft's words in each language and the product names as they are.
- **They make documents, not empty files.** An empty file named `.docx` is not a Word document. A template has a `format`
  (`OfficeFormat`), and the file is an Office Open XML package (ECMA-376) with the fewest parts that format needs: the document,
  the workbook with one empty sheet, the presentation with one empty slide, its master, layout and theme. `OfficeDocument` writes the
  parts from the standard and stores them in a ZIP archive (`StoredZip`: no compression, CRC-32, the date 1 January 1980), so the same
  format always gives the same bytes. No file of Microsoft Office, of another office suite or of a library is copied into it; the
  theme's colours and font are this project's own choice.
- **The plan names the format, not the bytes.** `CreateFileStep` carries `format`, and the executor asks `OfficeDocument` for the
  bytes when it writes the file, so `rh run --dry-run --json`, the MCP plan and the summaries stay short and readable.
- **A written-out template keeps its format.** Customize Templates writes `format = "docx"` with the Word template, and the config
  can give any template a format; the extension must then be the format's, and the contents empty (`rh config validate` says so).
- **Each template can be left out of the New File submenu**: `new_file.hidden = ["pptx"]`, a check on each template's line on the
  Finder Menu page. A hidden template is still an action of its own (`rh run new-file.pptx`) and can be a line of the menu.
  It is a setting an assistant may change by itself (it adds or takes away a menu line, and runs nothing).

## Why

New File should offer the Office documents people make most, by default, and let anyone switch off the ones they do not use:
all five are shown at first, and each can be unchecked.

## Checked

- Each package passes `unzip -t` and lists exactly its parts (`OfficeDocumentTests`); the CRC-32 is the standard one (its check
  value for "123456789").
- Read by python-docx, openpyxl and python-pptx (the presentation also takes a new slide and saves), by `textutil` (the Word
  document), and drawn by Quick Look as a thumbnail (`qlmanage -t`, which opens no window). The presentation was not drawn while it had
  no slide; it has one.

## Not checked

- Opening each document in Word, Excel and PowerPoint: `docs/development/MANUAL_CHECKS.md`, section 6b.
