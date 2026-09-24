# WolvenKit source requirement

`mt_ecosystem.archive` contains the cooked `mt_ecosystem.journal` resource. The
editable WolvenKit source was not shipped in the inspected NCM 2.0 package.
Recover it from the canonical development repository before adding localized
ArchiveXL on-screen JSON files or changing Redscript phone routing.

Required inventory after recovery: seven contact names, every intro message,
choice, conversation entry, notification, journal ID, and `LocKey#9000xxx`.
Rendered English comparisons in `MTEJournalHandler.reds` must become stable
choice-ID or LocKey routing; English comparisons may remain only as logged
compatibility fallback.
