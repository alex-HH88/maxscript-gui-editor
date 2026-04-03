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

-- Preserve existing instances across re-FileIn so we can stop them cleanly
if not (globalVars.isGlobal "_bridgeThread")   do global _bridgeThread   = undefined
if not (globalVars.isGlobal "_bridgeListener") do global _bridgeListener = undefined
if not (globalVars.isGlobal "_bridgeRunning")  do global _bridgeRunning  = false

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
-- Proper execution approach: use a timer to run code on the main thread
-- -----------------------------------------------------------------------
global _bridgePendingCode = #()
global _bridgeTimer = undefined

fn processBridgeQueue =
(
    if _bridgePendingCode.count == 0 do return undefined
    local code = _bridgePendingCode[1]
    deleteItem _bridgePendingCode 1
    try ( execute code )
    catch ( format "Bridge execute error: %\n" (getCurrentException()) )
)

fn handleClientV2 clientSocket =
(
    try
    (
        local netStream = clientSocket.GetStream()
        local reader    = dotNetObject "System.IO.StreamReader" netStream
        local writer    = dotNetObject "System.IO.StreamWriter" netStream
        writer.AutoFlush = true

        local header = reader.ReadLine()

        -- handle ping
        if header == "-- ping" do
        (
            writer.WriteLine "OK:pong"
            clientSocket.Close()
            return undefined
        )

        if header == undefined or header.count < 8 do
        (
            writer.WriteLine "ERROR:bad_header"
            clientSocket.Close()
            return undefined
        )

        local payloadLen = 0
        try ( payloadLen = (execute ("0x" + (trimRight (trimLeft header)))) ) catch ()
        if payloadLen == undefined or payloadLen <= 0 do
        (
            writer.WriteLine "ERROR:bad_length"
            clientSocket.Close()
            return undefined
        )

        -- Read payload
        local buf = dotNetObject "System.Char[]" payloadLen
        local totalRead = 0
        while totalRead < payloadLen do
        (
            local n = reader.Read buf totalRead (payloadLen - totalRead)
            if n <= 0 do exit
            totalRead += n
        )

        local code = (dotNetClass "System.String").new buf 0 totalRead
        writer.WriteLine "OK"
        clientSocket.Close()

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
-- Listener loop (runs on background thread)
-- -----------------------------------------------------------------------
fn listenerLoop listener =
(
    format "Bridge listener started on port %\n" BRIDGE_PORT
    while _bridgeRunning do
    (
        try
        (
            if listener.Pending() do
            (
                local client = listener.AcceptTcpClient()
                handleClientV2 client
            )
            -- sleep 50ms to avoid busy-wait
            (dotNetClass "System.Threading.Thread").Sleep 50
        )
        catch
        (
            if _bridgeRunning do
                format "Bridge listener error: %\n" (getCurrentException())
        )
    )
    listener.Stop()
    format "Bridge listener stopped.\n"
)

-- Top-level entry point for the background thread (no closure needed)
fn _bridgeLoopFn = ( listenerLoop _bridgeListener )

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

    -- Create a 50ms tick timer to flush the code queue on the main thread
    if _bridgeTimer != undefined do ( _bridgeTimer.enabled = false )
    _bridgeTimer = dotNetObject "System.Windows.Forms.Timer"
    _bridgeTimer.Interval = 50
    dotNet.addEventHandler _bridgeTimer "Tick" (fn s e = processBridgeQueue())
    _bridgeTimer.Start()

    _bridgePendingCode = #()
    _bridgeRunning     = true

    -- Stop any previous listener still holding the port
    try ( if _bridgeListener != undefined do _bridgeListener.Stop() ) catch ()
    _bridgeListener = undefined

    local ipAny      = (dotNetClass "System.Net.IPAddress").Any
    local endpoint   = dotNetObject "System.Net.IPEndPoint" ipAny BRIDGE_PORT
    _bridgeListener  = dotNetObject "System.Net.Sockets.TcpListener" endpoint
    _bridgeListener.Start()

    local tsDelegate = dotNet.createDelegate "System.Threading.ThreadStart" _bridgeLoopFn
    _bridgeThread = dotNetObject "System.Threading.Thread" tsDelegate
    _bridgeThread.IsBackground = true
    _bridgeThread.Start()

    format "=== MAXScript GUI Editor Bridge Listener v% started on port % ===\n" BRIDGE_VERSION BRIDGE_PORT
    format "    Stop with: stopBridgeListener()\n"
)

fn stopBridgeListener =
(
    _bridgeRunning = false
    if _bridgeTimer != undefined do ( _bridgeTimer.Stop() ; _bridgeTimer = undefined )
    format "Bridge listener stopping...\n"
)

-- Auto-start
startBridgeListener()
