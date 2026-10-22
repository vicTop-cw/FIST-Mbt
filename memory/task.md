R97 BUG-60 FIX COMPLETE:
- Fixed JS backend: Added counter initialization and increment for infinite loops with `循 于 「x」 附 计数 <init>`
- Fixed BEAM backend: Changed to Stream.unfold for proper counter increment
- Fixed pre-existing bug: BEAM `出`/`继` in infinite loops now correctly wrapped in try/catch
- All 13 loop tests pass
- BUG-60 marked FIXED in ledger
- Dual-backend stdout equality verified