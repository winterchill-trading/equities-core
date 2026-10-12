# NYSE Pillar Integrated Feed (XDP)

Sources (public, fetched 2026-10-12):

- Pillar Integrated Feed Client Specification v2.5h, 2026-07-30:
  <https://www.nyse.com/publicdocs/nyse/data/NYSE_Pillar_Integrated_Feed_Client_Specification.pdf>
- Pillar Equities Common Client Specification v2.4t, 2026-10-01 (packet header, control
  messages, request server):
  <https://beta.nyse.com/publicdocs/nyse/data/NYSE_Pillar_Equities_Common_Client_Specification.pdf>

The Integrated Feed is an order-by-order (depth of book) multicast feed that also carries
trades, auction imbalances and security status, in matching-engine order. It is UDP
multicast, with A/B lines, a TCP Request Server for retransmission and refresh, and
refresh multicast channels.

## Encoding

- Little endian binary; ASCII strings left aligned, NUL padded; no alignment padding.
- Packet: 16-byte header, then `NumberMsgs` messages; max packet 1400 bytes; messages never
  straddle packets. Heartbeat = header with no messages, DeliveryFlag 1, once a second.
- Every message starts with `MsgSize:u16`, `MsgType:u16`. Clients must skip using MsgSize
  (messages may grow trailing fields).
- Time: `SourceTime` seconds come in Source Time Reference (type 2) once a second per
  channel; data messages carry only `SourceTimeNS` (ns within that second).
- Prices: `u32`/`i32` numerator; `price = value / 10^PriceScaleCode` from the Symbol Index
  Mapping message (scale 6 under $500 last close, 4 from $500, 3 from $100,000).
- Order ids are 8 bytes and equal the gateway OrderID. Trade ids are 4 bytes, the low 4 bytes
  of the gateway DealID; the full DealID is `0 | SystemID:u8 | MarketID:u16 | TradeID:u32`.
- Sequence numbers: per channel; the packet header gives the first message's number.
  `SymbolSeqNum` per symbol lets a client track a few symbols and request per-symbol refresh.

### Packet header

| Field | Off | Len | Notes |
| --- | --- | --- | --- |
| PktSize | 0 | 2 | including the header |
| DeliveryFlag | 2 | 1 | 1 heartbeat, 10 failover, 11 original, 12 seq reset, 13/15 retransmission, 17-20 refresh |
| NumberMsgs | 3 | 1 | |
| SeqNum | 4 | 4 | of the first message |
| SendTime | 8 | 4 | seconds since epoch |
| SendTimeNS | 12 | 4 | |

## Control messages

| Type | Name | Size | Fields |
| --- | --- | --- | --- |
| 1 | Sequence Number Reset | 14 | SourceTime @4, SourceTimeNS @8, ProductID u8 @12, ChannelID u8 @13; own packet, SeqNum 1 |
| 2 | Source Time Reference | 16 | ID u32 @4 (system id), SymbolSeqNum @8 (reserved), SourceTime u32 @12 |
| 3 | Symbol Index Mapping | 44 | SymbolIndex u32 @4, Symbol char(11) @8, MarketID u16 @20, SystemID u8 @22, ExchangeCode @23, PriceScaleCode u8 @24, SecurityType @25, LotSize u16 @26, PrevClosePrice u32 @28, PrevCloseVolume u32 @32, PriceResolution @36, RoundLot @37, MPV u16 @38, UnitOfTrade u16 @40, ... |
| 32 | Symbol Clear | 20 | SourceTime, SourceTimeNS, SymbolIndex @12, NextSourceSeqNum @16 |
| 34 | Security Status | 46 | SourceTime @4, SourceTimeNS @8, SymbolIndex @12, SymbolSeqNum @16, SecurityStatus @20, HaltCondition @21, Price1 @26, Price2 @30, SSR exchange @34, SSR volume @35, Time @39, SSRState @43, MarketState @44 |
| 10, 13, 15 | Retransmission / Symbol Index / Refresh request | | client to Request Server (TCP) |
| 11, 12, 31, 35 | Request Response, Heartbeat Response, Message Unavailable, Refresh Header | | |

Security Status values: `4` halt, `5` resume, `6` suspend, `A`/`C`/`D` short sale
restriction activated/continued/deactivated, `P` pre-opening, `B` begin accepting orders,
`E` early session, `O` core session, `L` late session, `X` closed, `I` halt resume price
indication, `G` pre-opening indication. Halt conditions include `M` LULD pause, `D` news
released, `P` news pending, `1`/`2`/`3` market-wide circuit breaker levels, `~` none.

## Integrated Feed messages

Side is ASCII `'B'`/`'S'`. All offsets in bytes.

| Type | Name | Size | Fields |
| --- | --- | --- | --- |
| 100 | Add Order | 39 | SourceTimeNS @4, SymbolIndex @8, SymbolSeqNum @12, OrderID u64 @16, Price u32 @24, Volume u32 @28, Side @32, FirmID char(5) @33, reserved @38 |
| 101 | Modify Order | 35 | ... OrderID @16, Price @24, Volume @28, PositionChange u8 @32, Side @33 |
| 102 | Delete Order | 25 | ... OrderID @16 |
| 103 | Order Execution | 42 | ... OrderID @16, TradeID u32 @24, Price @28, Volume @32 (executed qty), PrintableFlag @36, TradeCond1-4 @38-41 |
| 104 | Replace Order | 42 | ... OrderID @16, NewOrderID u64 @24, Price @32, Volume @36, Side @40 |
| 105 | Imbalance | 73 | SourceTime @4, SourceTimeNS @8, SymbolIndex @12, SymbolSeqNum @16, ReferencePrice @20, PairedQty @24, TotalImbalanceQty @28, MarketImbalanceQty @32, AuctionTime u16 @36 (HHMM), AuctionType @38, ImbalanceSide @39, ContinuousBookClearingPrice @40, AuctionInterestClearingPrice @44, SSRFilingPrice @48, IndicativeMatchPrice @52, UpperCollar @56, LowerCollar @60, AuctionStatus @64, FreezeStatus @65, NumExtensions @66, UnpairedQty @67, UnpairedSide @71 |
| 106 | Add Order Refresh | | Add Order plus refresh context, on refresh channels |
| 110 | Non-Displayed Trade | 33 | ... TradeID @16, Price @20, Volume @24, PrintableFlag @28, TradeCond1-4 @29-32 |
| 111 | Cross Trade | | |
| 112 | Trade Cancel | | |
| 113 | Cross Correction | | |
| 114 | Retail Price Improvement | | |
| 223 | Stock Summary | | dedicated channel |

Semantics worth reproducing:

- Execution `Volume` equal to the remaining size removes the order; execution price may
  differ from the order price (price improvement), remaining shares keep the order price.
- Delete is not sent for full executions, and not for cancel/replace (Replace is sent).
- On session transitions (early to core) orders not eligible for the new session are
  deleted explicitly; at close Security Status `X` implies all orders gone, no deletes.
- Imbalance messages are sent once a second during the auction periods only when a
  calculated field changes. AuctionType `O` early opening, `M` core opening, `H` reopening,
  `C` closing, `P` extreme closing, `R` regulatory.
- Hidden liquidity trades appear as Non-Displayed Trade (110), not as Order Execution.

## Simulator scope

A minimal `nyse-sim` feed must publish:

- Packet header with sequence numbers, heartbeat packets, Sequence Number Reset at start.
- Source Time Reference once a second, Symbol Index Mapping per symbol at startup.
- Add (100), Modify (101), Delete (102), Execution (103), Replace (104), Non-Displayed
  Trade (110), Imbalance (105) during auctions, Security Status (34) for session
  transitions, halts, LULD pauses and SSR.
- Over TCP instead of multicast in the sim: the same packets length-prefixed by PktSize; a
  Refresh Request (15) answered with Add Order Refresh (106) for every resting order.

Out of scope: retransmission server, A/B lines, cross trades and corrections, RPI, stock
summary.

Not verified: exact layouts of 106, 111-114 and 223; the full value lists of TradeCond1-4;
the Request Server message layouts.
