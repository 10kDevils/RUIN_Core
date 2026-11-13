-- RUIN Core: this release's signed notice. The release build writes it
-- (tools/release/notice.py, with the RUIN_RELEASE_SEED secret); a copy built
-- by hand has none, and RUIN then only passes on notices it hears about.
local ADDON, ns = ...
ns.RELEASE_NOTICE = nil
