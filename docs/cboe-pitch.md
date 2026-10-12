# Cboe US Equities/Options Multicast PITCH 2.X

Source (public, fetched 2026-10-12):

- Cboe Titanium U.S. Equities/Options Multicast PITCH Specification v2.41.82, 2026-10-02
  (Markdown edition of the PDF):
  <https://cdn.cboe.com/resources/techspec/technical-specifications-cboe-titanium-u-s-equitiesoptions-multicast-pitch-specification.md>
- PDF: <https://cdn.cboe.com/resources/techspec/technical-specifications-cboe-titanium-u-s-equitiesoptions-multicast-pitch-specification.pdf>

Full depth, order by order, anonymous. Multicast over UDP per matching unit (symbol range),
with a TCP Gap Request Proxy (GRP) for retransmission and TCP Spin Servers for book
snapshots. The same framing is used over TCP for GRP and spin traffic, which is what a
TCP-only simulator should speak. Order entry is BOE or FIX, never PITCH.

## Encoding

- Binary: unsigned little endian.
- Alphanumeric / Printable ASCII: left justified, **space padded** (unlike BOE, which NUL pads).
- Binary Short Price: `u16`, 2 implied decimals. Binary Long Price: `u64`, 4 implied decimals.
- Time Offset: `u32` ns since the last Time message of the unit.
- Every message: `Length u8` (including itself), `MessageType u8`. Clients skip unknown
  types and ignore trailing bytes (messages may grow).
- Long vs short variants: a sender picks short (`u16` qty, short price, 6-char symbol) when
  quantity < 65,536 and price fits two decimals below $655.36; otherwise long. Expanded
  variants carry 8-char symbols.

### Sequenced Unit Header (8 bytes)

| Field | Off | Len | Notes |
| --- | --- | --- | --- |
| Hdr Length | 0 | 2 | whole block including header |
| Hdr Count | 2 | 1 | messages that follow; 0 = heartbeat |
| Hdr Unit | 3 | 1 | matching unit |
| Hdr Sequence | 4 | 4 | sequence of the first message (implied +1 each); 0 for unsequenced |

Heartbeats (count 0) after 1 s of silence carry the next sequence. Clients must heartbeat
GRP and spin connections at least every 5 s.

## Messages

| Type | Name | Len | Fields (offset) |
| --- | --- | --- | --- |
| `0x20` | Time | 6 (10) | Time u32 @2 = seconds since midnight **Eastern**; Epoch Time u32 @6 on newer units |
| `0xB1` | Time Reference | | C1 options, BZX/EDGX equities from 2026-11-02 |
| `0x97` | Unit Clear | 6 | TimeOffset @2: drop all orders of the unit |
| `0x21` | Add Order long | 34 | TimeOffset @2, OrderId u64 @6, Side @14 (`B`/`S`), Quantity u32 @15, Symbol(6) @19, Price long @25, AddFlags @33 |
| `0x22` | Add Order short | 26 | OrderId @6, Side @14, Quantity u16 @15, Symbol(6) @17, Price short @23, AddFlags @25 |
| `0x2F` | Add Order expanded | 41 eq / 50 opt | OrderId @6, Side @14, Quantity u32 @15, Symbol(8) @19, Price long @27, AddFlags @35, ParticipantID(4) @36, CustomerIndicator @40 |
| `0x23` | Order Executed | 26 eq / 27 opt | OrderId @6, ExecutedQuantity u32 @14, ExecutionId u64 @18 (at the order's price) |
| `0x24` | Order Executed at Price/Size | 38 / 39 | OrderId @6, ExecutedQuantity @14, RemainingQuantity @18, ExecutionId @22, Price long @30 |
| `0x25` | Reduce Size long | 18 | OrderId @6, CanceledQuantity u32 @14 |
| `0x26` | Reduce Size short | 16 | OrderId @6, CanceledQuantity u16 @14 |
| `0x27` | Modify Order long | 27 | OrderId @6, Quantity u32 @14, Price long @18, ModifyFlags @26 (bit1 maintain priority) |
| `0x28` | Modify Order short | 19 | OrderId @6, Quantity u16 @14, Price short @16, ModifyFlags @18 |
| `0x29` | Delete Order | 14 | OrderId @6 |
| `0x2A` | Trade long | 41 / 42 | OrderId @6 (often obfuscated), Side @14 always `B`, Quantity u32 @15, Symbol(6) @19, Price long @25, ExecutionId @33 |
| `0x2B` | Trade short | 33 / 34 | Quantity u16 @15, Symbol(6) @17, Price short @23, ExecutionId @25 |
| `0x30` | Trade expanded | 43 / 44 | Symbol(8) @19, Price long @27, ExecutionId @35 |
| `0x2C` | Trade Break | 14 | ExecutionId @6 |
| `0x2D` | End of Session | 6 | |
| `0x31` | Trading Status | 18 | Symbol(6) @6, TradingStatus @14 (`H` halted, `Q` quote only, `R` opening rotation, `T` trading) |
| `0x95` | Auction Update | 47 | Symbol(8) @6, AuctionType @14 (`O` open, `C` close, `H` halt, `I` IPO, `M` market close, `P` periodic), ReferencePrice u64 @15, BuyShares u32 @23, SellShares u32 @27, IndicativePrice @31, AuctionOnlyPrice @39 |
| `0x96` | Auction Summary | 27 | Symbol(8) @6, AuctionType @14, Price long @15, Shares u32 @23 |
| `0x98` | Retail Price Improvement | | BYX/EDGX |
| `0x2E` | Symbol Mapping | 38 | options only: FeedSymbol(6) @2, OSI Symbol(21) @8, SymbolCondition @29, Underlying(8) @30 |

Gap Request Proxy (TCP): Login `0x01` (SessionSubId(4) @2, Username(4) @6, filler(2) @10,
Password(10) @12; 22 bytes), Login Response `0x02` (Status @2: `A`, `N`, `B`, `S`), Gap
Request `0x03` (Unit @2, Sequence u32 @3, Count u16 @7), Gap Response `0x04` (+ Status @9).
Requested messages are replayed on a gap multicast group.

Spin server (TCP): Spin Image Available `0x80` (Sequence @2), Spin Request `0x81`
(Sequence @2), Spin Response `0x82` (Sequence @2, OrderCount u32 @6, Status @10), then
Add Order messages for the whole book, then Spin Finished `0x83`. The client buffers
multicast from that sequence and applies it after the spin.

## Book semantics

- Executions against hidden orders appear only as Trade messages, with an obfuscated
  OrderId.
- Reserve orders: the displayed part executes as `0x23` on the visible OrderId; the hidden
  part as a Trade with an obfuscated id; on reload the order gets a **new OrderId** via a
  fresh Add Order.
- Execution ids print as 9 base-36 characters; the first character distinguishes local
  matches, auction fills (`C`) and routed trades (`R`).

## Simulator scope

A minimal `cboe-sim` PITCH feed (TCP, one unit) must publish:

- Sequenced Unit Header framing with heartbeats.
- Time every second, Add Order (long or expanded), Order Executed, Order Executed at
  Price/Size, Reduce Size, Modify Order, Delete Order, Trade (for hidden fills), Trading
  Status, Auction Update / Auction Summary around the open and close, End of Session.
- A spin on connect: Spin Response, Add Order per resting order, Spin Finished.

Out of scope: multicast, A/B feeds, GRP gap fills, options auction messages, RPI, width
updates.

Not verified: the Time Reference message layout, Instrument Definition messages and the
options auction message layouts (not needed for an equities sim).
