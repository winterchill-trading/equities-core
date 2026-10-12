# NYSE Pillar Gateway binary order entry

Sources (public, fetched 2026-10-12):

- NYSE Pillar Gateway Binary Protocol Specification, spec 6.1, protocol 1.1, 2026-09-22:
  <https://www.nyse.com/publicdocs/NYSE_Pillar_Gateway_Binary_Protocol_Specification.pdf>
- NYSE Pillar Stream Protocol Specification:
  <https://www.nyse.com/publicdocs/NYSE_Pillar_Stream_Protocol_Specification.pdf>
- Reason codes and liquidity indicators (spreadsheet, not summarised here):
  <https://www.nyse.com/publicdocs/nyse/NYSE_Pillar_Reason_Codes_and_Liquidity_Indicators.xlsx>
- Order type matrix (spreadsheet): <https://www.nyse.com/publicdocs/NYSE_Pillar_Binary_Gateway_Order_Type_Matrix.xlsx>

Covers NYSE, NYSE Arca, NYSE American, NYSE National and NYSE Texas equities.

## Data types

All integers are **little endian**.

| Type | Meaning |
| --- | --- |
| `u8` `u16` `u32` `u64` | unsigned LE |
| `char(n)` | ASCII, right padded with spaces |
| `zchar(n)` | ASCII, right padded with NUL |
| `Price` | `u64`, scale 8: `123000000` = $1.23 |
| `Timestamp` | `u64` ns since the Unix epoch |
| `MsgHeader` | `type:u16` at 0, `length:u16` at 2; length covers header + payload + add-ons |

Maximum order quantity: 5,000,000 shares (NYSE auction orders 25,000,000). Maximum price
depends on the XDP price scale code of the symbol (scale 6: $2,147.48; 4: $214,748.364;
3: $999,999.999).

## Session layer (Pillar Stream Protocol)

TCP. The client logs in, the gateway advertises streams, the client opens them. Each
direction is a *stream* of sequenced messages; unsequenced messages manage the streams.

`StreamId` is 8 bytes: `sess:u32` (bits 24-31 env id, 0-23 session number) and
`value:u32` (bits 24-31 stream type, 8-23 user id, 0-7 sub id). Stream types: `15` TG
(trader to gateway, write), `13` GT (gateway to trader, read), `33` REF (reference data,
read). `SeqMsgId` = `stream_id:StreamId` + `seq:u64` (from 1).

| Message | Type | Len | Dir | Fields (offset) |
| --- | --- | --- | --- | --- |
| Login | `0x0201` | 76 | C→G | username char(16) @4, password char(32) @20, mic char(4) @52, version char(20) @56 = `"1.1"` |
| LoginResponse | `0x0202` | 21 | G→C | username char(16) @4, status u8 @20 |
| StreamAvail | `0x0203` | 21 | G→C | stream_id @4, next_seq u64 @12, access u8 @20 (bit0 read, bit1 write, bit2 throttle reject) |
| Heartbeat | `0x0204` | 4 | C→G | client sends every 1 s; gateway drops the connection after 5 s of silence |
| Open | `0x0205` | 30 | C→G | stream_id @4, start_seq u64 @12, end_seq u64 @20 (exclusive), access u8 @28, mode u8 @29 (bit0 lossy) |
| OpenResponse | `0x0206` | 14 | G→C | stream_id @4, status u8 @12, access u8 @13 |
| Close | `0x0207` | 12 | C→G | stream_id @4 |
| CloseResponse | `0x0208` | 13 | G→C | stream_id @4, status u8 @12 |
| SeqMsg | `0x0905` | ≥32 | both | seqmsg SeqMsgId @4, reserved u32 @20, timestamp u64 @24, payload MsgHeader @32 |

StreamAvail is also sent once per second per stream and doubles as the gateway's
heartbeat. Status codes: 0 ok, 18 not logged in, 24 invalid login, 27 already logged in,
28 heartbeat timeout, 29 login timed out, 33 invalid message, 54 no stream permission,
81 invalid protocol version, 82 out of sequence, 84 invalid stream, 85 stream not open,
86 invalid timestamp, 89 denial of service, 90 write permission revoked.

Typical flow: Login, LoginResponse, StreamAvail(TG, GT, REF), Open REF/GT with
`start_seq 1, end_seq 0xffffffffffffffff, access read`, Open TG `access write`, then
SeqMsgs both ways. Replay of GT is an Open with an older start_seq.

## Application payloads (inside SeqMsg)

### BitfieldOrderInstructions (u64)

| Field | Bit | Width | Values |
| --- | --- | --- | --- |
| SubIDIndicator | 12 | 1 | 0 use MPSubID for STP, 1 MPID level only |
| SpecialOrdType | 13 | 4 | 0 none, 1-3 DMM, 4 QCT |
| LocateReqd | 17 | 1 | must be 0 for short sides |
| RetailIndicator | 18 | 1 | |
| AttributedQuote | 19 | 3 | |
| OrderCapacity | 22 | 3 | 1 agency, 2 principal, 3 riskless principal |
| InterestType | 25 | 3 | 4 Q-order, 5/6 CCO |
| TradingSessionID | 28 | 3 | 0 overnight, 1 early, 2 core, 3 late, 4 early+core, 5 core+late, 6 early+core+late, 7 all incl. overnight |
| TimeInForce | 31 | 3 | 1 Day, 2 IOC, 3 at the opening (OPG), 4 on close |
| ProactiveIfLocked | 34 | 3 | |
| SelfTradeType | 37 | 3 | 0 session default, 1 none, 2 cancel newest, 3 cancel oldest, 4 cancel both, 5 cancel decrement |
| CancelInsteadOfReprice | 40 | 4 | 0, 1 LULD only, 3 any reason |
| RoutingInst | 44 | 4 | 1 non-routable, 2 routable, 8 minimum fill, ... |
| ExtendedExecInst | 48 | 4 | 1 ALO, 8 imbalance offset, ... |
| ExecInst | 52 | 4 | 4 ISO, 5 primary peg, 6 market peg, 7 midpoint liquidity, 8 non-displayed, 9 trade-at ISO |
| OrdType | 56 | 4 | 1 market, 2 limit, 3 inside limit, 4 pegged |
| Side | 60 | 4 | 1 buy, 2 sell, 3 sell short, 4 sell short exempt, 5-7 cross |

Bits 0-11 reserved. Market-on-close is OrdType 1 + TIF 4; limit-on-close OrdType 2 + TIF 4;
MOO/LOO use TIF 3.

### Member to Pillar (TG stream)

| Message | Type | Len |
| --- | --- | --- |
| Session Configuration Request | `0x0220` | 74 |
| Sequenced Filler | `0x0282` | 4 |
| New Order Single / Cancel-Replace | `0x0240` | 65 + optional add-on |
| Order Cancel Request | `0x0280` | 28 |
| Order Modify Request (reduce qty, change sell side) | `0x0270` | 34 |
| Bulk Cancel Request | `0x0281` | |
| Symbol Subscription, TG Begin/End, Manual Action, risk messages (DMM, risk) | `0x0346`, `0x0343`, `0x0344`, `0x0354`, `0x0330`, `0x0331` | |

New Order Single `0x0240`:

| Field | Type | Off | Len | Notes |
| --- | --- | --- | --- | --- |
| msghdr | MsgHeader | 0 | 4 | |
| SymbolID | u32 | 4 | 4 | from the REF stream symbol message |
| MPID | zchar(4) | 8 | 4 | firm id |
| MMID | u32 | 12 | 4 | |
| MPSubID | char | 16 | 1 | |
| ClOrdID | u64 | 17 | 8 | unique per Username+MPID among open orders |
| OrigClOrdID | u64 | 25 | 8 | 0 for a new order, else the order being replaced |
| BitfieldOrderInstructions | u64 | 33 | 8 | above |
| Price | Price | 41 | 8 | |
| OrderQty | u32 | 49 | 4 | |
| MinQty | u32 | 53 | 4 | 0 none |
| UserData | zchar(8) | 57 | 8 | echoed |
| add-on | | 65 | var | e.g. OptionalOrderAddOn `0x0241` len 41: MaxFloor u32 @9 (reserve display), LocateBroker @13, OffsetPrice @25 |

Cancel `0x0280`: SymbolID u32 @4, MPID @8, ClOrdID u64 @12, OrigClOrdID u64 @20.
Modify `0x0270`: as cancel, then OrderQty u32 @28, Side u8 @32, LocateReqd u8 @33. Modify
keeps priority and OrderID; cancel/replace loses priority and gets a new OrderID.

Session Configuration Request `0x0220`: Username char(16) @4, CancelOnDisconnect u8 @20,
ThrottlePreference u8 @21, SelfTradePrevention u8 @22 (session default STP),
OrderPriorityUpdate u8 @23, BOLDDesignation u8 @24, reserved zchar(49) @25.

### Pillar to member (GT and REF streams)

| Message | Type | Len | Stream |
| --- | --- | --- | --- |
| Equities Symbol Reference Data | `0x0232` | 56 | REF |
| MPV Class / MPV Level reference data | `0x0230` / `0x0231` | | REF |
| MPID / MMID Configuration | `0x0272` / `0x0273` | | REF |
| Session Configuration Ack | `0x0221` | 98 | REF |
| Order and Cancel/Replace Ack | `0x0260` | ≥102 | GT |
| Modify/Cancel Request Ack and UROUT | `0x0271` | ≥74 | GT |
| Order Priority Update Ack | `0x0262` | | GT |
| Execution Report | `0x0290` | ≥84 | GT |
| Trade Bust/Correct | `0x0292` | 82 | GT |
| Application Layer Reject | `0x0263` | 43 | GT |
| Auction Price Data (NYSE DMM) | `0x0352` | 46 | GT |

Symbol reference `0x0232`: TransactTime @4, SymbolID u32 @12, NYSESymbol char(24) @16,
ListedMIC char(4) @40, RoundLotSize u8 @44, ADVRiskRangeID u8 @45, MPVClassID u16 @53,
TestSymbolIndicator u8 @55. MPV level `0x0231` carries the price range and quoting/trading
MPV (tick) per class.

Order ack `0x0260`: TransactTime @4, SymbolID @12, MPID @16, MMID @20, MPSubID @24,
ClOrdID @25, OrigClOrdID @33, BitfieldOrderInstructions @41, Price @49, OrderQty @57,
MinQty @61, OrderID u64 @65, LeavesQty u32 @73, WorkingPrice @77, WorkingAway u8 @85,
PreLiquidityIndicator zchar(4) @86, ReasonCode u16 @90, AckType u8 @92 (1 new, 6 pending
replace, 8 replaced, ...), BitfieldFlowIndicator u8 @93, UserData @94.

Modify/cancel ack `0x0271` (also the unsolicited out "UROUT"): TransactTime @4, SymbolID
@12, MPID @16, OrderID @20, RefClOrdID @28, OrigClOrdID @36, Price @44, OrderQty @52,
LeavesQty @56, Side u8 @60, LocateReqd u8 @61, ReasonCode u16 @62, AckType u8 @64 (5 pending
cancel, 7 pending modify, 9 modified, 11 canceled, 12 done for day), BitfieldFlowIndicator
u8 @65, UserData zchar(8) @66.

Execution report `0x0290`: TransactTime @4, SymbolID @12, MPID @16, OrderID u64 @20,
ClOrdID u64 @28, DealID u64 @36 (shared by both sides, maps to XDP trade id), LastPx @44,
LeavesQty u32 @52, CumQty u32 @56, LastQty u32 @60, LiquidityIndicator zchar(4) @64,
BitfieldExecutionDetails u8 @68, reserved @69, LocateReqd u8 @72, ParticipantType u8 @73,
ReasonCode u16 @74, UserData @76.

Reject `0x0263`: TransactTime @4, SymbolID @12, MPID @16, ClOrdID @20, ReasonCode u16 @28,
RejectType u8 @30 (1 order/replace, 2 modify, 3 cancel, 4 bulk cancel), UserData @31,
reserved char(4) @39.

OrderID and DealID on the gateway equal the order id and trade id published on XDP, so
a client can match its own orders on the feed.

## Simulator scope

A minimal `nyse-sim` gateway must implement:

- Stream protocol: Login/LoginResponse, StreamAvail (on login and every second), Heartbeat
  timeout, Open/OpenResponse with replay of GT from `start_seq`, Close, SeqMsg framing.
- REF stream: Equities Symbol Reference Data `0x0232` per symbol, Session Configuration
  Ack `0x0221`.
- TG: New Order `0x0240` (limit, market, IOC, Day, OPG/on close, ALO, MaxFloor reserve,
  STP types 1-5), Cancel `0x0280`, Modify `0x0270`, Cancel/Replace (`0x0240` with
  OrigClOrdID).
- GT: Order Ack `0x0260` (AckType 1, 8), Modify/Cancel Ack `0x0271` (AckType 9, 11),
  Execution Report `0x0290`, Application Layer Reject `0x0263`.
- Cancel on disconnect.

Out of scope: DMM and floor broker messages, risk controls, routing, pegs, retail,
cross orders, trade bust/correct, drop copies.

Session Configuration Ack `0x0221` begins TransactTime @4, UserSessionType u8 @12,
UserSessionStatus u8 @13, Username char(16) @14, MIC char(4) @30, CancelOnDisconnect u8 @34;
the rest of its 98 bytes echoes the request settings.

Not verified: reason code and liquidity indicator values (they live in a spreadsheet that
was not read); the tail of the Session Configuration Ack past offset 34.
