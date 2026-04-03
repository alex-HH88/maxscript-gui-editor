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

fn _closeClient clientSocket writer =
(
    try ( if writer != undefined do writer.Flush() ) catch ()
    try
    (
        local sd = (dotNetClass "System.Net.Sockets.SocketShutdown").Both
        clientSocket.Client.Shutdown sd
    ) catch ()
    try ( clientSocket.Close() ) catch ()
)

fn handleClientV2 clientSocket =
(
    try
    (
        local netStream = clientSocket.GetStream()
        local reader    = dotNetObject "System.IO.StreamReader" netStream
        local writer    = dotNetObject "System.IO.StreamWriter" netStream
        writer.AutoFlush = true

        -- Read header line
        local header = ""
        local limit  = 128
        while limit > 0 do
        (
            limit -= 1
            local b = netStream.ReadByte()
            if b < 0 do exit
            if b == 10 do exit          -- LF
            if b != 13 do               -- skip CR
                header += bit.intAsChar b
        )

        -- handle ping
        if header == "-- ping" do
        (
            writer.WriteLine "OK:pong"
            _closeClient clientSocket writer
            return undefined
        )

        if header == undefined or header.count < 8 do
        (
            writer.WriteLine "ERROR:bad_header"
            _closeClient clientSocket writer
            return undefined
        )

        local payloadLen = 0
        try ( payloadLen = (execute ("0x" + (trimRight (trimLeft header)))) ) catch ()
        if payloadLen == undefined or payloadLen <= 0 do
        (
            writer.WriteLine "ERROR:bad_length"
            _closeClient clientSocket writer
            return undefined
        )

        -- Read payload byte-by-byte (avoids .NET array creation issues)
        local code = ""
        for i = 1 to payloadLen do
        (
            local b = netStream.ReadByte()
            if b < 0 do exit
            code += bit.intAsChar b
        )

        writer.WriteLine "OK"
        _closeClient clientSocket writer

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
