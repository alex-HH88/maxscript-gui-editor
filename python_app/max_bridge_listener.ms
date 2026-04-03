/**
 * MAXScript GUI Editor — TCP Bridge Listener
 * Run this script ONCE inside 3ds Max to start the listener.
 * The Python app can then send code directly into Max via TCP.
 *
 * Port: 27120  (change BRIDGE_PORT below if needed)
 * Stop:  call stopBridgeListener() in the MAXScript Listener
 */

global BRIDGE_VERSION = "1.15"
global BRIDGE_PORT    = 27120

-- Declare globals without assignment to preserve existing values across re-FileIn
global _bridgeListener
global _bridgeRunning
global _bridgeTimer
-- Initialize only on first load (when still undefined)
if _bridgeListener == undefined do _bridgeListener = undefined
if _bridgeRunning  == undefined do _bridgeRunning  = false
if _bridgeTimer    == undefined do _bridgeTimer    = undefined

-- -----------------------------------------------------------------------
-- Protocol handler (runs on a background .NET thread)
-- -----------------------------------------------------------------------
fn handleClient clientSocket =
(
    try
    (
        local netStream = clientSocket.GetStream()
        local reader    = dotNetObject "System.IO.StreamReader" netStream
        local writer    = dotNetObject "System.IO.StreamWriter" netStream
        writer.AutoFlush = true

        -- Read length header:  8 hex digits + newline
        local header = reader.ReadLine()
        if header == undefined or header.count < 8 do
        (
            writer.WriteLine "ERROR:bad header"
            clientSocket.Close()
            return undefined
        )

        local payloadLen = 0
        try ( payloadLen = (execute ("0x" + header)) ) catch ()
        if payloadLen <= 0 do
        (
            writer.WriteLine "ERROR:bad length"
            clientSocket.Close()
            return undefined
        )

        -- Read exactly payloadLen bytes
        local buf = dotNetObject "System.Char[]" payloadLen
        local read = 0
        while read < payloadLen do
        (
            local n = reader.Read buf read (payloadLen - read)
            if n <= 0 do exit
            read += n
        )

        local code = (dotNetClass "System.String").new buf 0 read
        writer.WriteLine "OK"
        clientSocket.Close()

        -- Execute on the Max main thread via a queued callback
        -- (dotNet threads cannot call Max APIs directly)
        callbacks.addScript #filePostOpen ("execute " + (code as string)) id:#bridgeExec persistent:false
        -- Better: use a one-shot idle callback
        callbacks.removeScripts #systemPreNew id:#bridgeExec
        local safeCode = code  -- capture
        callbacks.addScript #systemPreNew ("execute " + dotNet.ValueToDotNetObject safeCode (dotNetClass "System.String")) \
            id:#bridgeExec persistent:false

        -- Simplest reliable method: write to a temp file and fileIn it
        local tmpFile = (getDir #temp) + "\\bridge_cmd.ms"
        local f = createFile tmpFile
        format "%" safeCode to:f
        close f
        callbacks.addScript #systemPreNew ("fileIn " + (dotNet.ValueToDotNetObject tmpFile (dotNetClass "System.String"))) \
            id:#bridgeExec2 persistent:false
    )
    catch ( format "Bridge handler error: %\n" (getCurrentException()) )
)

-- -----------------------------------------------------------------------
-- Code queue (flushed by poll timer on the main thread)
-- -----------------------------------------------------------------------
global _bridgePendingCode = #()

fn processBridgeQueue =
(
    if _bridgePendingCode.count == 0 do return undefined
    local code = _bridgePendingCode[1]
    deleteItem _bridgePendingCode 1
    try ( execute code )
    catch ( format "Bridge execute error: %\n" (getCurrentException()) )
)

fn _closeClient clientSocket unused =
(
    try
    (
        local sd = (dotNetClass "System.Net.Sockets.SocketShutdown").Both
        clientSocket.Client.Shutdown sd
    ) catch ()
    try ( clientSocket.Close() ) catch ()
)

fn _readLine netStream =
(
    -- Read bytes one-at-a-time until LF, return as string (no StreamReader buffering)
    local byteType = dotNetClass "System.Byte"
    local oneByte  = (dotNetClass "System.Array").CreateInstance byteType 1
    local chars    = ""
    local limit    = 64
    while limit > 0 do
    (
        limit -= 1
        local n = netStream.Read oneByte 0 1
        if n <= 0 do exit
        local b = (dotNetClass "System.Convert").ToChar oneByte[0]
        if b == "\n" do exit
        if b != "\r" do chars += b as string
    )
    chars
)

fn handleClientV2 clientSocket =
(
    try
    (
        local netStream = clientSocket.GetStream()

        local header = _readLine netStream

        -- handle ping
        if header == "-- ping" do
        (
            local resp = (dotNetClass "System.Text.Encoding").UTF8.GetBytes "OK:pong\n"
            netStream.Write resp 0 resp.Length
            _closeClient clientSocket undefined
            return undefined
        )

        if header == undefined or header.count < 8 do
        (
            local resp = (dotNetClass "System.Text.Encoding").UTF8.GetBytes "ERROR:bad_header\n"
            netStream.Write resp 0 resp.Length
            _closeClient clientSocket undefined
            return undefined
        )

        local payloadLen = 0
        try ( payloadLen = (execute ("0x" + (trimRight (trimLeft header)))) ) catch ()
        if payloadLen == undefined or payloadLen <= 0 do
        (
            local resp = (dotNetClass "System.Text.Encoding").UTF8.GetBytes "ERROR:bad_length\n"
            netStream.Write resp 0 resp.Length
            _closeClient clientSocket undefined
            return undefined
        )

        -- Read payload bytes directly from stream
        local buf      = (dotNetClass "System.Array").CreateInstance (dotNetClass "System.Byte") payloadLen
        local totalRead = 0
        while totalRead < payloadLen do
        (
            local n = netStream.Read buf totalRead (payloadLen - totalRead)
            if n <= 0 do exit
            totalRead += n
        )

        local code = (dotNetClass "System.Text.Encoding").UTF8.GetString buf 0 totalRead
        local okResp = (dotNetClass "System.Text.Encoding").UTF8.GetBytes "OK\n"
        netStream.Write okResp 0 okResp.Length
        _closeClient clientSocket undefined

        -- Queue for main-thread execution via timer
        append _bridgePendingCode code
    )
    catch
    (
        try ( clientSocket.Close() ) catch ()
        format "Bridge handler error: %\n" (getCurrentException())
    )
)

-- -----------------------------------------------------------------------
-- Poll tick — called every 50ms on the main thread via timer
-- -----------------------------------------------------------------------
fn _bridgePollTick s e =
(
    if not _bridgeRunning do return undefined
    try
    (
        if _bridgeListener != undefined and _bridgeListener.Pending() do
        (
            local client = _bridgeListener.AcceptTcpClient()
            handleClientV2 client
        )
        processBridgeQueue()
    )
    catch ( format "Bridge poll error: %\n" (getCurrentException()) )
)

-- -----------------------------------------------------------------------
-- Public API
-- -----------------------------------------------------------------------
fn startBridgeListener =
(
    if _bridgeRunning do
    (
        format "Bridge listener already running on port %.\n" BRIDGE_PORT
        return undefined
    )

    -- Stop any previous listener still holding the port
    try ( if _bridgeListener != undefined do _bridgeListener.Stop() ) catch ()
    _bridgeListener = undefined

    local ipAny     = (dotNetClass "System.Net.IPAddress").Any
    local endpoint  = dotNetObject "System.Net.IPEndPoint" ipAny BRIDGE_PORT
    _bridgeListener = dotNetObject "System.Net.Sockets.TcpListener" endpoint
    _bridgeListener.Start()

    _bridgePendingCode = #()
    _bridgeRunning     = true

    -- Single 50ms timer: polls for incoming connections and flushes the queue
    if _bridgeTimer != undefined do ( _bridgeTimer.Stop() )
    _bridgeTimer = dotNetObject "System.Windows.Forms.Timer"
    _bridgeTimer.Interval = 50
    dotNet.addEventHandler _bridgeTimer "Tick" _bridgePollTick
    _bridgeTimer.Start()

    format "=== MAXScript GUI Editor Bridge Listener v% started on port % ===\n" BRIDGE_VERSION BRIDGE_PORT
    format "    Stop with: stopBridgeListener()\n"
)

fn stopBridgeListener =
(
    _bridgeRunning = false
    if _bridgeTimer != undefined do ( _bridgeTimer.Stop() ; _bridgeTimer = undefined )
    try ( if _bridgeListener != undefined do ( _bridgeListener.Stop() ; _bridgeListener = undefined ) ) catch ()
    format "Bridge listener stopped.\n"
)

-- Auto-start
startBridgeListener()
