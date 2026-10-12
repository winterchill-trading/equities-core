# Cboe US Equities BOE (Binary Order Entry) v2

Sources (public, fetched 2026-10-12):

- Cboe Titanium U.S. Equities BOE Specification v2.4.58, 2026-10-05 (Markdown edition of the
  PDF): <https://cdn.cboe.com/resources/techspec/technical-specifications-cboe-titanium-u-s-equities-boe-specification.md>
- Cboe Titanium U.S. Options BOE Specification v2.11.116, 2026-09-25:
  <https://cdn.cboe.com/resources/techspec/technical-specifications-cboe-titanium-u-s-options-boe-specification.md>
- Cboe also publishes BOEv3 (new message layouts and price scaling); this summary is v2.

Applies to BZX, BYX, EDGX and EDGA equities.

## Data types

| Type | Encoding |
| --- | --- |
| Binary | unsigned little endian, size by context |
| Binary Price | signed LE 8 bytes, **4 implied decimals** (`1234500` = $123.45) |
| Short Binary Price | signed LE 4 bytes, 4 implied decimals |
| Signed Binary Fee | signed LE 8 bytes, 5 implied decimals |
| Alpha / Alphanumeric / Text | ASCII, NUL padded on the right |
| DateTime | 8 bytes, ns since the Unix epoch, UTC |
| Date | `u32` with value `YYYYMMDD` |

All default values are binary zero.

## Framing and session

Every message has a 10-byte header:

| Field | Off | Len | Notes |
| --- | --- | --- | --- |
| StartOfMessage | 0 | 2 | `0xBA 0xBA` |
| MessageLength | 2 | 2 | bytes from this field to the end (excludes StartOfMessage) |
| MessageType | 4 | 1 | |
| MatchingUnit | 5 | 1 | 0 inbound and for session messages; outbound sequenced messages carry the unit |
| SequenceNumber | 6 | 4 | inbound: one stream across units; outbound: per matching unit; 0 for session messages |

Session messages are unsequenced. On reconnect the member sends the last sequence it saw
per unit in the Login Request; Cboe replays missed outbound messages, then sends Replay
Complete. Login Response carries the last inbound sequence Cboe processed, so the member
may resend later orders. Heartbeats are sent by each side after 1 s of silence. One
connection per username + session sub id.

| Message | Type | Dir | Fields |
| --- | --- | --- | --- |
| Login Request | `0x37` | M→C | SessionSubID alnum(4) @10, Username alnum(4) @14, Password alnum(10) @18, NumberOfParamGroups u8 @28, groups |
| Logout Request | `0x02` | M→C | |
| Client Heartbeat | `0x03` | M→C | |
| Login Response | `0x24` | C→M | LoginResponseStatus @10 (`A` accepted, `N` not authorised, `D` disabled, `B` in use, `F` invalid return bitfields, ...), Text(60) @11, NoUnspecifiedUnitReplay @71, LastReceivedSequenceNumber u32 @72, NumberOfUnits u8 @76, (unit u8, seq u32)*, echoed param groups |
| Logout | `0x08` | C→M | reason and text, last sequences |
| Server Heartbeat | `0x09` | C→M | |
| Replay Complete | `0x13` | C→M | |

Login parameter groups: `0x80` Unit Sequences (`len u16, type, NoUnspecifiedUnitReplay u8,
NumberOfUnits u8, (unit u8, seq u32)*`) and `0x81` Return Bitfields (`len u16, type,
MessageType u8, NumberOfReturnBitfields u8, bitfield bytes`). Return bitfields chosen at
login decide which optional fields Cboe appends to each outbound message type for the
whole session; each outbound message still carries its bitfields.

## Optional fields

New Order, Cancel, Modify and every outbound message end with `NumberOfBitfields u8`, the
bitfield bytes, then the selected optional fields **in bitfield order** (byte 1 bit 0
first). New Order input bitfields (byte: bit value, field, length):

| Byte | 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | ClearingFirm 4 | ClearingAccount 4 | Price 8 | ExecInst 1 | OrdType 1 | TimeInForce 1 | MinQty 4 | MaxFloor 4 |
| 2 | Symbol 8 (required) | SymbolSfx 8 | Currency | IdSource | SecurityId | SecurityExchange | Capacity 1 (required) | RoutingInst 4 |
| 3 | Account 16 | DisplayIndicator 1 | reserved | DiscretionAmount 2 | PegDifference 8 | PreventMatch 3 | LocateReqd 1 | ExpireTime 8 |
| 4 | MaturityDate | StrikePrice | PutOrCall | RiskReset 8 | OpenClose | CMTANumber | TargetPartyID | reserved |
| 5 | SessionEligibility | AttributedQuote 1 | BookingType | ExtExecInst 1 | ClientID | InvestorID | ExecutorID | OrderOrigination |
| 6 | DisplayRange 4 | StopPx 8 | RoutStrategy 6 | RouteDeliveryMethod 3 | ExDestination 1 | EchoText 64 | AuctionId | RoutingFirmID |

Field values used by a simulator:

- Side: `1` buy, `2` sell, `5` sell short, `6` sell short exempt.
- OrdType: `1` market, `2` limit (default), `3` stop, `4` stop limit, `P` pegged.
- TimeInForce: `0` Day (default), `1` GTC (treated as Day), `2` at the open (BZX listed), `3`
  IOC, `4` FOK, `5` GTX (to end of post-market), `6` GTD (needs ExpireTime), `7` at the close,
  `E` pre-market to end of regular, `R` regular hours only, `X` pre-market to end of post.
- Capacity: `A` agency, `P` principal, `R` riskless principal.
- RoutingInst first char: `B` book only, `P` post only (ALO), `R` routable, ...
- ExecInst `f`: intermarket sweep (ISO).
- MaxFloor: displayed quantity of a reserve order, 0 = all displayed.
- DisplayIndicator: re-pricing options; `I`-style values make the order invisible (hidden).
- PreventMatch (STP), 3 chars: modifier `N` cancel newest, `O` oldest, `B` both, `S`
  smallest, `D` decrement larger / cancel smaller; level `F` firm, `M` MPID, `X` affiliate;
  optional trading group id.
- OrderQty limit 999,999 shares.

## Application messages

| Message | Type | Seq | Fixed part (offsets) |
| --- | --- | --- | --- |
| New Order | `0x38` | yes | ClOrdID text(20) @10, Side @30, OrderQty u32 @31, NumberOfNewOrderBitfields @35, bitfields @36 |
| Cancel Order | `0x39` | yes | OrigClOrdID text(20) @10, NumberOfCancelOrderBitfields @30 |
| Modify Order | `0x3A` | yes | ClOrdID(20) @10, OrigClOrdID(20) @30, NumberOfModifyOrderBitfields @50 (OrderQty, Price, OrdType, CancelOrigOnReject ...) |
| Purge Orders | `0x47` | yes | mass cancel by MPID / symbol / risk group |
| Order Acknowledgment | `0x25` | yes | TransactionTime @10, ClOrdID(20) @18, OrderID u64 @38, reserved @46, NumberOfReturnBitfields @47 |
| Order Rejected | `0x26` | no | TransactionTime @10, ClOrdID @18, OrderRejectReason @38, Text(60) @39, reserved @99, bitfields count @100 |
| Order Modified | `0x27` | yes | TransactionTime @10, ClOrdID @18, OrderID @38, ... |
| Order Restated | `0x28` | yes | reserve reload, SWP restatement |
| User Modify Rejected | `0x29` | no | |
| Order Cancelled | `0x2A` | yes | TransactionTime @10, ClOrdID @18, CancelReason @38, reserved @39, count @40 |
| Cancel Rejected | `0x2B` | no | |
| Order Execution | `0x2C` | yes | TransactionTime @10, ClOrdID @18, ExecID u64 @38, LastShares u32 @46, LastPx Price @50, LeavesQty u32 @58, BaseLiquidityIndicator @62, SubLiquidityIndicator @63, ContraBroker alnum(4) @64, reserved @68, count @69 |
| Trade Cancel or Correct | `0x2D` | yes | |
| Mass Cancel Acknowledgment | `0x36` | no | |
| Purge Rejected | `0x48` | no | |

OrderID matches the Order Id on PITCH. ExecID is printed as 9 base-36 characters; the
first character tells internal match (`0`), auction fill (`C`), routed (`R`).
BaseLiquidityIndicator: `A` added, `R` removed, `X` routed, `C` auction.

Reason codes (single character, in rejects and cancels): `A` admin, `D` duplicate ClOrdID,
`H` halted, `J` too late to cancel, `L` would lock/cross NBBO, `M` size exceeded, `N` ran out
of liquidity, `O` unknown ClOrdID, `S` short sale price violation, `U` user requested, `V`
would wash (STP), `W` ALO would remove, `X` expired, `Y` symbol not supported, `Z`
unforeseen, `u` LULD, `x` crossed market.

## Cboe Options: BOE and PITCH differences

- Same framing, session and bitfield scheme; message types add `0x41` New Order Cross,
  `0x4B` New Complex Order, `0x5A` Cross Multileg, `0x55`/`0x59` Quote Update (market
  makers), `0x56` Reset Risk, `0x4C` New Complex Instrument, and `0x43`/`0x44`/`0x46` cross
  acknowledgements.
- An option is either a Cboe-format symbol or root Symbol plus byte-4 bitfield fields
  MaturityDate (Date `YYYYMMDD`), StrikePrice (Binary Price, 0 - 999,999.99), PutOrCall
  (`0` put, `1` call), and OpenClose (`O`, `C`, `N`). OrderQty is contracts (max 999,999).
- Capacity values: `C` customer, `M` market maker, `F` firm, `U` professional customer, `N`
  away market maker, `B` broker-dealer, `J` joint back office.
- PITCH for options uses 6-character feed symbols mapped to 21-character OSI symbols by a
  Symbol Mapping message (`0x2E`); executions and trades carry an extra Trade Condition
  byte; options add Transaction Begin/End, Width Update, Options Auction Update and auction
  notification messages; Add Order flags bit 3 marks AON.
- Price ticks follow the options tick tables (see `Tick_size`), not the penny rule.

## Simulator scope

A minimal `cboe-sim` BOE port must implement:

- Framing with `0xBABA`, Login Request/Response with unit sequences and return bitfields,
  replay of outbound messages per unit then Replay Complete, heartbeats both ways,
  Logout.
- New Order (Price, OrdType, TimeInForce 0/3/4/7/2, Symbol, Capacity, RoutingInst `B`/`P`,
  MaxFloor, PreventMatch, ExecInst `f`), Cancel Order, Modify Order (price and size).
- Order Acknowledgment, Order Rejected, Order Modified, Order Cancelled, Cancel Rejected,
  Order Execution, Order Restated for reserve reloads.
- Return bitfields honoured at least for Side, Price, Symbol, OrderQty, LeavesQty.

Out of scope: routing, pegs, discretion, stops, purge and risk messages, trade
cancel/correct, options crosses and quotes.

Not verified: full Logout and Order Modified layouts, the complete return bitfield
tables beyond Order Acknowledgment byte 1-3, the DisplayIndicator value list.
