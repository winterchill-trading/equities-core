# CME iLink 3 order entry and MDP 3.0 market data (SBE)

Sources (public, fetched 2026-10-12). The CME Client Systems Wiki renders with JavaScript;
pages were read through its public Confluence REST API
(`/wiki/rest/api/content/<page id>?expand=body.view`).

- iLink Simple Binary Encoding (SOFH, SBE header, NewOrderSingle example, schema
  distribution): <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/714113056>
- iLink Message Header: <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/716013709>
- FIXP session messages: Negotiate
  <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457640053>, Establish
  <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457672951>, Sequence
  <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457096515>, Terminate
  <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457327359>, Not Applied
  <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457640161>
- MDP 3.0 SBE Technical Headers and SBE Message Header:
  <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457638617>,
  <https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457325932>
- **MDP 3.0 SBE schema (public FTP)**: `ftp://ftp.cmegroup.com/SBEFix/Production/Templates/templates_FixBinary.xml`
  (package `mktdata`, schema id 1, version 13, dated 20230411); also `templates_v13.xml`, and
  New Release / Cert copies under `SBEFix/NRCert/Templates/`, `SBEFix/Cert/Templates/`.
  MDP TCP session templates: `ftp://ftp.cmegroup.com/SBEFix/Production/SessionManagement/Templates/templates_MdpSessionMgmt_v0.xml`.
- **iLink 3 SBE schema**: `ilinkbinary.xml` on `sftpng.cmegroup.com` under
  `/MSGW/Production/Templates`, `/MSGW/NRCert/Templates`, `/MSGW/Cert/Templates`.
  It needs CME SFTP credentials and was **not** downloaded. Template ids and offsets below
  were checked against a third-party copy of `iLinkBinary` schema id 8 **version 5**
  (description 20200212) found in an open-source iLink 3 simulator; its NewOrderSingle514
  matches the byte-level example on the wiki. Newer versions may append fields.

## Encoding shared by both

- Little endian. SBE 1.0 RC4. Fixed-offset root block, then repeating groups, then
  variable-length data.
- Prices are `PRICE9` / `PRICENULL9`: `int64` mantissa, constant exponent -9
  (`100000000000` = 100.0). Null for `PRICENULL9` is `INT64_MAX`.
- Integer nulls: `uInt8` 255, `uInt16` 65535, `uInt32` 4294967295, `int32` `INT32_MIN`
  (SBE default); `charNULL` enum null is byte 0.
- Templates may be extended by appending fields: decoders must use the header's
  `BlockLength` (and the group's `blockLength`) to skip, never a hard-coded size.
- Timestamps are `uInt64` ns since the Unix epoch, UTC.

## iLink 3 (order entry over TCP, FIXP session layer)

Each message: SOFH (4 bytes) + SBE header (8 bytes) + body.

| Field | Type | Notes |
| --- | --- | --- |
| MessageSize | u16 | whole message including SOFH |
| EncodingType | u16 | `0xCAFE` (CME SBE 1.0 little endian) |
| BlockLength | u16 | root block size |
| TemplateID | u16 | |
| SchemaID | u16 | 8 |
| Version | u16 | schema version |

### Session (FIXP)

| Template | Message | Block | Key fields (offset) |
| --- | --- | --- | --- |
| 500 | Negotiate | 76 | HMACSignature char(32) @0, AccessKeyID char(20) @32, UUID u64 @52, RequestTimestamp u64 @60, Session char(3) @68, Firm char(5) @71, Credentials varData (length 0) |
| 501 | NegotiationResponse | 32 | UUID @0, RequestTimestamp @8, SecretKeySecureIDExpiration u16 @16, FaultToleranceIndicator @18, SplitMsg @19, PreviousSeqNo u32 @20, PreviousUUID u64 @24 |
| 502 | NegotiationReject | 68 | |
| 503 | Establish | 132 | HMACSignature @0, AccessKeyID @32, TradingSystemName char(30) @52, Version char(10) @82, Vendor char(10) @92, UUID @102, RequestTimestamp @110, NextSeqNo u32 @118, Session @122, Firm @125, KeepAliveInterval u16 ms @130 |
| 504 | EstablishmentAck | 38 | UUID @0, RequestTimestamp @8, NextSeqNo @16, PreviousSeqNo @20, PreviousUUID @24, KeepAliveInterval @32, SecretKeySecureIDExpiration @34, FaultToleranceIndicator @36, SplitMsg @37 |
| 505 | EstablishmentReject | 72 | |
| 506 | Sequence | 14 | UUID @0, NextSeqNo u32 @8, FaultToleranceIndicator @12, KeepAliveIntervalLapsed @13 (heartbeat) |
| 507 | Terminate | 67 | Reason char(48) @0, UUID @48, RequestTimestamp @56, ErrorCodes u16 @64, SplitMsg @66 |
| 508 | RetransmitRequest | 30 | UUID @0, LastUUID @8, RequestTimestamp @16, FromSeqNo u32 @24, MsgCount u16 @28 |
| 509 | Retransmission | 31 | same + SplitMsg @30 |
| 510 | RetransmitReject | 75 | |
| 513 | NotApplied | 17 | UUID @0, FromSeqNo u32 @8, MsgCount u32 @12, SplitMsg @16 (customer sequence gap) |

Flow: TCP connect, Negotiate (HMAC-SHA256 over
`RequestTimestamp\nUUID\nSessionID\nFirmID` with the CME secret key), NegotiationResponse,
Establish (within 60 s), EstablishmentAck, then business messages; customer flow is
*Idempotent*, CME flow *Recoverable*. UUID is chosen weekly and kept midweek to continue
sequence numbers. Sequence (506) is the heartbeat: sent when KeepAliveInterval lapses
without traffic; a second lapse disconnects. Every business message carries `SeqNum`
(tag 9726); CME answers a forward gap with NotApplied. All sessions are cancel on
disconnect (except CGW).

### Application messages

| Template | Message | Block | Dir |
| --- | --- | --- | --- |
| 514 | NewOrderSingle | 116 | C→E |
| 515 | OrderCancelReplaceRequest | 125 | C→E |
| 516 | OrderCancelRequest | 88 | C→E |
| 517 | MassQuote | 92 | C→E |
| 529 / 530 / 533 | OrderMassActionRequest / OrderMassStatusRequest / OrderStatusRequest | | C→E |
| 518, 537 | PartyDetailsDefinitionRequest, PartyDetailsListRequest | | C→E |
| 521 | BusinessReject | 330 | E→C |
| 522 | ExecutionReportNew | 209 | E→C |
| 523 | ExecutionReportReject | 467 | E→C |
| 524 | ExecutionReportElimination (expired / IOC remainder) | 202 | E→C |
| 525 | ExecutionReportTradeOutright | 235 | E→C |
| 531 | ExecutionReportModify | 217 | E→C |
| 532 | ExecutionReportStatus | 480 | E→C |
| 534 | ExecutionReportCancel | 214 | E→C |
| 535 / 536 | OrderCancelReject / OrderCancelReplaceReject | 409 | E→C |
| 564 / 565 | ExecutionReportPendingCancel / PendingReplace | | E→C |

NewOrderSingle 514 (verified against the wiki's hex example): Price PRICENULL9 @0,
OrderQty u32 @8, SecurityID i32 @12, Side u8 @16 (1 buy, 2 sell), SeqNum u32 @17, SenderID
char(20) @21, ClOrdID char(20) @41, PartyDetailsListReqID u64 @61, OrderRequestID u64 @69,
SendingTimeEpoch u64 @77, StopPx @85, Location char(5) @93, MinQty u32 @98, DisplayQty u32
@102, ExpireDate u16 @106, OrdType char @108 (`1` market with protection, `2` limit, `3`
stop with protection, `4` stop limit, `K` market with leftover as limit), TimeInForce u8
@109 (0 Day, 1 GTC, 3 FAK, 4 FOK, 6 GTD), ManualOrderIndicator @110, ExecInst set @111,
ExecutionMode @112, LiquidityFlag @113, ManagedOrder @114, ShortSaleType @115.

OrderCancelRequest 516: OrderID u64 @0, PartyDetailsListReqID @8, ManualOrderIndicator @16,
SeqNum @17, SenderID @21, ClOrdID @41, OrderRequestID @61, SendingTimeEpoch @69, Location
@77, SecurityID @82, Side @86, LiquidityFlag @87. OrderCancelReplaceRequest 515 is the new
order layout plus OrderID u64 @69 and OFMOverride @119.

ExecutionReportNew 522: SeqNum @0, UUID @4, ExecID char(40) @12, SenderID @52, ClOrdID
@72, PartyDetailsListReqID @92, OrderID @100, Price @108, StopPx @116, TransactTime @124,
SendingTimeEpoch @132, OrderRequestID @140, CrossID @148, HostCrossID @156, Location
@164, SecurityID @169, OrderQty @173, MinQty @177, DisplayQty @181, ExpireDate @185,
DelayDuration @187, OrdType @189, Side @190, TimeInForce @191, ManualOrderIndicator @192,
PossRetransFlag @193, ... (OrdStatus `0` and ExecType `0` are constants).

ExecutionReportTradeOutright 525: ... LastPx @100, OrderID @108, Price @116, ...,
SecurityID @185, OrderQty @189, LastQty @193, CumQty @197, MDTradeEntryID u32 @201 (links to
MDP TradeSummary), SideTradeID @205, TradeLinkID @209, LeavesQty @213, TradeDate @217,
OrdStatus @221 (1 partial, 2 filled), OrdType @222, Side @223, TimeInForce @224, ...,
AggressorIndicator @227; then groups NoFills (FillPx, FillQty, FillExecID, FillYieldType)
and NoOrderEvents.

ExecutionReportCancel 534: like 522 with CumQty @177 and ExecRestatementReason @199.

## MDP 3.0 (market data over UDP multicast)

Packet: `MsgSeqNum u32` + `SendingTime u64` (12 bytes; TCP conflated adds `0xCAFE` in
front), then messages. Each message: `MsgSize u16` (whole message including this field)
+ SBE header `BlockLength u16, TemplateID u16, SchemaID u16 (1), Version u16`. Repeating
groups use `groupSize` = `blockLength u16 + numInGroup u8` (3 bytes), or `groupSize8Byte`
(blockLength u16, numInGroup u8 at offset 7; 8 bytes).

| Template | Message | Block | Notes |
| --- | --- | --- | --- |
| 4 | ChannelReset | 9 | TransactTime, MatchEventIndicator, group ApplID |
| 12 | AdminHeartbeat | 0 | |
| 30 | SecurityStatus | 30 | TransactTime @0, SecurityGroup char(6) @8, Asset char(6) @14, SecurityID @20, TradeDate @24, MatchEventIndicator @26, SecurityTradingStatus @27, HaltReason @28, SecurityTradingEvent @29 |
| 46 | MDIncrementalRefreshBook | 11 | MBP (and MBOFD) book updates |
| 47 | MDIncrementalRefreshOrderBook | 11 | MBOFD only |
| 48 | MDIncrementalRefreshTradeSummary | 11 | trades |
| 49 / 51 | DailyStatistics / SessionStatistics | 11 | settlement, open interest, open/high/low |
| 50 | LimitsBanding | 11 | price limits |
| 37 | Volume | 11 | |
| 52 / 53 | SnapshotFullRefresh / ...OrderBook | 59 / 28 | recovery feed |
| 54 / 55 / 56 | MDInstrumentDefinitionFuture / Option / Spread | 224 / 221 / 255 | instrument feed |
| 64-69 | LongQty variants | | |

Book 46 root: TransactTime u64 @0, MatchEventIndicator set @8. Group NoMDEntries (32-byte
entries): MDEntryPx PRICENULL9 @0, MDEntrySize i32 @8, SecurityID i32 @12, RptSeq u32 @16
(per-instrument sequence), NumberOfOrders i32 @20, MDPriceLevel u8 @24 (1 = top),
MDUpdateAction u8 @25 (0 New, 1 Change, 2 Delete, 3 DeleteThru, 4 DeleteFrom, 5 Overlay),
MDEntryType char @26 (`0` bid, `1` offer, `E`/`F` implied, `J` book reset), TradeableSize
i32 @27 (since v13). Group NoOrderIDEntries (`groupSize8Byte`, 24-byte entries): OrderID
u64, MDOrderPriority u64, MDDisplayQty i32, ReferenceID u8 (index into NoMDEntries),
OrderUpdateAction u8.

OrderBook 47 group (40 bytes): OrderID @0, MDOrderPriority @8, MDEntryPx @16, MDDisplayQty
@24, SecurityID @28, MDUpdateAction @32, MDEntryType @33.

TradeSummary 48 group (32 bytes): MDEntryPx PRICE9 @0, MDEntrySize @8, SecurityID @12,
RptSeq @16, NumberOfOrders @20, AggressorSide u8 @24 (0 none, 1 buy, 2 sell),
MDUpdateAction @25, MDTradeEntryID u32 @26; then NoOrderIDEntries (OrderID u64, LastQty
i32).

MatchEventIndicator bits: 0 last trade msg, 1 last volume, 2 last quote, 3 last stats, 4
last implied, 5 recovery, 7 end of event. SecurityTradingStatus: 2 halt, 4 close, 15 new
price indication, 17 ready to trade (open), 18 not available, 21 pre-open, 24 pre-cross,
25 cross, 26 post close, 103 no change.

MDInstrumentDefinitionFuture 54 carries Symbol char(20) @35, SecurityID @55, SecurityType
@59, CFICode @65, MaturityMonthYear @71, Currency @76, MinTradeVol @83, MaxTradeVol @87,
MinPriceIncrement PRICE9 @91, DisplayFactor @99, UnitOfMeasureQty @140, TradingReferencePrice
@148, HighLimitPrice @165, LowLimitPrice @173, MaxPriceVariation @181,
ContractMultiplier @199, MinPriceIncrementAmount @205, then groups (events such as
activation/last trade, feed types, lot rules).

## Simulator scope

A minimal `cme-sim` must implement:

- iLink 3 over TCP: SOFH + SBE header; Negotiate/NegotiationResponse (HMAC accepted
  without checking), Establish/EstablishmentAck, Sequence heartbeats with keep-alive
  lapse handling, Terminate, NotApplied on inbound gaps, RetransmitRequest/Retransmission
  for outbound replay; cancel on disconnect.
- NewOrderSingle (limit, market with protection, Day/GTC/FAK/FOK, DisplayQty iceberg,
  MinQty), OrderCancelRequest, OrderCancelReplaceRequest; responses ExecutionReportNew,
  ExecutionReportReject, ExecutionReportTradeOutright, ExecutionReportCancel,
  ExecutionReportModify, ExecutionReportElimination, OrderCancelReject,
  OrderCancelReplaceReject, BusinessReject.
- MDP 3.0 over TCP for the sim (same packet header and messages as UDP): ChannelReset,
  AdminHeartbeat, MDInstrumentDefinitionFuture, SecurityStatus (pre-open, open, halt,
  close, maintenance window), MDIncrementalRefreshBook (MBP, 10 levels), TradeSummary,
  SnapshotFullRefresh on connect, DailyStatistics for settlement.

Out of scope: spreads and implied prices, options, mass quotes, party details, RFQ,
MBOFD/MBOLD order-level books, BrokerTec/EBS variants, fault tolerance (primary/backup).

Not verified: the current `ilinkbinary.xml` (needs SFTP credentials); layouts here come
from schema version 5 and may have gained appended fields since. The HMAC canonical
string was read from the Negotiate page but not tested against a real gateway.
